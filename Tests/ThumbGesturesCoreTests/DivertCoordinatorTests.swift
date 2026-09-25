import XCTest
@testable import ThumbGesturesCore

final class DivertCoordinatorTests: XCTestCase {
    var coordinator = DivertCoordinator()

    override func setUp() {
        coordinator = DivertCoordinator()
    }

    func testFirstBeginRuns() {
        XCTAssertTrue(coordinator.begin())
        XCTAssertTrue(coordinator.isRunning)
    }

    func testSuccessGoesIdle() {
        _ = coordinator.begin()
        XCTAssertEqual(coordinator.end(success: true), .idle)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testBeginDuringRunDoesNotNestAndRunsAgainAfter() {
        _ = coordinator.begin()
        XCTAssertFalse(coordinator.begin())
        XCTAssertEqual(coordinator.end(success: true), .runAgain)
        XCTAssertTrue(coordinator.begin())
        XCTAssertEqual(coordinator.end(success: true), .idle)
    }

    func testFailuresRetryWithBackoff() {
        for expected in [2.0, 5, 15, 30, 30] {
            _ = coordinator.begin()
            XCTAssertEqual(coordinator.end(success: false), .retry(after: expected))
        }
    }

    func testSuccessResetsBackoff() {
        _ = coordinator.begin(); _ = coordinator.end(success: false)
        _ = coordinator.begin(); _ = coordinator.end(success: false)
        _ = coordinator.begin(); _ = coordinator.end(success: true)
        _ = coordinator.begin()
        XCTAssertEqual(coordinator.end(success: false), .retry(after: 2))
    }

    func testFirstFailureIsReported() {
        _ = coordinator.begin(); _ = coordinator.end(success: false)
        XCTAssertEqual(coordinator.failures, 1)
        _ = coordinator.begin(); _ = coordinator.end(success: true)
        XCTAssertEqual(coordinator.failures, 0)
    }

    func testTriggerDuringFailedRunRunsAgainNotBackoff() {
        _ = coordinator.begin()
        _ = coordinator.begin()
        XCTAssertEqual(coordinator.end(success: false), .runAgain)
    }

    func testQuitWhenIdleIsImmediate() {
        XCTAssertTrue(coordinator.requestQuit())
    }

    func testQuitDuringRunWaitsForTheEnd() {
        _ = coordinator.begin()
        XCTAssertFalse(coordinator.requestQuit())
        XCTAssertFalse(coordinator.begin())
        XCTAssertEqual(coordinator.end(success: true), .quit)
    }
}
