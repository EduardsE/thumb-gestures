import XCTest
@testable import ThumbGesturesCore

final class ThumbControllerTests: XCTestCase {
    let began = ThumbOutput.frame(SwipeFrame(offset: 0, phase: .began, exitSpeed: 0))

    func controller(_ mode: Mode, quick: Preset = .medium) -> ThumbController {
        var p = Preferences()
        p.mode = mode
        p.quickPreset = quick
        return ThumbController(preferences: p, exitFactor: 1)
    }

    func testQuickSwipeMode() {
        var c = controller(.quickSwipe)
        XCTAssertEqual(c.handle(.button(pressed: true), now: 0), [])
        XCTAssertEqual(c.handle(.move(dx: -600), now: 0.01), [.quickSwipe(.spaceRight)])
        XCTAssertEqual(c.handle(.button(pressed: false), now: 0.1), [])
    }

    func testQuickSwipeClick() {
        var c = controller(.quickSwipe)
        _ = c.handle(.button(pressed: true), now: 0)
        XCTAssertEqual(c.handle(.button(pressed: false), now: 0.1), [.missionControl])
    }

    func testFollowHandMode() {
        var c = controller(.followHand)
        _ = c.handle(.button(pressed: true), now: 0)
        XCTAssertEqual(c.handle(.move(dx: -31), now: 0.01),
                       [began, .frame(SwipeFrame(offset: 31.0 / 1500, phase: .changed, exitSpeed: 0))])
    }

    func testFollowHandClick() {
        var c = controller(.followHand)
        _ = c.handle(.button(pressed: true), now: 0)
        XCTAssertEqual(c.handle(.button(pressed: false), now: 0.1), [.missionControl])
    }

    func testApplyWhenIdleTakesEffectAtOnce() {
        var c = controller(.quickSwipe)
        var p = Preferences()
        p.mode = .followHand
        c.apply(p)
        XCTAssertEqual(c.preferences.mode, .followHand)
        _ = c.handle(.button(pressed: true), now: 0)
        XCTAssertEqual(c.handle(.move(dx: -31), now: 0.01).first, began)
    }

    func testApplyDuringHoldWaitsForNextPress() {
        var c = controller(.quickSwipe)
        _ = c.handle(.button(pressed: true), now: 0)
        var p = Preferences()
        p.mode = .followHand
        c.apply(p)
        XCTAssertEqual(c.preferences.mode, .quickSwipe)
        XCTAssertEqual(c.handle(.move(dx: -600), now: 0.01), [.quickSwipe(.spaceRight)])
        _ = c.handle(.button(pressed: false), now: 0.1)
        _ = c.handle(.button(pressed: true), now: 0.2)
        XCTAssertEqual(c.preferences.mode, .followHand)
        XCTAssertEqual(c.handle(.move(dx: -31), now: 0.21).first, began)
    }

    func testQuickPresetDistanceIsUsed() {
        var c = controller(.quickSwipe, quick: .short)
        _ = c.handle(.button(pressed: true), now: 0)
        XCTAssertEqual(c.handle(.move(dx: -400), now: 0.01), [.quickSwipe(.spaceRight)])
    }

    func testResetDropsHold() {
        var c = controller(.quickSwipe)
        _ = c.handle(.button(pressed: true), now: 0)
        _ = c.handle(.move(dx: -300), now: 0.01)
        c.reset()
        XCTAssertEqual(c.handle(.button(pressed: false), now: 0.1), [])
    }

    func testCancelEndsAnOpenFollowSwipe() {
        var c = controller(.followHand)
        _ = c.handle(.button(pressed: true), now: 0)
        _ = c.handle(.move(dx: -31), now: 0.0)
        _ = c.handle(.move(dx: -69), now: 0.05)
        XCTAssertEqual(c.cancel(), [.frame(SwipeFrame(offset: 100.0 / 1500, phase: .ended, exitSpeed: 0))])
        XCTAssertEqual(c.handle(.button(pressed: false), now: 0.1), [])
    }

    func testCancelWithoutSwipeGivesNothing() {
        var c = controller(.followHand)
        _ = c.handle(.button(pressed: true), now: 0)
        XCTAssertEqual(c.cancel(), [])
        XCTAssertEqual(c.handle(.button(pressed: false), now: 0.1), [])
    }

    func testCancelInQuickSwipeDropsHold() {
        var c = controller(.quickSwipe)
        _ = c.handle(.button(pressed: true), now: 0)
        _ = c.handle(.move(dx: -300), now: 0.01)
        XCTAssertEqual(c.cancel(), [])
        XCTAssertEqual(c.handle(.button(pressed: false), now: 0.1), [])
    }

    func testCancelAppliesPendingPreferences() {
        var c = controller(.quickSwipe)
        _ = c.handle(.button(pressed: true), now: 0)
        var p = Preferences()
        p.mode = .followHand
        c.apply(p)
        _ = c.cancel()
        XCTAssertEqual(c.preferences.mode, .followHand)
    }
}
