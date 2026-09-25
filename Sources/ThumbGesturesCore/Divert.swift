// When to divert the thumb button. This file does no I/O.
//
// A divert waits for mouse replies in a nested run loop, so a new trigger
// (a connect, a wake) or a stop signal can arrive during a divert. The
// coordinator makes sure that diverts never nest, that a trigger during a
// divert causes one more divert after it, that a failed divert is retried
// with a backoff, and that a stop waits until the divert ends.

public struct DivertCoordinator {
    public enum Next: Equatable {
        case idle
        case runAgain
        case retry(after: Double)
        case quit
    }

    public static let retryDelays: [Double] = [2, 5, 15, 30]

    public private(set) var isRunning = false
    /// Failed diverts in a row.
    public private(set) var failures = 0
    private var again = false
    private var quit = false

    public init() {}

    /// Returns true if the caller must start a divert now.
    public mutating func begin() -> Bool {
        guard !isRunning, !quit else {
            again = true
            return false
        }
        isRunning = true
        again = false
        return true
    }

    /// Call when a divert ends. Returns what the caller must do next.
    public mutating func end(success: Bool) -> Next {
        isRunning = false
        failures = success ? 0 : failures + 1
        if quit { return .quit }
        if again { return .runAgain }
        if success { return .idle }
        return .retry(after: Self.retryDelays[min(failures, Self.retryDelays.count) - 1])
    }

    /// Returns true if the caller can undivert and exit now.
    /// During a divert, the caller must wait for `end`, which then returns `.quit`.
    public mutating func requestQuit() -> Bool {
        quit = true
        return !isRunning
    }
}
