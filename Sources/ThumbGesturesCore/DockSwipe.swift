// The frames of a synthetic trackpad Space swipe (a "dock swipe").
// Unlike the ⌃← / ⌃→ shortcuts, a new swipe can interrupt the Space animation.
// This file does no I/O. Actions posts the frames as undocumented CGEvents.

/// IOHIDEventPhase values.
public enum SwipePhase: Int {
    case began = 1
    case changed = 2
    case ended = 4
}

public struct SwipeFrame: Equatable {
    public let offset: Double
    public let phase: SwipePhase
    public let exitSpeed: Double
}

public enum DockSwipe {
    // Tested on macOS 26: 20 steps, 8 ms apart, exit speed 3.
    public static let steps = 20
    public static let interval = 0.008
    public static let exitSpeed = 3.0

    /// The frames for a Space switch. An offset of +1 is a full swipe to the Space on the right.
    public static func frames(for action: GestureAction) -> [SwipeFrame] {
        let target: Double
        switch action {
        case .spaceRight: target = 1
        case .spaceLeft: target = -1
        case .missionControl: return []
        }
        var frames = [SwipeFrame(offset: 0, phase: .began, exitSpeed: 0)]
        for step in 1...steps {
            frames.append(SwipeFrame(offset: target * Double(step) / Double(steps), phase: .changed, exitSpeed: 0))
        }
        frames.append(SwipeFrame(offset: target, phase: .ended, exitSpeed: exitSpeed))
        return frames
    }
}
