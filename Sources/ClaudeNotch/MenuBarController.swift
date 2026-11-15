import AppKit
import Combine
import NotchCore

/// A small sparkle in the menu bar: what is going on at a glance, Pause, and Quit. Shown or hidden from the settings.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: NotchModel
    private var statusItem: NSStatusItem?
    private var observer: AnyCancellable?

    init(model: NotchModel) {
        self.model = model
        super.init()
        observer = model.$menuBarIconEnabled.receive(on: DispatchQueue.main).sink { [weak self] enabled in
            enabled ? self?.show() : self?.hide()
        }
    }

    private func show() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Claude Notch")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func hide() {
        statusItem.map { NSStatusBar.system.removeStatusItem($0) }
        statusItem = nil
    }

    // MARK: NSMenuDelegate

    /// Rebuilt each time it opens, so the numbers and Pause/Resume are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(label("Claude Notch \(Config.version)", bold: true))
        menu.addItem(label(summary()))
        if !model.allServers.isEmpty {
            let count = model.allServers.count
            menu.addItem(label("\(count) server\(count == 1 ? "" : "s") running"))
        }
        menu.addItem(.separator())
        menu.addItem(action(model.isPaused ? "Resume alerts" : "Pause alerts for 1 hour", #selector(togglePause)))
        menu.addItem(action("Hide menu bar icon", #selector(hideIcon)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Claude Notch", #selector(quit), key: "q"))
    }

    private func summary() -> String {
        var parts: [String] = []
        if model.needsYouCount > 0 { parts.append("\(model.needsYouCount) need you") }
        if model.workingCount > 0 { parts.append("\(model.workingCount) working") }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return model.monitor.sessions.isEmpty ? "No active sessions" : "All quiet"
    }

    private func label(_ text: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if bold { item.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.menuFont(ofSize: 0).withWeight(.semibold)]) }
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePause() { model.isPaused ? model.resumeAlerts() : model.pauseAlerts() }
    @objc private func hideIcon() { model.setMenuBarIconEnabled(false) }
    @objc private func quit() { NSApp.terminate(nil) }
}

private extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
