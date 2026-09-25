import Foundation
import XCTest
@testable import ThumbGesturesCore

final class GestureTests: XCTestCase {
    var gesture = Gesture(distance: 600)

    override func setUp() {
        gesture = Gesture(distance: 600)
    }

    func press() -> GestureAction? { gesture.handle(.button(pressed: true)) }
    func release() -> GestureAction? { gesture.handle(.button(pressed: false)) }
    func move(_ dx: Int) -> GestureAction? { gesture.handle(.move(dx: dx)) }

    func testClickOpensMissionControl() {
        XCTAssertNil(press())
        XCTAssertEqual(release(), .missionControl)
    }

    func testMoveLeftSwitchesToSpaceOnTheRight() {
        _ = press()
        XCTAssertEqual(move(-600), .spaceRight)
        XCTAssertNil(release())
    }

    func testMoveRightSwitchesToSpaceOnTheLeft() {
        _ = press()
        XCTAssertEqual(move(600), .spaceLeft)
        XCTAssertNil(release())
    }

    func testOneSwitchPerHold() {
        _ = press()
        XCTAssertEqual(move(-600), .spaceRight)
        XCTAssertNil(move(-600))
        XCTAssertNil(move(2000))
        XCTAssertNil(release())
    }

    func testSmallMovesAddUp() {
        _ = press()
        XCTAssertNil(move(-200))
        XCTAssertNil(move(-200))
        XCTAssertEqual(move(-200), .spaceRight)
    }

    func testMoveBelowDistanceThenReleaseOpensMissionControl() {
        _ = press()
        XCTAssertNil(move(-599))
        XCTAssertEqual(release(), .missionControl)
    }

    func testBackAndForthCancelsOut() {
        _ = press()
        XCTAssertNil(move(-400))
        XCTAssertNil(move(400))
        XCTAssertEqual(release(), .missionControl)
    }

    func testIdleIgnoresMovesAndReleases() {
        XCTAssertNil(move(-1000))
        XCTAssertNil(release())
    }

    func testRepeatedPressDoesNotResetHold() {
        _ = press()
        XCTAssertNil(move(-400))
        XCTAssertNil(press())
        XCTAssertEqual(move(-200), .spaceRight)
        XCTAssertNil(press())
        XCTAssertNil(move(-600))
    }

    func testLinkChangeResetsHold() {
        _ = press()
        XCTAssertNil(move(-400))
        XCTAssertNil(gesture.handle(.linked(false)))
        XCTAssertFalse(gesture.isHeld)
        XCTAssertNil(release())
        _ = press()
        XCTAssertNil(move(-300))
    }

    func testResetDropsHold() {
        _ = press()
        gesture.reset()
        XCTAssertNil(release())
    }

    func testDistanceIsAtLeastOne() {
        XCTAssertEqual(Gesture(distance: 0).distance, 1)
    }

    func testSwitchDistanceReadsPositiveNumber() {
        XCTAssertEqual(Settings.switchDistance(NSNumber(value: 800)), 800)
    }

    func testSwitchDistanceFallsBackToDefault() {
        XCTAssertEqual(Settings.switchDistance(nil), 600)
        XCTAssertEqual(Settings.switchDistance(NSNumber(value: 0)), 600)
        XCTAssertEqual(Settings.switchDistance(NSNumber(value: -5)), 600)
        XCTAssertEqual(Settings.switchDistance("800"), 600)
    }
}
