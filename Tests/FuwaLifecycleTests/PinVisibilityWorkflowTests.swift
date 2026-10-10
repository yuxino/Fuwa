import FuwaCore
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct PinVisibilityWorkflowTests {
    @Test func globalRestoreStillHonorsApplicationRule() {
        var policy = PinVisibilityPolicy(activeApplicationBundleIdentifier: "com.apple.Terminal", ownBundleIdentifier: "app.fuwa")
        var options = PinOptions()
        options.applicationScopeBundleIdentifier = "com.apple.Safari"
        #expect(policy.suppresses(options))
        policy.arePinsHidden = true
        policy.applicationActivated(bundleIdentifier: "com.apple.Safari")
        #expect(policy.suppresses(options))
        policy.arePinsHidden = false
        #expect(!policy.suppresses(options))
        policy.applicationActivated(bundleIdentifier: "com.apple.Terminal")
        #expect(policy.suppresses(options))
    }

    @Test func openingFuwaDoesNotHideTheWorkingApplicationsReference() {
        var policy = PinVisibilityPolicy(activeApplicationBundleIdentifier: "com.apple.Safari", ownBundleIdentifier: "app.fuwa")
        var options = PinOptions()
        options.applicationScopeBundleIdentifier = "com.apple.Safari"
        let bundleActivationChangedPolicy = policy.applicationActivated(bundleIdentifier: "app.fuwa")
        #expect(!bundleActivationChangedPolicy)
        #expect(!policy.suppresses(options))
        let processActivationChangedPolicy = policy.applicationActivated(bundleIdentifier: nil, isFuwa: true)
        #expect(!processActivationChangedPolicy)
        #expect(!policy.suppresses(options))
    }

    @Test func unknownForegroundHidesBoundPinsButLeavesUnboundPinsAvailable() {
        var policy = PinVisibilityPolicy(activeApplicationBundleIdentifier: "com.apple.Safari", ownBundleIdentifier: nil)
        var options = PinOptions()
        options.applicationScopeBundleIdentifier = "com.apple.Safari"
        let foregroundChanged = policy.applicationActivated(bundleIdentifier: nil)
        #expect(foregroundChanged)
        #expect(policy.suppresses(options))
        #expect(!policy.suppresses(PinOptions()))
        policy.arePinsHidden = true
        #expect(policy.suppresses(PinOptions()))
    }

    @Test func applicationPolicyComposesWithNativeSpaceScope() {
        let policy = PinVisibilityPolicy(activeApplicationBundleIdentifier: "com.apple.Safari", ownBundleIdentifier: "app.fuwa")
        var options = PinOptions()
        options.applicationScopeBundleIdentifier = "com.apple.Safari"
        options.spaceScope = .currentSpace
        #expect(!policy.suppresses(options))
        options.spaceScope = .allSpaces
        #expect(!policy.suppresses(options))
        // Space placement belongs to AppKit's public collection behavior;
        // application rules never silently replace the user's Space choice.
    }

    @Test func addingPinRevealsHiddenGroupAndStillHonorsApplicationRule() {
        var policy = PinVisibilityPolicy(activeApplicationBundleIdentifier: "org.example.editor", ownBundleIdentifier: "app.fuwa")
        var options = PinOptions()
        options.applicationScopeBundleIdentifier = "org.example.browser"
        policy.arePinsHidden = true
        let requestRevision = policy.globalVisibilityRevision
        let revealedGroup = policy.revealAfterAddingPin(ifUnchangedSince: requestRevision)
        #expect(revealedGroup)
        #expect(!policy.arePinsHidden)
        #expect(policy.suppresses(options))
        policy.applicationActivated(bundleIdentifier: "org.example.browser")
        #expect(!policy.suppresses(options))
    }

    @Test func latePinCompletionPreservesNewerHideIntent() {
        var policy = PinVisibilityPolicy(activeApplicationBundleIdentifier: "org.example.editor", ownBundleIdentifier: "app.fuwa")
        let visibleRequest = policy.globalVisibilityRevision
        policy.arePinsHidden = true
        let olderAddRevealedGroup = policy.revealAfterAddingPin(ifUnchangedSince: visibleRequest)
        #expect(!olderAddRevealedGroup)
        #expect(policy.arePinsHidden)

        let hiddenRequest = policy.globalVisibilityRevision
        policy.arePinsHidden = false
        policy.arePinsHidden = true
        let addRevealedAfterNewerShowHide = policy.revealAfterAddingPin(ifUnchangedSince: hiddenRequest)
        #expect(!addRevealedAfterNewerShowHide)
        #expect(policy.arePinsHidden)

        let latestRequest = policy.globalVisibilityRevision
        let latestAddRevealedGroup = policy.revealAfterAddingPin(ifUnchangedSince: latestRequest)
        #expect(latestAddRevealedGroup)
        #expect(!policy.arePinsHidden)
    }

    @Test func overlappingHideAndRestoreConvergeToLatestIntent() async throws {
        let reconciler = PinVisibilityReconciler()
        let entered = VisibilitySignal()
        let finishHide = VisibilitySignal()
        let restoreSubmitted = VisibilitySignal()
        var requestedHidden = true
        var applied: [Bool] = []
        let first = Task { @MainActor in
            try await reconciler.reconcile {
                let hidden = requestedHidden
                if applied.isEmpty {
                    entered.release()
                    await finishHide.wait()
                }
                applied.append(hidden)
            }
        }
        await entered.wait()
        requestedHidden = false
        let second = Task { @MainActor in
            restoreSubmitted.release()
            try await reconciler.reconcile { Issue.record("Overlapping requests should share the existing worker") }
        }
        await restoreSubmitted.wait()
        finishHide.release()
        try await first.value
        try await second.value
        #expect(applied == [true, false])
    }

    @Test func clearInvalidatesOldWorkWithoutErasingNewWorker() async throws {
        let reconciler = PinVisibilityReconciler()
        let oldEntered = VisibilitySignal()
        let finishOld = VisibilitySignal()
        let newEntered = VisibilitySignal()
        let finishNew = VisibilitySignal()
        let followupSubmitted = VisibilitySignal()
        var applied: [String] = []
        let old = Task { @MainActor in
            try await reconciler.reconcile {
                oldEntered.release()
                await finishOld.wait()
            }
        }
        await oldEntered.wait()
        reconciler.invalidate()
        let replacement = Task { @MainActor in
            try await reconciler.reconcile {
                newEntered.release()
                await finishNew.wait()
                applied.append("new")
            }
        }
        await newEntered.wait()
        finishOld.release()
        do {
            try await old.value
            Issue.record("A cleared visibility operation must finish as cancelled")
        } catch is CancellationError {
            // Expected even when an underlying asynchronous stop ignores cancellation.
        }
        let followup = Task { @MainActor in
            followupSubmitted.release()
            try await reconciler.reconcile { Issue.record("The replacement worker must remain registered") }
        }
        await followupSubmitted.wait()
        finishNew.release()
        try await replacement.value
        try await followup.value
        #expect(applied == ["new", "new"])
    }

    @Test func aFailedOperationCanBeRetried() async throws {
        let reconciler = PinVisibilityReconciler()
        do {
            try await reconciler.reconcile { throw VisibilityProbeError.expected }
            Issue.record("The operation's failure must reach its caller")
        } catch VisibilityProbeError.expected {}
        var retried = false
        try await reconciler.reconcile { retried = true }
        #expect(retried)
    }

    @Test func failureForOldIntentDoesNotDiscardQueuedRestore() async throws {
        let reconciler = PinVisibilityReconciler()
        let entered = VisibilitySignal()
        let finishOld = VisibilitySignal()
        let restoreSubmitted = VisibilitySignal()
        var requestedHidden = true
        var restored = false
        let first = Task { @MainActor in
            try await reconciler.reconcile {
                if requestedHidden {
                    entered.release()
                    await finishOld.wait()
                    throw VisibilityProbeError.expected
                }
                restored = true
            }
        }
        await entered.wait()
        requestedHidden = false
        let restore = Task { @MainActor in
            restoreSubmitted.release()
            try await reconciler.reconcile { Issue.record("Restore should reuse the pending worker") }
        }
        await restoreSubmitted.wait()
        finishOld.release()
        try await first.value
        try await restore.value
        #expect(restored)
    }
}

@MainActor
private final class VisibilitySignal {
    private var isReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isReleased { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        let waiting = waiters
        waiters.removeAll()
        for continuation in waiting { continuation.resume() }
    }
}

private enum VisibilityProbeError: Error {
    case expected
}
