import AppKit

// Housekeeping commands (`install-hooks`, `status`, …) run and exit; with no arguments the app starts.
if let exitCode = CommandLineTool.run(arguments: Array(CommandLine.arguments.dropFirst())) {
    exit(exitCode)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
let delegate = AppDelegate()
application.delegate = delegate
application.run()
