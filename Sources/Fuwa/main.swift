import AppKit
import FuwaCore

// Copies at different paths still share the shortcut and manage floating
// mirrors. Acquire ownership before constructing any controllers or panels.
let supportDirectory = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
).appendingPathComponent("Fuwa", isDirectory: true)
try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
guard let instanceLock = try SingleInstanceLock(
    url: supportDirectory.appendingPathComponent("running.lock")
) else {
    exit(0)
}

// Also respect an already-running older build that predates the lock.
if let existing = NSRunningApplication.runningApplications(
    withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.yuxino.fuwa"
).first(where: {
    $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        && $0.isFinishedLaunching && !$0.isTerminated
}) {
    existing.activate(options: [])
    exit(0)
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
// Match the saved Dock preference before login-item startup can show an icon.
// A visible management window temporarily supplies Dock presence either way.
application.setActivationPolicy(AppSettingsStore().keepInDock ? .regular : .accessory)

withExtendedLifetime((applicationDelegate, instanceLock)) {
    application.run()
}
