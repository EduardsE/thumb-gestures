import XCTest
@testable import ThumbGesturesCore

final class FollowGestureTests: XCTestCase {
    var follow = FollowGesture(scale: 1500, exitFactor: 1)
    let began = FollowOutput.frame(SwipeFrame(offset: 0, phase: .began, exitSpeed: 0))

    override func setUp() {
        follow = FollowGesture(scale: 1500, exitFactor: 1)
    }

    func press(_ time: Double = 0) -> [FollowOutput] { follow.handle(.button(pressed: true), now: time) }
    func release(_ time: Double) -> [FollowOutput] { follow.handle(.button(pressed: false), now: time) }
    func move(_ dx: Int, _ time: Double) -> [FollowOutput] { follow.handle(.move(dx: dx), now: time) }
    func changed(_ offset: Double) -> FollowOutput { .frame(SwipeFrame(offset: offset, phase: .changed, exitSpeed: 0)) }

    /// The single ended frame in the outputs, or a test failure.
    func ended(_ outputs: [FollowOutput]) -> SwipeFrame? {
        guard outputs.count == 1, case .frame(let frame) = outputs[0], frame.phase == .ended else {
            XCTFail("expected one ended frame, got \(outputs)")
            return nil
        }
        return frame
    }

    func testClickOpensMissionControl() {
        XCTAssertEqual(press(), [])
        XCTAssertEqual(release(0.1), [.missionControl])
    }

    func testMoveInsideDeadZoneIsAClick() {
        _ = press()
        XCTAssertEqual(move(-30, 0.01), [])
        XCTAssertEqual(release(0.1), [.missionControl])
    }

    func testMovePastDeadZoneStartsSwipe() {
        _ = press()
        XCTAssertEqual(move(-31, 0.01), [began, changed(31.0 / 1500)])
    }

    func testMovingRightGivesNegativeOffset() {
        _ = press()
        XCTAssertEqual(move(100, 0.01), [began, changed(-100.0 / 1500)])
    }

    func testLaterMovesSendChanged() {
        _ = press()
        _ = move(-31, 0.01)
        XCTAssertEqual(move(-10, 0.02), [changed(41.0 / 1500)])
    }

    func testReleaseSendsEndedWithExitSpeed() {
        _ = press()
        _ = move(-31, 0.0)
        _ = move(-150, 0.05)
        guard let frame = ended(release(0.06)) else { return }
        XCTAssertEqual(frame.offset, 181.0 / 1500, accuracy: 1e-9)
        XCTAssertEqual(frame.exitSpeed, 150.0 / 1500 / 0.05, accuracy: 1e-9)
    }

    func testOldSamplesAreDropped() {
        _ = press()
        _ = move(-31, 0.0)
        _ = move(-100, 1.0)
        _ = move(-100, 1.05)
        guard let frame = ended(release(1.06)) else { return }
        XCTAssertEqual(frame.exitSpeed, 100.0 / 1500 / 0.05, accuracy: 1e-9)
    }

    func testStopBeforeReleaseGivesZeroExitSpeed() {
        _ = press()
        _ = move(-31, 0.0)
        _ = move(-150, 0.05)
        XCTAssertEqual(ended(release(1.0))?.exitSpeed, 0)
    }

    func testOneSampleGivesZeroExitSpeed() {
        _ = press()
        _ = move(-31, 0.0)
        XCTAssertEqual(ended(release(0.02))?.exitSpeed, 0)
    }

    func testExitFactorScalesSpeed() {
        follow = FollowGesture(scale: 1500, exitFactor: 2)
        _ = press()
        _ = move(-31, 0.0)
        _ = move(-150, 0.05)
        XCTAssertEqual(ended(release(0.06))?.exitSpeed ?? 0, 2 * 150.0 / 1500 / 0.05, accuracy: 1e-9)
    }

    func testRepeatedPressKeepsHold() {
        _ = press()
        _ = move(-31, 0.01)
        XCTAssertEqual(press(0.02), [])
        XCTAssertEqual(move(-10, 0.03), [changed(41.0 / 1500)])
    }

    func testLinkDuringSwipeEndsIt() {
        _ = press()
        _ = move(-31, 0.0)
        _ = move(-69, 0.05)
        XCTAssertEqual(follow.handle(.linked(false), now: 0.06),
                       [.frame(SwipeFrame(offset: 100.0 / 1500, phase: .ended, exitSpeed: 0))])
        XCTAssertEqual(release(0.1), [])
    }

    func testLinkWithoutSwipeGivesNothing() {
        _ = press()
        XCTAssertEqual(follow.handle(.linked(true), now: 0.01), [])
        XCTAssertEqual(release(0.1), [])
    }

    func testIdleMoveGivesNothing() {
        XCTAssertEqual(move(-500, 0.0), [])
        XCTAssertEqual(release(0.1), [])
    }

    func testResetDropsHold() {
        _ = press()
        _ = move(-31, 0.01)
        follow.reset()
        XCTAssertEqual(release(0.1), [])
    }
}
