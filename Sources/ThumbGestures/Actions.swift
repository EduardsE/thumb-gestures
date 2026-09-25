import AppKit
import CoreGraphics
import ThumbGesturesCore

enum Actions {
    static func perform(_ action: GestureAction) {
        switch action {
        case .missionControl:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        case .spaceLeft:
            pressControlArrow(keyCode: 123)  // ⌃← Move left a space
        case .spaceRight:
            pressControlArrow(keyCode: 124)  // ⌃→ Move right a space
        }
    }

    /// Arrow keys carry the Fn flag. The system shortcut needs Control + Fn to match.
    private static func pressControlArrow(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = [.maskControl, .maskSecondaryFn]
            event?.post(tap: .cghidEventTap)
        }
    }
}
