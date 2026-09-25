import Foundation
import XCTest
@testable import ThumbGesturesCore

final class PreferencesTests: XCTestCase {
    func testDefaults() {
        let p = Preferences()
        XCTAssertEqual(p.mode, .quickSwipe)
        XCTAssertEqual(p.quickPreset, .medium)
        XCTAssertEqual(p.followPreset, .medium)
        XCTAssertEqual(Preferences(defaults: [:]), p)
    }

    func testRoundTripForEveryModeAndPreset() {
        for mode in Mode.allCases {
            for quick in Preset.allCases {
                for follow in Preset.allCases {
                    var p = Preferences()
                    p.mode = mode
                    p.quickPreset = quick
                    p.followPreset = follow
                    XCTAssertEqual(Preferences(defaults: p.defaultsValues), p)
                }
            }
        }
    }

    func testDefaultsValuesUseTheStoredKeys() {
        var p = Preferences()
        p.mode = .followHand
        p.followPreset = .long
        XCTAssertEqual(p.defaultsValues, ["Mode": "followHand", "QuickSwipeDistance": "medium", "FollowHandDistance": "long"])
    }

    func testBadValuesFallBack() {
        let p = Preferences(defaults: ["Mode": "fast", "QuickSwipeDistance": NSNumber(value: 5), "FollowHandDistance": "huge"])
        XCTAssertEqual(p, Preferences())
    }

    func testPresetTable() {
        var p = Preferences()
        let expected: [(Preset, Int, Double)] = [(.short, 400, 1000), (.medium, 600, 1500), (.long, 900, 2200)]
        for (preset, distance, scale) in expected {
            p.quickPreset = preset
            p.followPreset = preset
            XCTAssertEqual(p.switchDistance, distance)
            XCTAssertEqual(p.followScale, scale)
        }
    }

    func testPresetFollowsSelectedMode() {
        var p = Preferences()
        p.preset = .short
        XCTAssertEqual(p.quickPreset, .short)
        XCTAssertEqual(p.followPreset, .medium)
        p.mode = .followHand
        XCTAssertEqual(p.preset, .medium)
        p.preset = .long
        XCTAssertEqual(p.followPreset, .long)
        XCTAssertEqual(p.quickPreset, .short)
    }

    func testExitSpeedFactor() {
        XCTAssertEqual(Preferences.exitSpeedFactor(nil), 1)
        XCTAssertEqual(Preferences.exitSpeedFactor(NSNumber(value: 0)), 1)
        XCTAssertEqual(Preferences.exitSpeedFactor(NSNumber(value: -1)), 1)
        XCTAssertEqual(Preferences.exitSpeedFactor("2"), 1)
        XCTAssertEqual(Preferences.exitSpeedFactor(NSNumber(value: 2.5)), 2.5)
    }
}
