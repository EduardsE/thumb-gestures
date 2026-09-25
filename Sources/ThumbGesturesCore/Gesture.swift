// The thumb button gesture: a click, or a hold with a horizontal movement.
// This file does no I/O.

public enum GestureAction: Equatable {
    case missionControl
    case spaceLeft
    case spaceRight
}

public struct Gesture {
    /// Horizontal movement, in mouse counts, that starts a Space switch.
    public let distance: Int
    public private(set) var isHeld = false
    private var total = 0
    private var switched = false

    public init(distance: Int) {
        self.distance = max(1, distance)
    }

    public mutating func handle(_ event: ThumbEvent) -> GestureAction? {
        switch event {
        case .button(pressed: true):
            // The mouse can report "pressed" again during a hold. Keep the hold.
            if !isHeld {
                isHeld = true
                total = 0
                switched = false
            }
            return nil
        case .button(pressed: false):
            guard isHeld else { return nil }
            isHeld = false
            return switched ? nil : .missionControl
        case .move(let dx):
            guard isHeld, !switched else { return nil }
            total += dx
            guard abs(total) >= distance else { return nil }
            switched = true
            // Like a natural trackpad swipe: moving left pushes the Space away and shows the one on the right.
            return total < 0 ? .spaceRight : .spaceLeft
        case .linked:
            // A release can get lost while the mouse reconnects.
            reset()
            return nil
        }
    }

    public mutating func reset() {
        isHeld = false
        total = 0
        switched = false
    }
}
