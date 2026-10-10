import Foundation

/// Bounded signatures compare image content, rather than the arrival of SCK frames.
public struct CapturedPictureActivity: Sendable {
    public let idleDelay: TimeInterval
    public private(set) var isIdle = false
    private var previousSamples: [UInt8]?
    private var previousDimensions: PixelDimensions?
    private var lastChangeTime: TimeInterval?

    public init(idleDelay: TimeInterval = 15) { self.idleDelay = max(1, idleDelay) }

    @discardableResult
    public mutating func observe(samples: [UInt8], dimensions: PixelDimensions,
                                 at time: TimeInterval) -> Bool {
        guard !samples.isEmpty, time.isFinite else { return false }
        let changed: Bool
        if let previousSamples, previousSamples.count == samples.count, previousDimensions == dimensions {
            // Ignore tiny capture/rounding noise. Any sampled color change of
            // eight levels is enough to restore the user's selected frame rate.
            changed = zip(previousSamples, samples).contains { abs(Int($0) - Int($1)) >= 8 }
        } else { changed = true }
        if changed || lastChangeTime == nil {
            // Retain the last significant picture as the baseline so gradual
            // changes accumulate rather than disappearing frame by frame.
            previousSamples = samples
            previousDimensions = dimensions
            lastChangeTime = time
            isIdle = false
        }
        _ = evaluate(at: time)
        return changed
    }

    @discardableResult
    public mutating func evaluate(at time: TimeInterval) -> Bool {
        let previous = isIdle
        if let lastChangeTime, time.isFinite { isIdle = time - lastChangeTime >= idleDelay }
        return previous != isIdle
    }

    public mutating func reset() {
        previousSamples = nil
        previousDimensions = nil
        lastChangeTime = nil
        isIdle = false
    }
}

/// Async restoration must not reveal pixels after a newer hide or privacy stop.
public struct CapturePresentationSuppression: Sendable {
    public private(set) var isSuppressed = false
    public private(set) var revision: UInt64 = 0
    private var stopped = false

    public init() {}

    @discardableResult
    public mutating func change(to suppressed: Bool) -> UInt64 {
        revision &+= 1
        isSuppressed = suppressed
        return revision
    }

    public mutating func stop() { revision &+= 1; stopped = true }

    public func allowsRestore(revision candidate: UInt64) -> Bool {
        !stopped && !isSuppressed && revision == candidate
    }
}
