import AppKit
import CoreGraphics
import ThumbGesturesCore

enum Actions {
    static func perform(_ action: GestureAction) {
        switch action {
        case .missionControl:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        case .spaceLeft, .spaceRight:
            swipe(action)
        }
    }

    /// When the frames of the last swipe are all posted.
    private static var swipeEnd = DispatchTime.now()

    /// Posts the frames of a live Space swipe with a timer, so the run loop stays free.
    /// A swipe that is still being posted (about 0.2 s) finishes first.
    private static func swipe(_ action: GestureAction) {
        var time = max(DispatchTime.now(), swipeEnd)
        for frame in DockSwipe.frames(for: action) {
            DispatchQueue.main.asyncAfter(deadline: time) { post(frame) }
            time = time + DockSwipe.interval
        }
        swipeEnd = time
    }

    /// The undocumented event pair that a trackpad sends for a horizontal Space swipe.
    /// The field numbers are the same that Mac Mouse Fix uses. A macOS update can change them.
    private static func post(_ frame: SwipeFrame) {
        func field(_ number: UInt32) -> CGEventField { CGEventField(rawValue: number)! }

        guard let gesture = CGEvent(source: nil), let dock = CGEvent(source: nil) else { return }
        gesture.setDoubleValueField(field(55), value: 29)       // NSEventTypeGesture
        gesture.setDoubleValueField(field(41), value: 33231)

        dock.setDoubleValueField(field(55), value: 30)          // dock control event
        dock.setDoubleValueField(field(41), value: 33231)
        dock.setDoubleValueField(field(110), value: 23)         // kIOHIDEventTypeDockSwipe
        dock.setDoubleValueField(field(123), value: 1)          // horizontal
        dock.setDoubleValueField(field(165), value: 1)
        dock.setDoubleValueField(field(132), value: Double(frame.phase.rawValue))
        dock.setDoubleValueField(field(134), value: Double(frame.phase.rawValue))
        dock.setDoubleValueField(field(124), value: frame.offset)
        dock.setIntegerValueField(field(135), value: Int64(Float32(frame.offset).bitPattern))
        dock.setDoubleValueField(field(136), value: 0)
        if frame.phase == .ended {
            dock.setDoubleValueField(field(129), value: frame.exitSpeed)
            dock.setDoubleValueField(field(130), value: frame.exitSpeed)
        }
        dock.post(tap: .cgSessionEventTap)
        gesture.post(tap: .cgSessionEventTap)
    }
}
