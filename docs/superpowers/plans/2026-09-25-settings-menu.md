# Settings Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a menu bar menu to Thumb Gestures that selects the switch mode (Quick Swipe or Follow Hand) and a distance preset for each mode, and that can pause, open the log, and quit, with no restart.

**Architecture:** New pure core types (`Preferences`, `FollowGesture`, `ThumbController`) and a pause state in `DivertCoordinator`, all with unit tests. The app starts `NSApplication` as an accessory app with an `NSStatusItem` (`StatusMenu`), and `main.swift` sends HID events to `ThumbController` and does its outputs.

**Tech Stack:** Swift 5.9 tools (Swift 6.4 compiler in Swift 5 mode), SwiftPM, XCTest, AppKit (`NSStatusItem`, `NSMenu`), IOKit HID, launchd.

**Spec:** `docs/superpowers/specs/2026-09-25-settings-menu-design.md`

## Global Constraints

- Branch: `feature/settings-menu` (already created from `main`, spec committed).
- macOS 13 or later. No third-party dependencies. No SwiftUI.
- Defaults domain `local.thumbgestures.ThumbGestures`. Keys: `Mode` (`quickSwipe` | `followHand`, default `quickSwipe`), `QuickSwipeDistance` and `FollowHandDistance` (`short` | `medium` | `long`, default `medium`), `ExitSpeedFactor` (number > 0, default 1, no menu item).
- Old keys `SwitchDistance`, `FollowScale`, `FollowHand` are not read anymore.
- Presets: Quick swipe switch distance Short 400, Medium 600, Long 900. Follow hand counts for one Space Short 1000, Medium 1500, Long 2200.
- Follow hand: dead zone 30 counts (`|total| > 30` starts a swipe); offset `-total / scale`; exit speed from samples in the last 0.1 s before the release; link change during a swipe sends `ended` with exit speed 0.
- A mode or preset change applies at the next press of the thumb button, never during a hold.
- Menu titles, exactly: `Ready`, `Waiting for the mouse`, `Paused`, `Quick Swipe`, `Follow Hand`, `Distance`, `Short`, `Medium`, `Long`, `Pause`, `Resume`, `Open Log`, `Quit Thumb Gestures`.
- Icons (SF Symbols, template): Ready `arrow.left.and.right`; Waiting `exclamationmark.triangle`; Paused `arrow.left.and.right` with `appearsDisabled = true`.
- `build.sh` signs with the local certificate `Local App Signing` (exists on this Mac), so a reinstall keeps the Accessibility permission.
- Test command: `swift test --disable-swift-testing`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Do not push, merge into `main`, or delete branches without the user's explicit yes.

## Review Focus

- **A stop before the release** (hold, move fast, stop for a second, release) must give exit speed 0, so macOS does not complete a switch that the hand did not flick. Test: `testStopBeforeReleaseGivesZeroExitSpeed` in Task 2.
- **A mode change in the menu during a hold** must not switch the gesture in the middle of the hold (a started live swipe would never get `ended`). Test: `testApplyDuringHoldWaitsForNextPress` in Task 3.
- **A pause while a divert is running** must not leave the button diverted with no gestures. Test: `testPauseDuringSuccessfulDivertUndiverts` in Task 4.
- **A connect or a wake during pause** must not divert the button again. Test: `testTriggerDuringPauseIsNotRemembered` and `testBeginWhilePausedReturnsFalse` in Task 4.
- **Old or bad stored values** (for example `Mode = "fast"` or a number instead of a string) must give the defaults and not crash. Test: `testBadValuesFallBack` in Task 1.

---

### Task 1: Preferences

**Files:**
- Create: `Sources/ThumbGesturesCore/Preferences.swift`
- Modify: `Sources/ThumbGesturesCore/Gesture.swift` (remove `enum Settings`, lines 56-64)
- Modify: `Sources/ThumbGestures/main.swift:42` (stop using `Settings`)
- Test: `Tests/ThumbGesturesCoreTests/PreferencesTests.swift`
- Modify: `Tests/ThumbGesturesCoreTests/GestureTests.swift` (remove `testSwitchDistanceReadsPositiveNumber` and `testSwitchDistanceFallsBackToDefault`)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `public enum Mode: String, CaseIterable { case quickSwipe, followHand }`
  - `public enum Preset: String, CaseIterable { case short, medium, long }`
  - `public struct Preferences: Equatable` with `static let modeKey = "Mode"`, `quickSwipeDistanceKey = "QuickSwipeDistance"`, `followHandDistanceKey = "FollowHandDistance"`, `exitSpeedFactorKey = "ExitSpeedFactor"`; `var mode: Mode`, `var quickPreset: Preset`, `var followPreset: Preset`; `init()`; `init(defaults: [String: Any])`; `var defaultsValues: [String: String]`; `var preset: Preset { get set }` (the preset of the selected mode); `var switchDistance: Int`; `var followScale: Double`; `static func exitSpeedFactor(_ value: Any?) -> Double`.

- [ ] **Step 1: Write the failing tests**

`Tests/ThumbGesturesCoreTests/PreferencesTests.swift`:

```swift
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
```

Also delete these two tests from `Tests/ThumbGesturesCoreTests/GestureTests.swift` (they test `Settings`, which this task removes):

```swift
    func testSwitchDistanceReadsPositiveNumber() {
        XCTAssertEqual(Settings.switchDistance(NSNumber(value: 800)), 800)
    }

    func testSwitchDistanceFallsBackToDefault() {
        XCTAssertEqual(Settings.switchDistance(nil), 600)
        XCTAssertEqual(Settings.switchDistance(NSNumber(value: 0)), 600)
        XCTAssertEqual(Settings.switchDistance(NSNumber(value: -5)), 600)
        XCTAssertEqual(Settings.switchDistance("800"), 600)
    }
```

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `cd ~/code/thumb-gestures && swift test --disable-swift-testing 2>&1 | grep -oE "error: cannot find [^ ]+ in scope" | sort -u`
Expected: `error: cannot find 'Preferences' in scope` (and `'Mode'`, `'Preset'`).

- [ ] **Step 3: Write the implementation**

`Sources/ThumbGesturesCore/Preferences.swift`:

```swift
// The user settings: the switch mode and a distance preset for each mode.
// The menu writes them to the defaults domain. This file does no I/O.

import Foundation

public enum Mode: String, CaseIterable {
    case quickSwipe
    case followHand
}

public enum Preset: String, CaseIterable {
    case short
    case medium
    case long
}

public struct Preferences: Equatable {
    public static let modeKey = "Mode"
    public static let quickSwipeDistanceKey = "QuickSwipeDistance"
    public static let followHandDistanceKey = "FollowHandDistance"
    public static let exitSpeedFactorKey = "ExitSpeedFactor"

    public var mode: Mode = .quickSwipe
    public var quickPreset: Preset = .medium
    public var followPreset: Preset = .medium

    public init() {}

    /// Reads the stored values. A missing or bad value gives the default.
    public init(defaults: [String: Any]) {
        mode = (defaults[Self.modeKey] as? String).flatMap(Mode.init(rawValue:)) ?? .quickSwipe
        quickPreset = (defaults[Self.quickSwipeDistanceKey] as? String).flatMap(Preset.init(rawValue:)) ?? .medium
        followPreset = (defaults[Self.followHandDistanceKey] as? String).flatMap(Preset.init(rawValue:)) ?? .medium
    }

    public var defaultsValues: [String: String] {
        [Self.modeKey: mode.rawValue,
         Self.quickSwipeDistanceKey: quickPreset.rawValue,
         Self.followHandDistanceKey: followPreset.rawValue]
    }

    /// The preset of the selected mode.
    public var preset: Preset {
        get { mode == .quickSwipe ? quickPreset : followPreset }
        set {
            if mode == .quickSwipe { quickPreset = newValue } else { followPreset = newValue }
        }
    }

    /// Quick swipe: horizontal movement, in mouse counts, that starts a switch.
    public var switchDistance: Int {
        switch quickPreset {
        case .short: return 400
        case .medium: return 600
        case .long: return 900
        }
    }

    /// Follow hand: mouse counts for one full Space.
    public var followScale: Double {
        switch followPreset {
        case .short: return 1000
        case .medium: return 1500
        case .long: return 2200
        }
    }

    /// The hidden ExitSpeedFactor setting, or 1 if it is missing or not a positive number.
    public static func exitSpeedFactor(_ value: Any?) -> Double {
        if let number = value as? NSNumber, number.doubleValue > 0 { return number.doubleValue }
        return 1
    }
}
```

In `Sources/ThumbGesturesCore/Gesture.swift`, delete the whole `public enum Settings { ... }` block (from `public enum Settings {` to its closing `}` at the end of the file).

In `Sources/ThumbGestures/main.swift`, replace line 42:

```swift
var gesture = Gesture(distance: Settings.switchDistance(UserDefaults.standard.object(forKey: "SwitchDistance")))
```

with:

```swift
var gesture = Gesture(distance: Preferences(defaults: UserDefaults.standard.dictionaryRepresentation()).switchDistance)
```

(Task 5 replaces this line again. This change only keeps the app target building.)

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `cd ~/code/thumb-gestures && swift test --disable-swift-testing 2>&1 | grep -E "Executed|error:" | tail -1 && swift build -c release --product ThumbGestures 2>&1 | grep -E "error|Build complete"`
Expected: `Executed 55 tests, with 0 failures` and `Build complete!`.

- [ ] **Step 5: Commit**

```bash
cd ~/code/thumb-gestures
git add Sources Tests
git commit -m "Add Preferences with modes and distance presets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: FollowGesture in the core

**Files:**
- Create: `Sources/ThumbGesturesCore/FollowGesture.swift`
- Modify: `Sources/ThumbGesturesCore/DockSwipe.swift` (public `init` for `SwipeFrame`)
- Test: `Tests/ThumbGesturesCoreTests/FollowGestureTests.swift`

**Interfaces:**
- Consumes: `ThumbEvent` (HIDPP.swift), `SwipeFrame`, `SwipePhase` (DockSwipe.swift).
- Produces:
  - `public enum FollowOutput: Equatable { case frame(SwipeFrame), missionControl }`
  - `public struct FollowGesture` with `static let deadZone = 30`, `static let sampleWindow = 0.1`, `let scale: Double`, `let exitFactor: Double`, `init(scale: Double, exitFactor: Double)`, `mutating func handle(_ event: ThumbEvent, now: Double) -> [FollowOutput]`, `mutating func reset()`.
  - `SwipeFrame.init(offset: Double, phase: SwipePhase, exitSpeed: Double)` (public).

- [ ] **Step 1: Write the failing tests**

`Tests/ThumbGesturesCoreTests/FollowGestureTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `cd ~/code/thumb-gestures && swift test --disable-swift-testing 2>&1 | grep -oE "error: cannot find [^ ]+ in scope" | sort -u`
Expected: `error: cannot find 'FollowGesture' in scope` (and `'FollowOutput'`).

- [ ] **Step 3: Write the implementation**

In `Sources/ThumbGesturesCore/DockSwipe.swift`, replace:

```swift
    public let exitSpeed: Double
}
```

with:

```swift
    public let exitSpeed: Double

    public init(offset: Double, phase: SwipePhase, exitSpeed: Double) {
        self.offset = offset
        self.phase = phase
        self.exitSpeed = exitSpeed
    }
}
```

`Sources/ThumbGesturesCore/FollowGesture.swift`:

```swift
// Follow hand: during a hold, the Space follows the hand like a trackpad swipe.
// On release, macOS completes the switch or goes back, from the offset and the
// exit speed. This file does no I/O.

public enum FollowOutput: Equatable {
    case frame(SwipeFrame)
    case missionControl
}

public struct FollowGesture {
    /// Movement, in counts, before a swipe starts. Below it, a release is a click.
    public static let deadZone = 30
    /// The exit speed uses the movement of the last 0.1 s before the release.
    public static let sampleWindow = 0.1

    /// Mouse counts for one full Space.
    public let scale: Double
    /// Multiplier for the exit speed (offsets per second).
    public let exitFactor: Double

    private var isHeld = false
    private var swiping = false
    private var total = 0
    private var samples: [(time: Double, offset: Double)] = []

    public init(scale: Double, exitFactor: Double) {
        self.scale = max(1, scale)
        self.exitFactor = exitFactor
    }

    /// Moving left gives a positive offset: the Space on the right comes in.
    private var offset: Double { -Double(total) / scale }

    public mutating func handle(_ event: ThumbEvent, now: Double) -> [FollowOutput] {
        switch event {
        case .button(pressed: true):
            // The mouse can report "pressed" again during a hold. Keep the hold.
            if !isHeld {
                reset()
                isHeld = true
            }
            return []
        case .button(pressed: false):
            guard isHeld else { return [] }
            defer { reset() }
            guard swiping else { return [.missionControl] }
            return [.frame(SwipeFrame(offset: offset, phase: .ended, exitSpeed: exitSpeed(at: now)))]
        case .move(let dx):
            guard isHeld else { return [] }
            total += dx
            var outputs: [FollowOutput] = []
            if !swiping {
                guard abs(total) > Self.deadZone else { return [] }
                swiping = true
                outputs.append(.frame(SwipeFrame(offset: 0, phase: .began, exitSpeed: 0)))
            }
            samples.append((now, offset))
            samples.removeAll { now - $0.time > Self.sampleWindow }
            outputs.append(.frame(SwipeFrame(offset: offset, phase: .changed, exitSpeed: 0)))
            return outputs
        case .linked:
            // Do not leave a swipe open when the mouse connects or disconnects.
            defer { reset() }
            return swiping ? [.frame(SwipeFrame(offset: offset, phase: .ended, exitSpeed: 0))] : []
        }
    }

    public mutating func reset() {
        isHeld = false
        swiping = false
        total = 0
        samples = []
    }

    /// Offsets per second over the last sample window. 0 if the hand stopped before the release.
    private func exitSpeed(at now: Double) -> Double {
        let recent = samples.filter { now - $0.time <= Self.sampleWindow }
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return 0 }
        return (last.offset - first.offset) / (last.time - first.time) * exitFactor
    }
}
```

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `cd ~/code/thumb-gestures && swift test --disable-swift-testing 2>&1 | grep -E "Executed|error:" | tail -1`
Expected: `Executed 70 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
cd ~/code/thumb-gestures
git add Sources/ThumbGesturesCore Tests/ThumbGesturesCoreTests/FollowGestureTests.swift
git commit -m "Add FollowGesture: the Space follows the hand during a hold

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: ThumbController

**Files:**
- Create: `Sources/ThumbGesturesCore/ThumbController.swift`
- Test: `Tests/ThumbGesturesCoreTests/ThumbControllerTests.swift`

**Interfaces:**
- Consumes: `Preferences` (Task 1), `FollowGesture`, `FollowOutput` (Task 2), `Gesture`, `GestureAction` (Gesture.swift), `ThumbEvent`, `SwipeFrame`.
- Produces:
  - `public enum ThumbOutput: Equatable { case missionControl, quickSwipe(GestureAction), frame(SwipeFrame) }`
  - `public struct ThumbController` with `init(preferences: Preferences, exitFactor: Double)`, `private(set) var preferences: Preferences`, `mutating func apply(_ preferences: Preferences)`, `mutating func handle(_ event: ThumbEvent, now: Double) -> [ThumbOutput]`, `mutating func reset()`.

- [ ] **Step 1: Write the failing tests**

`Tests/ThumbGesturesCoreTests/ThumbControllerTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `cd ~/code/thumb-gestures && swift test --disable-swift-testing 2>&1 | grep -oE "error: cannot find [^ ]+ in scope" | sort -u`
Expected: `error: cannot find 'ThumbController' in scope` (and `'ThumbOutput'`).

- [ ] **Step 3: Write the implementation**

`Sources/ThumbGesturesCore/ThumbController.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `cd ~/code/thumb-gestures && swift test --disable-swift-testing 2>&1 | grep -E "Executed|error:" | tail -1`
Expected: `Executed 78 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
cd ~/code/thumb-gestures
git add Sources/ThumbGesturesCore/ThumbController.swift Tests/ThumbGesturesCoreTests/ThumbControllerTests.swift
git commit -m "Add ThumbController to route events to the selected mode

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Pause in DivertCoordinator

**Files:**
- Modify: `Sources/ThumbGesturesCore/Divert.swift`
- Test: `Tests/ThumbGesturesCoreTests/DivertCoordinatorTests.swift` (add tests)

**Interfaces:**
- Consumes: the existing `DivertCoordinator`.
- Produces: `DivertCoordinator.Next.undivert`; `private(set) var isPaused: Bool`; `mutating func setPaused(_ paused: Bool)`.

- [ ] **Step 1: Write the failing tests**

Add these methods inside `final class DivertCoordinatorTests` in `Tests/ThumbGesturesCoreTests/DivertCoordinatorTests.swift`, before its last `}`:

```swift
    func testBeginWhilePausedReturnsFalse() {
        coordinator.setPaused(true)
        XCTAssertTrue(coordinator.isPaused)
        XCTAssertFalse(coordinator.begin())
        XCTAssertFalse(coordinator.isRunning)
    }

    func testTriggerDuringPauseIsNotRemembered() {
        _ = coordinator.begin()
        coordinator.setPaused(true)
        XCTAssertFalse(coordinator.begin())
        XCTAssertEqual(coordinator.end(success: false), .idle)
    }

    func testTriggerBeforePauseIsDropped() {
        _ = coordinator.begin()
        XCTAssertFalse(coordinator.begin())
        coordinator.setPaused(true)
        XCTAssertEqual(coordinator.end(success: true), .undivert)
    }

    func testResumeAllowsBegin() {
        coordinator.setPaused(true)
        coordinator.setPaused(false)
        XCTAssertTrue(coordinator.begin())
    }

    func testPauseDuringSuccessfulDivertUndiverts() {
        _ = coordinator.begin()
        coordinator.setPaused(true)
        XCTAssertEqual(coordinator.end(success: true), .undivert)
    }

    func testQuitDuringPausedDivertQuits() {
        _ = coordinator.begin()
        coordinator.setPaused(true)
        XCTAssertFalse(coordinator.requestQuit())
        XCTAssertEqual(coordinator.end(success: true), .quit)
    }
```

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `cd ~/code/thumb-gestures && swift test --disable-swift-testing 2>&1 | grep -oE "error: [^\[]+" | sort -u | head -5`
Expected: errors like `value of type 'DivertCoordinator' has no member 'setPaused'` and `type 'DivertCoordinator.Next' has no member 'undivert'`.

- [ ] **Step 3: Write the implementation**

In `Sources/ThumbGesturesCore/Divert.swift`:

1. Add `case undivert` to `enum Next`, after `case retry(after: Double)`:

```swift
        case retry(after: Double)
        /// The divert ended during a pause and succeeded: give the button back.
        case undivert
        case quit
```

2. After `public private(set) var failures = 0`, add:

```swift
    /// During a pause, no divert starts and triggers are not remembered.
    public private(set) var isPaused = false
```

3. Replace the `begin()` function with:

```swift
    /// Returns true if the caller must start a divert now.
    public mutating func begin() -> Bool {
        if isPaused { return false }
        guard !isRunning, !quit else {
            again = true
            return false
        }
        isRunning = true
        again = false
        return true
    }
```

4. In `end(success:)`, after the line `if quit { return .quit }`, add:

```swift
        if isPaused {
            again = false
            return success ? .undivert : .idle
        }
```

5. After `requestQuit()`, add:

```swift
    public mutating func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused { again = false }
    }
```

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `cd ~/code/thumb-gestures && swift test --disable-swift-testing 2>&1 | grep -E "Executed|error:" | tail -1`
Expected: `Executed 84 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
cd ~/code/thumb-gestures
git add Sources/ThumbGesturesCore/Divert.swift Tests/ThumbGesturesCoreTests/DivertCoordinatorTests.swift
git commit -m "Add pause to DivertCoordinator

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The menu bar app

**Files:**
- Create: `Sources/ThumbGestures/StatusMenu.swift`
- Modify: `Sources/ThumbGestures/main.swift` (full replacement below)
- Modify: `Sources/ThumbGestures/Actions.swift` (`post` becomes internal)
- Modify: `install.sh` (wait after `bootout`)

**Interfaces:**
- Consumes: `Preferences`, `Mode`, `Preset` (Task 1), `ThumbController`, `ThumbOutput` (Task 3), `DivertCoordinator` with pause (Task 4), `Actions.perform`, `Actions.post`, `Receiver`, `HIDPP`, `Report`.
- Produces: `final class StatusMenu` with `enum Status { case ready, waiting, paused }`, `var status: Status`, `var preferences: Preferences`, and callbacks `onSelectMode: ((Mode) -> Void)?`, `onSelectPreset: ((Preset) -> Void)?`, `onPause: (() -> Void)?`, `onOpenLog: (() -> Void)?`, `onQuit: (() -> Void)?`.

- [ ] **Step 1: Write the status menu**

`Sources/ThumbGestures/StatusMenu.swift`:

```swift
import AppKit
import ThumbGesturesCore

/// The menu bar icon and its menu. It shows the state and calls back on each choice.
final class StatusMenu: NSObject {
    enum Status {
        case ready
        case waiting
        case paused
    }

    var onSelectMode: ((Mode) -> Void)?
    var onSelectPreset: ((Preset) -> Void)?
    var onPause: (() -> Void)?
    var onOpenLog: (() -> Void)?
    var onQuit: (() -> Void)?

    var status: Status = .waiting { didSet { update() } }
    var preferences = Preferences() { didSet { update() } }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var modeItems: [NSMenuItem] = []
    private var presetItems: [NSMenuItem] = []
    private let pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        for (mode, title) in [(Mode.quickSwipe, "Quick Swipe"), (.followHand, "Follow Hand")] {
            let modeItem = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
            modeItem.target = self
            modeItem.representedObject = mode.rawValue
            menu.addItem(modeItem)
            modeItems.append(modeItem)
        }
        menu.addItem(.separator())

        let distance = NSMenuItem(title: "Distance", action: nil, keyEquivalent: "")
        let distanceMenu = NSMenu()
        distanceMenu.autoenablesItems = false
        for (preset, title) in [(Preset.short, "Short"), (.medium, "Medium"), (.long, "Long")] {
            let presetItem = NSMenuItem(title: title, action: #selector(selectPreset(_:)), keyEquivalent: "")
            presetItem.target = self
            presetItem.representedObject = preset.rawValue
            distanceMenu.addItem(presetItem)
            presetItems.append(presetItem)
        }
        distance.submenu = distanceMenu
        menu.addItem(distance)
        menu.addItem(.separator())

        pauseItem.action = #selector(pause)
        pauseItem.target = self
        menu.addItem(pauseItem)
        let logItem = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Thumb Gestures", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        update()
    }

    private func update() {
        switch status {
        case .ready:
            statusLine.title = "Ready"
            setIcon("arrow.left.and.right", dimmed: false)
        case .waiting:
            statusLine.title = "Waiting for the mouse"
            setIcon("exclamationmark.triangle", dimmed: false)
        case .paused:
            statusLine.title = "Paused"
            setIcon("arrow.left.and.right", dimmed: true)
        }
        pauseItem.title = status == .paused ? "Resume" : "Pause"
        for modeItem in modeItems {
            modeItem.state = modeItem.representedObject as? String == preferences.mode.rawValue ? .on : .off
        }
        for presetItem in presetItems {
            presetItem.state = presetItem.representedObject as? String == preferences.preset.rawValue ? .on : .off
        }
    }

    private func setIcon(_ symbol: String, dimmed: Bool) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Thumb Gestures")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.appearsDisabled = dimmed
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = Mode(rawValue: raw) else { return }
        onSelectMode?(mode)
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = Preset(rawValue: raw) else { return }
        onSelectPreset?(preset)
    }

    @objc private func pause() { onPause?() }
    @objc private func openLog() { onOpenLog?() }
    @objc private func quit() { onQuit?() }
}
```

- [ ] **Step 2: Make `Actions.post` internal**

In `Sources/ThumbGestures/Actions.swift`, replace `    private static func post(_ frame: SwipeFrame) {` with `    static func post(_ frame: SwipeFrame) {`.

- [ ] **Step 3: Replace main.swift**

Replace the whole of `Sources/ThumbGestures/main.swift` with:

```swift
// Thumb Gestures — actions for the thumb button of a Logitech MX Vertical.
//
// Click: Mission Control. Hold and move left or right: switch Spaces, as a
// quick swipe or with the Space following the hand (a menu bar setting).
// The app diverts the button through Logitech HID++ on the receiver, so
// Logi Options+ is not necessary. The mouse forgets the divert when it
// reconnects, so the app sends it again after a connect, a wake, or a plug-in.

import AppKit
import ApplicationServices
import IOKit.hid
import ThumbGesturesCore

setvbuf(stdout, nil, _IOLBF, 0)

// Two copies would both act on each click. If another copy holds the lock
// (for example one that macOS starts for a moment), wait for it to stop.
// An exit with code 0 here would stop launchd from starting the app again.
let lockPath = NSTemporaryDirectory() + "thumbgestures.lock"
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
if lockFD < 0 {
    log("Cannot open the lock file \(lockPath).")
    exit(1)
}
if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    log("Another copy of Thumb Gestures is running. Waiting for it to stop.")
    flock(lockFD, LOCK_EX)
}

// Accessibility is necessary to post the swipe events. A running process
// does not see the permission change, so exit and let launchd start a new
// copy that does. Show the system prompt only on the first try.
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let promptedKey = "PromptedForAccessibility"
let prompt = !UserDefaults.standard.bool(forKey: promptedKey)
if !AXIsProcessTrustedWithOptions([promptKey: prompt] as CFDictionary) {
    UserDefaults.standard.set(true, forKey: promptedKey)
    log("Waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility).")
    sleep(5)
    exit(1)
}

// A menu bar app with no Dock icon.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

var preferences = Preferences(defaults: UserDefaults.standard.dictionaryRepresentation())
let exitFactor = Preferences.exitSpeedFactor(UserDefaults.standard.object(forKey: Preferences.exitSpeedFactorKey))
var controller = ThumbController(preferences: preferences, exitFactor: exitFactor)
let menu = StatusMenu()
menu.preferences = preferences

let receiver = Receiver()
var deviceIndex: UInt8 = 0
var reprogIndex: UInt8 = 0
var coordinator = DivertCoordinator()
var divertTimer: DispatchWorkItem?

/// Turns on the receiver's connect notifications, so that a reconnect triggers a new divert.
func enableConnectNotifications() {
    let read = HIDPP.readRegister(device: HIDPP.receiverIndex, address: HIDPP.notificationsRegister)
    guard let flags = receiver.send(read) else {
        log("Cannot read the receiver notification flags.")
        return
    }
    let wanted = HIDPP.withWirelessNotifications(flags)
    guard wanted != Array(flags.prefix(3)) else { return }
    let write = HIDPP.writeRegister(device: HIDPP.receiverIndex, address: HIDPP.notificationsRegister, params: wanted)
    if receiver.send(write) == nil {
        log("Cannot turn on the receiver connect notifications.")
    }
}

/// Finds the mouse on the receiver and diverts the thumb button with raw movement.
/// Returns false if no mouse accepted the divert. The old indices stay until a divert succeeds.
func divertOnce() -> Bool {
    controller.reset()
    enableConnectNotifications()
    for index: UInt8 in 1...6 {
        guard let params = receiver.send(HIDPP.getFeature(device: index, id: HIDPP.reprogControlsV4)),
              params[0] != 0 else { continue }
        // A keyboard on the same receiver can have the feature but not the CID. Its reply is an error.
        let set = HIDPP.setCidReporting(device: index, reprogIndex: params[0],
                                        cid: HIDPP.thumbButton, flags: HIDPP.divertWithRawXY)
        if receiver.send(set) != nil {
            deviceIndex = index
            reprogIndex = params[0]
            log("Thumb button ready (device \(index), feature index \(params[0])).")
            menu.status = .ready
            return true
        }
    }
    return false
}

/// Runs a divert now, unless one is running already or the app is paused.
/// Then does what the coordinator says.
func divert() {
    guard coordinator.begin() else { return }
    switch coordinator.end(success: divertOnce()) {
    case .idle:
        break
    case .runAgain:
        scheduleDivert(after: 0.5)
    case .retry(let delay):
        menu.status = .waiting
        if coordinator.failures == 1 { log("No mouse answered. Trying again in the background.") }
        scheduleDivert(after: delay)
    case .undivert:
        undivert()
    case .quit:
        undivertAndExit()
    }
}

/// Diverts after a delay. A new request replaces a waiting one. Nothing happens during a pause.
func scheduleDivert(after delay: TimeInterval) {
    guard !coordinator.isPaused else { return }
    divertTimer?.cancel()
    let work = DispatchWorkItem { divert() }
    divertTimer = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
}

/// Gives the thumb button back to the mouse.
func undivert() {
    guard deviceIndex != 0 else { return }
    _ = receiver.send(HIDPP.setCidReporting(device: deviceIndex, reprogIndex: reprogIndex,
                                            cid: HIDPP.thumbButton, flags: HIDPP.undivert))
    log("Thumb button given back to the mouse.")
}

func undivertAndExit() -> Never {
    undivert()
    exit(0)
}

/// Stores new settings, gives them to the controller, and updates the menu.
func save(_ newPreferences: Preferences) {
    preferences = newPreferences
    for (key, value) in newPreferences.defaultsValues {
        UserDefaults.standard.set(value, forKey: key)
    }
    controller.apply(newPreferences)
    menu.preferences = newPreferences
    log("Settings: \(newPreferences.mode.rawValue), quick swipe \(newPreferences.quickPreset.rawValue), follow hand \(newPreferences.followPreset.rawValue).")
}

receiver.onReport = { bytes in
    guard let event = Report(bytes).thumbEvent(device: deviceIndex, reprogIndex: reprogIndex) else { return }
    if verbose { log("\(event)") }
    if case .linked(let linked) = event {
        log(linked ? "Mouse connected." : "Mouse disconnected.")
        if linked { scheduleDivert(after: 0.5) }
    }
    for output in controller.handle(event, now: ProcessInfo.processInfo.systemUptime) {
        switch output {
        case .missionControl:
            log("Action: missionControl")
            Actions.perform(.missionControl)
        case .quickSwipe(let action):
            log("Action: \(action)")
            Actions.perform(action)
        case .frame(let frame):
            if frame.phase != .changed || verbose {
                log("Swipe \(frame.phase) offset \(String(format: "%.2f", frame.offset)) exit \(String(format: "%.2f", frame.exitSpeed))")
            }
            Actions.post(frame)
        }
    }
}
receiver.onAttach = {
    log("Receiver found.")
    scheduleDivert(after: 0.5)
}
receiver.onDetach = {
    log("Receiver removed.")
    deviceIndex = 0
    controller.reset()
    if !coordinator.isPaused { menu.status = .waiting }
}

menu.onSelectMode = { mode in
    var newPreferences = preferences
    newPreferences.mode = mode
    save(newPreferences)
}
menu.onSelectPreset = { preset in
    var newPreferences = preferences
    newPreferences.preset = preset
    save(newPreferences)
}
menu.onPause = {
    if coordinator.isPaused {
        coordinator.setPaused(false)
        menu.status = .waiting
        log("Resumed.")
        scheduleDivert(after: 0.1)
    } else {
        coordinator.setPaused(true)
        divertTimer?.cancel()
        menu.status = .paused
        log("Paused.")
        // A divert that is running now gives the button back when it ends.
        if !coordinator.isRunning { undivert() }
    }
}
menu.onOpenLog = {
    let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ThumbGestures.log")
    let console = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
    NSWorkspace.shared.open([logFile], withApplicationAt: console, configuration: NSWorkspace.OpenConfiguration())
}
menu.onQuit = {
    log("Quit from the menu.")
    if coordinator.requestQuit() { undivertAndExit() }
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
) { _ in
    log("Woke from sleep.")
    scheduleDivert(after: 2)
}

// launchd sends SIGTERM at logout and at `launchctl bootout`. Ctrl-C sends SIGINT.
// During a divert, the handler can run inside its wait for a reply. Then the
// divert gives the button back and exits when it ends.
var signalSources: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        if coordinator.requestQuit() { undivertAndExit() }
    }
    source.resume()
    signalSources.append(source)
}

if receiver.start() == Receiver.notPermitted {
    log("Waiting for Input Monitoring permission (System Settings > Privacy & Security > Input Monitoring).")
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    sleep(5)
    exit(1)
}
log("Thumb Gestures is running (\(preferences.mode.rawValue), quick swipe \(preferences.quickPreset.rawValue), follow hand \(preferences.followPreset.rawValue)). Waiting for the receiver.")
app.run()
```

- [ ] **Step 4: Make install.sh wait for launchd**

In `install.sh`, replace:

```bash
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
```

with:

```bash
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
# bootout returns before the old copy is gone. Wait (max 5 s), or bootstrap fails.
for _ in $(seq 50); do
    launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || break
    sleep 0.1
done
```

- [ ] **Step 5: Build, test, and install twice**

Run: `cd ~/code/thumb-gestures && swift test --disable-swift-testing 2>&1 | grep -E "Executed|error:" | tail -1 && ./install.sh 2>&1 | tail -1 && ./install.sh 2>&1 | tail -1 && sleep 4 && tail -3 ~/Library/Logs/ThumbGestures.log`
Expected: `Executed 84 tests, with 0 failures`; both installs print `Log: /Users/e2/Library/Logs/ThumbGestures.log` (manual test 8); the log ends with `Thumb Gestures is running (quickSwipe, quick swipe medium, follow hand medium)...`, `Receiver found.`, and `Thumb button ready (device 1, feature index 10).`

If the log says "Waiting for Accessibility permission", the signature changed: tell the user to remove and add Thumb Gestures in the Accessibility settings.

- [ ] **Step 6: Manual tests with the user**

Ask the user to do each check and report. Check the log after each one.

1. The menu bar shows the icon. The menu shows `Ready`, a checkmark on `Quick Swipe`, and `Distance ▸ Medium`.
2. Quick Swipe works (hold + move switches one Space; click opens Mission Control). Select `Follow Hand`: the next hold follows the hand. The log shows `Settings: followHand, ...`. No restart.
3. In each mode, `Short` and `Long` change the distance. The log shows the new preset.
4. `Pause`: the icon dims, the status line says `Paused`, and the thumb button changes the pointer speed (the mouse's own function). The log shows `Paused.` and `Thumb button given back to the mouse.` `Resume`: the log shows `Resumed.` and `Thumb button ready`, and the gestures work.
5. `Open Log` opens Console with `ThumbGestures.log`.
6. While paused, turn the mouse off and on. The log shows `Mouse connected.` but no `Thumb button ready`. Then `Resume`.
7. `Quit Thumb Gestures`: the icon goes away, and the log shows `Quit from the menu.` and `Thumb button given back to the mouse.` Then start it again with `launchctl kickstart gui/$(id -u)/local.thumbgestures.ThumbGestures` and check for `Thumb button ready`.

If a check fails, use superpowers:systematic-debugging, and report to the user.

- [ ] **Step 7: Commit**

```bash
cd ~/code/thumb-gestures
git add Sources/ThumbGestures install.sh
git commit -m "Add the menu bar menu: mode, distance, pause, log, quit

The app now runs as an accessory NSApplication with a status item.
Settings apply without a restart. install.sh waits for launchd to stop
the old copy before bootstrap.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: README, then merge and push with the user's yes

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the finished feature from Tasks 1-5.
- Produces: an updated README; after the user's yes, `main` on GitHub with this change.

- [ ] **Step 1: Update the README**

In `README.md`:

1. Replace:

```
The direction is the same as a trackpad swipe with natural scrolling. One hold switches one Space. The pointer stays in place during a hold.
```

with:

```
The direction is the same as a trackpad swipe with natural scrolling. The pointer stays in place during a hold. There are two switch modes, and you select one in the menu bar:

- **Quick Swipe:** after a short movement, one quick swipe switches one Space. One hold switches one Space.
- **Follow Hand:** the Space moves with your hand during the hold, as on a trackpad. On release, macOS completes the switch or goes back, from how far and how fast you moved.
```

2. Replace the whole `## Options` section (from `## Options` to the line before `## Test without installing`) with:

````
## Menu

Thumb Gestures has an icon in the menu bar. Its menu has:

- A status line: **Ready**, **Waiting for the mouse**, or **Paused**.
- **Quick Swipe** and **Follow Hand**: the switch mode.
- **Distance**: Short, Medium, or Long, for the selected mode. Each mode keeps its own choice.
- **Pause** / **Resume**: gives the button back to the mouse (it then changes the pointer speed), or takes it again.
- **Open Log**: opens the log in Console.
- **Quit Thumb Gestures**: gives the button back and stops the app until the next login.

A change applies at the next press of the thumb button. No restart is necessary.

| Distance | Quick Swipe: movement to switch | Follow Hand: movement for one full Space |
|---|---|---|
| Short | 400 counts (about 1 cm) | 1000 counts (about 2.5 cm) |
| Medium | 600 counts (about 1.5 cm) | 1500 counts (about 4 cm) |
| Long | 900 counts (about 2.3 cm) | 2200 counts (about 5.5 cm) |

The distances in cm are for 1000 DPI.

Advanced: in Follow Hand mode, `ExitSpeedFactor` changes how much a flick counts on release (default 1):

```bash
defaults write local.thumbgestures.ThumbGestures ExitSpeedFactor -float 1.5
launchctl kickstart -k gui/$(id -u)/local.thumbgestures.ThumbGestures
```
````

3. In `## Troubleshooting`, add this line after the `**Nothing happens.**` line:

```
- **The button does nothing while a menu is open.** macOS pauses the mouse events during a menu. Close the menu.
```

Run: `cd ~/code/thumb-gestures && grep -c "SwitchDistance\|FollowScale\|FollowHand -bool" README.md`
Expected: `0`.

- [ ] **Step 2: Commit**

```bash
cd ~/code/thumb-gestures
git add README.md
git commit -m "Describe the menu, the modes, and the presets in the README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Ask the user before merge and push**

Tell the user: "The menu is done and tested. I am ready to merge `feature/settings-menu` into `main` and push it to GitHub. I can also delete the `spike/follow-hand` branch (local and on GitHub), because `main` then has Follow Hand. Do you approve both?" Wait for a clear yes for each.

- [ ] **Step 4: Merge and push (only after the yes)**

```bash
cd ~/code/thumb-gestures
git checkout main
git merge --ff-only feature/settings-menu
git push origin main
git branch -d feature/settings-menu
```

Only if the user approved the spike branch deletion:

```bash
git branch -D spike/follow-hand
git push origin --delete spike/follow-hand
```
