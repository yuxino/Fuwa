import Foundation
import FuwaCore

/// Global hiding and a pin's application rule are independent. Restoring the
/// group must never make a reference appear over an unrelated application.
struct PinVisibilityPolicy {
    var arePinsHidden = false {
        didSet {
            if arePinsHidden != oldValue { globalVisibilityRevision &+= 1 }
        }
    }
    private(set) var globalVisibilityRevision: UInt64 = 0
    private(set) var activeApplicationBundleIdentifier: String?
    private let ownBundleIdentifier: String?

    init(activeApplicationBundleIdentifier: String?, ownBundleIdentifier: String?) {
        self.activeApplicationBundleIdentifier = activeApplicationBundleIdentifier
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    /// Opening Fuwa's controls leaves the last working application's rule in
    /// force. Otherwise a reference would disappear while being configured.
    @discardableResult
    mutating func applicationActivated(bundleIdentifier: String?, isFuwa: Bool = false) -> Bool {
        guard !isFuwa,
              ownBundleIdentifier == nil || bundleIdentifier != ownBundleIdentifier else {
            return false
        }
        guard activeApplicationBundleIdentifier != bundleIdentifier else { return false }
        activeApplicationBundleIdentifier = bundleIdentifier
        return true
    }

    func suppresses(_ options: PinOptions) -> Bool {
        if arePinsHidden { return true }
        guard let application = options.applicationScopeBundleIdentifier else { return false }
        return application != activeApplicationBundleIdentifier
    }

    /// A completed add reveals an already hidden group, but a visibility choice
    /// made while its target was resolving takes precedence over the older add.
    @discardableResult
    mutating func revealAfterAddingPin(ifUnchangedSince revision: UInt64) -> Bool {
        guard globalVisibilityRevision == revision, arePinsHidden else { return false }
        arePinsHidden = false
        return true
    }
}

/// Coalesces overlapping visibility requests without cancelling stream teardown
/// midway. A request arriving during an await always gets a later pass using
/// the latest intent. Clearing pins invalidates the old worker immediately.
@MainActor
final class PinVisibilityReconciler {
    typealias Operation = @MainActor () async throws -> Void

    private var revision: UInt64 = 0
    private var generation: UInt64 = 0
    private var worker: Task<Void, Error>?
    private var workerToken: UUID?

    func reconcile(_ operation: @escaping Operation) async throws {
        revision &+= 1
        if let worker {
            try await worker.value
            return
        }

        let requestedGeneration = generation
        let token = UUID()
        workerToken = token
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            defer {
                // An invalidated worker must not erase its replacement.
                if self.workerToken == token {
                    self.worker = nil
                    self.workerToken = nil
                }
            }
            while true {
                try Task.checkCancellation()
                guard self.generation == requestedGeneration else {
                    throw CancellationError()
                }
                let requestedRevision = self.revision
                do {
                    try await operation()
                } catch {
                    try Task.checkCancellation()
                    guard self.generation == requestedGeneration else {
                        throw CancellationError()
                    }
                    // A failure for an obsolete intent must not prevent a
                    // queued restore from getting its own reconciliation pass.
                    if self.revision == requestedRevision { throw error }
                    continue
                }
                try Task.checkCancellation()
                guard self.generation == requestedGeneration else {
                    throw CancellationError()
                }
                if self.revision == requestedRevision { return }
            }
        }
        worker = task
        try await task.value
    }

    func invalidate() {
        generation &+= 1
        worker?.cancel()
        worker = nil
        workerToken = nil
    }
}
