import Foundation

/// Makes sure only one copy of the app runs, using a lock file. The lock belongs to the process, so it is released
/// automatically when the app quits or crashes; nothing is left behind to clean up.
public final class SingleInstance {
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)   // closing the file releases the lock
    }

    /// Takes the lock, or returns nil if another copy holds it. Waits a little first, so a copy that is just
    /// shutting down (a restart from the installer) has time to let go.
    public static func acquire(lockFile: URL, waitingUpTo wait: TimeInterval = 0) -> SingleInstance? {
        try? FileManager.default.createDirectory(at: lockFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(lockFile.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return nil }

        let deadline = Date().addingTimeInterval(wait)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard Date() < deadline else {
                close(descriptor)
                return nil
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return SingleInstance(descriptor: descriptor)
    }
}
