import XCTest
@testable import ThumbGesturesCore

final class DockSwipeTests: XCTestCase {
    func testMissionControlHasNoFrames() {
        XCTAssertEqual(DockSwipe.frames(for: .missionControl), [])
    }

    func testSpaceRightSwipesToPlusOne() {
        let frames = DockSwipe.frames(for: .spaceRight)
        XCTAssertEqual(frames.count, DockSwipe.steps + 2)
        XCTAssertEqual(frames.first, SwipeFrame(offset: 0, phase: .began, exitSpeed: 0))
        XCTAssertEqual(frames.last, SwipeFrame(offset: 1, phase: .ended, exitSpeed: DockSwipe.exitSpeed))
        let changed = frames.dropFirst().dropLast()
        XCTAssertTrue(changed.allSatisfy { $0.phase == .changed })
        XCTAssertEqual(changed.map(\.offset), changed.map(\.offset).sorted())
        XCTAssertEqual(changed.last?.offset, 1)
        XCTAssertGreaterThan(changed.first!.offset, 0)
    }

    func testSpaceLeftSwipesToMinusOne() {
        let frames = DockSwipe.frames(for: .spaceLeft)
        XCTAssertEqual(frames.first, SwipeFrame(offset: 0, phase: .began, exitSpeed: 0))
        XCTAssertEqual(frames.last, SwipeFrame(offset: -1, phase: .ended, exitSpeed: DockSwipe.exitSpeed))
        XCTAssertEqual(frames.dropFirst().dropLast().map(\.offset),
                       DockSwipe.frames(for: .spaceRight).dropFirst().dropLast().map { -$0.offset })
    }

    func testPhaseRawValuesMatchIOHIDEventPhase() {
        XCTAssertEqual(SwipePhase.began.rawValue, 1)
        XCTAssertEqual(SwipePhase.changed.rawValue, 2)
        XCTAssertEqual(SwipePhase.ended.rawValue, 4)
    }
}
