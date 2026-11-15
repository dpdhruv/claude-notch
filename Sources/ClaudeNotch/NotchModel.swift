import SwiftUI
import AppKit
import Combine
import NotchCore

/// View model for the notch: which mode it is in, and why. Owns the data sources and decides when to alert.
final class NotchModel: ObservableObject {
    let monitor: SessionMonitor
    let broker: PermissionBroker
    let geometry: NotchGeometry

    @Published private(set) var mode: NotchMode = .collapsed
    @Published private(set) var alert: NotchAlert?
    /// Pointer position in the notch's own coordinates (origin top-left), refreshed while the list is open.
    @Published var pointer: CGPoint?
    private(set) var isHovering = false

    /// How much the notch may intrude: normal, quiet (paused) or hidden (a full-screen app is in front).
    @Published private(set) var presence: Presence = .normal
    @Published private(set) var policy: QuietPolicy
    private let preferences: UserDefaults
    private let isFullScreenAppActive: () -> Bool

    private let linker: SessionLinker
    private let alerts = AlertEngine()
    private var alertTimer: Timer?
    private var pendingCollapse: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var knownRequestIDs = Set<String>()

    /// - Parameter isFullScreenAppActive: asked once a second whether a full-screen app is in front.
    init(geometry: NotchGeometry, paths: Paths = .live, preferences: UserDefaults = .standard,
         isFullScreenAppActive: @escaping () -> Bool = { false }) {
        self.geometry = geometry
        self.preferences = preferences
        self.isFullScreenAppActive = isFullScreenAppActive
        self.policy = QuietPolicy(quietInFullScreen: preferences.object(forKey: Self.quietInFullScreenKey) as? Bool ?? true)
        self.monitor = SessionMonitor(paths: paths)
        self.broker = PermissionBroker(paths: paths)
        self.linker = SessionLinker(paths: paths)

        // dropFirst: the initial empty value is not a scan result, and must not become the alert baseline.
        monitor.$sessions.dropFirst().sink { [weak self] in self?.sessionsChanged($0) }.store(in: &cancellables)
        monitor.$now.sink { [weak self] in self?.clockTicked($0) }.store(in: &cancellables)
        broker.$pending.receive(on: DispatchQueue.main).sink { [weak self] in self?.requestsChanged($0) }.store(in: &cancellables)
    }

    func start() {
        broker.start()
        monitor.start()
    }

    func stop() {
        broker.stop()
        monitor.stop()
    }

    private static let quietInFullScreenKey = "quietInFullScreen"

    // MARK: Quiet mode

    var isPaused: Bool { policy.isPaused(at: Date()) }

    func setQuietInFullScreen(_ enabled: Bool) {
        policy.quietInFullScreen = enabled
        preferences.set(enabled, forKey: Self.quietInFullScreenKey)
        refreshPresence()
    }

    func pauseAlerts(for duration: TimeInterval = Config.pauseDuration) {
        policy.pausedUntil = Date().addingTimeInterval(duration)
        refreshPresence()
    }

    func resumeAlerts() {
        policy.pausedUntil = nil
        refreshPresence()
    }

    private func refreshPresence() {
        let next = policy.presence(fullScreenActive: isFullScreenAppActive(), now: Date())
        guard next != presence else { return }
        let wasNormal = presence == .normal
        presence = next

        if next != .normal {
            // Going quiet: put away anything that is showing.
            alertTimer?.invalidate()
            pendingCollapse?.cancel()
            if mode != .collapsed { mode = .collapsed }
        } else if wasNormal == false, !requests.isEmpty {
            // Back to normal with approvals still waiting: show them now.
            NSSound(named: "Sosumi")?.play()
            withAnimation(Motion.alert) { mode = .request }
        }
    }

    // MARK: What to draw

    var sessions: [ClaudeSession] { Array(monitor.sessions.prefix(NotchGeometry.maxSessionRows)) }
    var requests: [PermissionRequest] { broker.pending }
    var size: CGSize { geometry.size(for: mode, sessionCount: sessions.count, requestCount: requests.count) }

    var needsYouCount: Int { max(requests.count, monitor.sessions.filter { $0.state == .needsYou }.count) }
    var workingCount: Int { monitor.sessions.filter { $0.state == .working }.count }

    /// The idle session whose cache expires soonest.
    var nextCacheExpiry: (remaining: TimeInterval, cache: PromptCache)? {
        monitor.sessions
            .filter { $0.state != .working }
            .compactMap { session in session.cache.map { (remaining: $0.remaining(at: monitor.now), cache: $0) } }
            .filter { $0.remaining > 0 }
            .min { $0.remaining < $1.remaining }
    }

    func sessionInfo(forID id: String) -> (title: String, project: String) {
        guard let session = monitor.sessions.first(where: { $0.id == id }) else { return ("Claude session", "") }
        return (session.title, session.project)
    }

    /// The card under the pointer, if the list is open.
    var hoveredRow: Int? {
        guard mode == .expanded, let pointer else { return nil }
        return geometry.sessionRowIndex(at: pointer, sessionCount: sessions.count)
    }

    // MARK: Pointer

    func pointerEntered() {
        isHovering = true
        guard presence != .hidden, requests.isEmpty else { return }
        pendingCollapse?.cancel()
        alertTimer?.invalidate()
        withAnimation(Motion.reveal) { mode = .expanded }
    }

    func pointerExited() {
        isHovering = false
        pointer = nil
        guard requests.isEmpty else { return }
        pendingCollapse?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isHovering else { return }
            self.collapse()
        }
        pendingCollapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func collapse() {
        guard requests.isEmpty else { return }
        withAnimation(Motion.settle) { mode = .collapsed }
    }

    // MARK: Actions

    func answer(_ request: PermissionRequest, _ decision: PermissionDecision) {
        broker.respond(to: request, with: decision)
    }

    /// Opens a session in the Claude desktop app; for terminal sessions, copies the resume command instead.
    func open(sessionID id: String, title: String) {
        let linker = self.linker
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let link = linker.deepLink(forTranscript: id)   // reads every desktop session file, so not on the main thread
            DispatchQueue.main.async {
                if let link {
                    NSWorkspace.shared.open(link)
                    self?.collapse()
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(SessionLinker.resumeCommand(forTranscript: id), forType: .string)
                    self?.present(NotchAlert(kind: .info, title: title, message: "Not a desktop session — copied `claude --resume` command", sessionID: id), force: true)
                }
            }
        }
    }

    func openSession(atRow row: Int) {
        guard sessions.indices.contains(row) else { return }
        open(sessionID: sessions[row].id, title: sessions[row].title)
    }

    // MARK: Reacting to data

    private func sessionsChanged(_ sessions: [ClaudeSession]) {
        dropRequestsAnsweredElsewhere(sessions)
        alerts.alerts(forChangesIn: sessions).forEach { present($0) }
    }

    private func clockTicked(_ now: Date) {
        refreshPresence()
        alerts.alerts(forCachesIn: monitor.sessions, now: now).forEach { present($0) }
    }

    /// A request is stale if its session moved on after it was raised: it was answered in Claude's own dialog.
    private func dropRequestsAnsweredElsewhere(_ sessions: [ClaudeSession]) {
        for request in broker.pending {
            guard let session = sessions.first(where: { $0.id == request.sessionID }),
                  session.lastActivity > request.raisedAt.addingTimeInterval(Config.answeredElsewhereSlack) else { continue }
            broker.respond(to: request, with: .deferToApp)
        }
    }

    private func requestsChanged(_ requests: [PermissionRequest]) {
        let ids = Set(requests.map(\.id))
        let hasNew = !ids.subtracting(knownRequestIDs).isEmpty
        knownRequestIDs = ids
        objectWillChange.send()   // `requests` is derived from the broker, which this model does not publish itself

        guard !requests.isEmpty else {
            if mode == .request { withAnimation(Motion.settle) { mode = isHovering ? .expanded : .collapsed } }
            return
        }
        // While quiet the cards wait (they hand back to Claude's own dialog on their own) and appear when quiet ends.
        guard presence == .normal else { return }
        if hasNew { NSSound(named: "Sosumi")?.play() }
        alertTimer?.invalidate()
        withAnimation(Motion.alert) { mode = .request }
    }

    // MARK: Alerts

    /// Drops the notch down for a moment. Skipped while the pointer is over it, unless forced.
    private func present(_ alert: NotchAlert, force: Bool = false) {
        guard force || (!isHovering && presence == .normal), requests.isEmpty else { return }
        self.alert = alert
        if let sound = alert.kind.sound { NSSound(named: sound)?.play() }
        withAnimation(Motion.alert) { mode = .peek }

        alertTimer?.invalidate()
        alertTimer = Timer.scheduledTimer(withTimeInterval: alert.kind.displayDuration, repeats: false) { [weak self] _ in
            guard let self, !self.isHovering else { return }
            self.collapse()
        }
    }

    /// For screenshots and debugging: start with the list open. See `CLAUDE_NOTCH_EXPANDED` in the README.
    func forceExpanded() {
        isHovering = true
        mode = .expanded
    }
}
