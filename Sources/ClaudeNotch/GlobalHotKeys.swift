import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts. Uses the Carbon hot key API, which needs no Accessibility permission and never
/// sees any other keystrokes.
final class GlobalHotKeys {
    struct Shortcut {
        let keyCode: Int
        let modifiers: Int
        let handler: () -> Void
    }

    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    /// Registers the shortcuts; returns how many the system accepted (another app may already own one).
    @discardableResult
    func register(_ shortcuts: [Shortcut]) -> Int {
        unregister()
        installEventHandler()
        for (index, shortcut) in shortcuts.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x434E4348), id: id)   // 'CNCH'
            guard RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
                  let ref else { continue }
            refs.append(ref)
            handlers[id] = shortcut.handler
        }
        return refs.count
    }

    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        handlers = [:]
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue().handlers[hotKeyID.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    deinit {
        unregister()
        eventHandler.map { RemoveEventHandler($0) }
    }
}
