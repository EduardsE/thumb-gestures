// Follow hand: during a hold, the Space follows the hand like a trackpad swipe.
// On release, macOS completes the switch or goes back, from the offset and the
// exit speed. This file does no I/O.

public enum FollowOutput: Equatable {
    case frame(SwipeFrame)
    case missionControl
}

public struct FollowGesture {
    /// Movement, in counts, before a swipe starts. Below it, a release is a click.
    public static let deadZone = 30
    /// The exit speed uses the movement of the last 0.1 s before the release.
    public static let sampleWindow = 0.1

    /// Mouse counts for one full Space.
    public let scale: Double
    /// Multiplier for the exit speed (offsets per second).
    public let exitFactor: Double

    private var isHeld = false
    private var swiping = false
    private var total = 0
    private var samples: [(time: Double, offset: Double)] = []

    public init(scale: Double, exitFactor: Double) {
        self.scale = max(1, scale)
        self.exitFactor = exitFactor
    }

    /// Moving left gives a positive offset: the Space on the right comes in.
    private var offset: Double { -Double(total) / scale }

    public mutating func handle(_ event: ThumbEvent, now: Double) -> [FollowOutput] {
        switch event {
        case .button(pressed: true):
            // The mouse can report "pressed" again during a hold. Keep the hold.
            if !isHeld {
                reset()
                isHeld = true
            }
            return []
        case .button(pressed: false):
            guard isHeld else { return [] }
            defer { reset() }
            guard swiping else { return [.missionControl] }
            return [.frame(SwipeFrame(offset: offset, phase: .ended, exitSpeed: exitSpeed(at: now)))]
        case .move(let dx):
            guard isHeld else { return [] }
            total += dx
            var outputs: [FollowOutput] = []
            if !swiping {
                guard abs(total) > Self.deadZone else { return [] }
                swiping = true
                outputs.append(.frame(SwipeFrame(offset: 0, phase: .began, exitSpeed: 0)))
            }
            samples.append((now, offset))
            samples.removeAll { now - $0.time > Self.sampleWindow }
            outputs.append(.frame(SwipeFrame(offset: offset, phase: .changed, exitSpeed: 0)))
            return outputs
        case .linked:
            // Do not leave a swipe open when the mouse connects or disconnects.
            defer { reset() }
            return swiping ? [.frame(SwipeFrame(offset: offset, phase: .ended, exitSpeed: 0))] : []
        }
    }

    public mutating func reset() {
        isHeld = false
        swiping = false
        total = 0
        samples = []
    }

    /// Offsets per second over the last sample window. 0 if the hand stopped before the release.
    private func exitSpeed(at now: Double) -> Double {
        let recent = samples.filter { now - $0.time <= Self.sampleWindow }
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return 0 }
        return (last.offset - first.offset) / (last.time - first.time) * exitFactor
    }
}
