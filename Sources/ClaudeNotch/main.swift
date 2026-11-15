import AppKit
import NotchCore

// Housekeeping commands (`install-hooks`, `status`, …) run and exit; with no arguments the app starts.
if let exitCode = CommandLineTool.run(arguments: Array(CommandLine.arguments.dropFirst())) {
    exit(exitCode)
}

// One notch is enough: a second copy (started by hand, or by a login item on top of one already running) just quits.
// Kept in a global so the lock lasts as long as the app does.
guard let instanceLock = SingleInstance.acquire(lockFile: Paths.live.instanceLock, waitingUpTo: 3) else {
    FileHandle.standardError.write(Data("Claude Notch is already running.\n".utf8))
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
let delegate = AppDelegate()
application.delegate = delegate
application.run()
