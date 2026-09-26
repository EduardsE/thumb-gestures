// Sends thumb button events to the gesture of the selected mode.
// A settings change during a hold waits for the next press, so a started
// live swipe always gets its end. This file does no I/O.

public enum ThumbOutput: Equatable {
    case missionControl
    case quickSwipe(GestureAction)
    case frame(SwipeFrame)
}

public struct ThumbController {
    public private(set) var preferences: Preferences
    private let exitFactor: Double
    private var pending: Preferences?
    private var isHeld = false
    private var quick: Gesture
    private var follow: FollowGesture

    public init(preferences: Preferences, exitFactor: Double) {
        self.preferences = preferences
        self.exitFactor = exitFactor
        quick = Gesture(distance: preferences.switchDistance)
        follow = FollowGesture(scale: preferences.followScale, exitFactor: exitFactor)
    }

    /// New settings. They take effect now, or at the next press if a hold is active.
    public mutating func apply(_ preferences: Preferences) {
        if isHeld {
            pending = preferences
        } else {
            use(preferences)
        }
    }

    public mutating func handle(_ event: ThumbEvent, now: Double) -> [ThumbOutput] {
        switch event {
        case .button(pressed: true):
            if !isHeld, let pending { use(pending) }
            isHeld = true
        case .button(pressed: false), .linked:
            isHeld = false
        case .move:
            break
        }

        switch preferences.mode {
        case .quickSwipe:
            guard let action = quick.handle(event) else { return [] }
            return [action == .missionControl ? .missionControl : .quickSwipe(action)]
        case .followHand:
            return follow.handle(event, now: now).map { output in
                switch output {
                case .frame(let frame): return .frame(frame)
                case .missionControl: return .missionControl
                }
            }
        }
    }

    /// Ends an open live swipe, so that macOS does not stay between two Spaces, and then resets.
    /// Use it before a divert, at a receiver removal, and at exit.
    public mutating func cancel() -> [ThumbOutput] {
        let outputs: [ThumbOutput] = follow.handle(.linked(false), now: 0).compactMap { output in
            if case .frame(let frame) = output { return .frame(frame) }
            return nil
        }
        reset()
        return outputs
    }

    public mutating func reset() {
        quick.reset()
        follow.reset()
        isHeld = false
        if let pending { use(pending) }
    }

    private mutating func use(_ preferences: Preferences) {
        self.preferences = preferences
        pending = nil
        quick = Gesture(distance: preferences.switchDistance)
        follow = FollowGesture(scale: preferences.followScale, exitFactor: exitFactor)
    }
}
