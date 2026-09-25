# Thumb Gestures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS background app that diverts the MX Vertical thumb button through Logitech HID++: a click opens Mission Control, and a hold with a left or right movement switches one Space.

**Architecture:** A Swift package. The library target `ThumbGesturesCore` has all logic without I/O (HID++ bytes, report decode, the gesture state machine), and unit tests cover it. The executable target `ThumbGestures` has the IOKit receiver, the actions (key events and Mission Control), and the wiring. Shell scripts package it as `Thumb Gestures.app` with a LaunchAgent, the same as Scroll Split (`~/code/scrollsplit`).

**Tech Stack:** Swift 5.9 tools (Swift 6.4 compiler in Swift 5 mode), SwiftPM, XCTest, IOKit HID, CoreGraphics, AppKit, launchd.

**Spec:** `docs/superpowers/specs/2026-09-25-thumb-gestures-design.md`

## Global Constraints

- macOS 13 or later (`platforms: [.macOS(.v13)]`, `LSMinimumSystemVersion` 13.0).
- No third-party dependencies.
- Bundle ID and LaunchAgent label: `local.thumbgestures.ThumbGestures`.
- App name: `Thumb Gestures`. Executable name: `ThumbGestures`.
- Log file: `~/Library/Logs/ThumbGestures.log`.
- Receiver: vendor `0x046D`, product `0xC52B`, primary usage page `0xFF00`.
- Thumb button CID: `0xFD`. Divert flags: `0x33`. Undivert flags: `0x22`.
- HID++ software ID: `0x0A`. Long report ID `0x11`, 20 bytes. Short report ID `0x10`, 7 bytes.
- Default switch distance: 600 mouse counts. Setting: `defaults write local.thumbgestures.ThumbGestures SwitchDistance -int <n>`.
- Moving the mouse **left** gives `.spaceRight` (⌃→). Moving **right** gives `.spaceLeft` (⌃←).
- One switch for each hold. A release without a switch gives Mission Control.
- Request timeout: 1.5 s. Divert delay after wake: 2 s. Divert delay after a connect or a receiver plug-in: 0.5 s.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Do not change Scroll Split (`~/code/scrollsplit`).

## Review Focus

- **Events from other HID++ features** (for example battery reports with software ID 0 at a different feature index) must not act as the thumb button. Test: `testThumbEventIgnoresOtherFeatureIndex` in Task 1.
- **A reply for a different request** (different device, feature, or function) that arrives while the app waits must not count as the answer. Test: `testIsReplyRejectsOtherDeviceFeatureOrFunction` in Task 1.
- **A connection notification before the mouse is found** (device index still 0) must still start a divert. Test: `testThumbEventReportsConnectionForAnyDevice` in Task 1.
- **A repeated "pressed" notification during a hold** must not reset the movement total or allow a second switch. Test: `testRepeatedPressDoesNotResetHold` in Task 2.
- **A bad `SwitchDistance` value** (0, negative, text) must fall back to 600 and not make every tiny movement a switch. Test: `testSwitchDistanceFallsBackToDefault` in Task 2.

---

### Task 1: Package and HID++ message layer

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/ThumbGesturesCore/HIDPP.swift`
- Test: `Tests/ThumbGesturesCoreTests/HIDPPTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum HIDPP` with constants `logitechVendorID: Int`, `unifyingReceiverProductID: Int`, `vendorUsagePage: Int`, `longReportID: UInt8`, `shortReportID: UInt8`, `longLength: Int`, `softwareID: UInt8`, `reprogControlsV4: UInt16`, `thumbButton: UInt16`, `divertWithRawXY: UInt8`, `undivert: UInt8`.
  - `HIDPP.getFeature(device: UInt8, id: UInt16) -> [UInt8]`
  - `HIDPP.setCidReporting(device: UInt8, reprogIndex: UInt8, cid: UInt16, flags: UInt8) -> [UInt8]`
  - `HIDPP.isReply(_ report: Report, to request: [UInt8]) -> Bool`
  - `enum Report: Equatable` with `init(_ bytes: [UInt8])` and cases `response(device:feature:fnsw:params:)`, `error(device:feature:fnsw:code:)`, `buttons(device:feature:cids:)`, `rawXY(device:feature:dx:dy:)`, `connection(device:linked:)`, `other`.
  - `enum ThumbEvent: Equatable { case button(pressed: Bool), move(dx: Int), linked(Bool) }`
  - `Report.thumbEvent(device: UInt8, reprogIndex: UInt8, cid: UInt16 = HIDPP.thumbButton) -> ThumbEvent?`

- [ ] **Step 1: Create the package files**

`Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThumbGestures",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ThumbGesturesCore"),
        .testTarget(name: "ThumbGesturesCoreTests", dependencies: ["ThumbGesturesCore"]),
    ]
)
```

`.gitignore`:

```
.build/
build/
.DS_Store
```

- [ ] **Step 2: Write the failing tests**

`Tests/ThumbGesturesCoreTests/HIDPPTests.swift`:

```swift
import XCTest
@testable import ThumbGesturesCore

final class HIDPPTests: XCTestCase {
    /// Pads the given bytes to a 20-byte long report.
    func long(_ head: [UInt8]) -> [UInt8] {
        head + [UInt8](repeating: 0, count: 20 - head.count)
    }

    func testGetFeatureRequestBytes() {
        XCTAssertEqual(HIDPP.getFeature(device: 1, id: 0x1B04),
                       long([0x11, 0x01, 0x00, 0x0A, 0x1B, 0x04]))
    }

    func testDivertRequestBytes() {
        XCTAssertEqual(HIDPP.setCidReporting(device: 1, reprogIndex: 10, cid: 0xFD, flags: HIDPP.divertWithRawXY),
                       long([0x11, 0x01, 0x0A, 0x3A, 0x00, 0xFD, 0x33, 0x00, 0x00]))
    }

    func testUndivertRequestBytes() {
        XCTAssertEqual(HIDPP.setCidReporting(device: 1, reprogIndex: 10, cid: 0xFD, flags: HIDPP.undivert),
                       long([0x11, 0x01, 0x0A, 0x3A, 0x00, 0xFD, 0x22, 0x00, 0x00]))
    }

    func testDecodeResponse() {
        XCTAssertEqual(Report(long([0x11, 0x01, 0x00, 0x0A, 0x0A])),
                       .response(device: 1, feature: 0, fnsw: 0x0A,
                                 params: [0x0A] + [UInt8](repeating: 0, count: 15)))
    }

    func testDecodeButtonsPressed() {
        XCTAssertEqual(Report(long([0x11, 0x01, 0x0A, 0x00, 0x00, 0xFD])),
                       .buttons(device: 1, feature: 10, cids: [0xFD]))
    }

    func testDecodeButtonsReleased() {
        XCTAssertEqual(Report(long([0x11, 0x01, 0x0A, 0x00])),
                       .buttons(device: 1, feature: 10, cids: []))
    }

    func testDecodeRawXYNegativeAndPositive() {
        // dx = -300 (0xFED4), dy = +5
        XCTAssertEqual(Report(long([0x11, 0x01, 0x0A, 0x10, 0xFE, 0xD4, 0x00, 0x05])),
                       .rawXY(device: 1, feature: 10, dx: -300, dy: 5))
        // dx = +300, dy = -1
        XCTAssertEqual(Report(long([0x11, 0x01, 0x0A, 0x10, 0x01, 0x2C, 0xFF, 0xFF])),
                       .rawXY(device: 1, feature: 10, dx: 300, dy: -1))
    }

    func testDecodeConnection() {
        XCTAssertEqual(Report([0x10, 0x01, 0x41, 0x04, 0x02, 0x7A, 0x40]),
                       .connection(device: 1, linked: true))
        XCTAssertEqual(Report([0x10, 0x01, 0x41, 0x04, 0x42, 0x7A, 0x40]),
                       .connection(device: 1, linked: false))
    }

    func testDecodeErrors() {
        // HID++ 2.0 error (long report)
        XCTAssertEqual(Report(long([0x11, 0x01, 0xFF, 0x0A, 0x3A, 0x02])),
                       .error(device: 1, feature: 10, fnsw: 0x3A, code: 0x02))
        // HID++ 1.0 error (short report), for example an empty receiver slot
        XCTAssertEqual(Report([0x10, 0x03, 0x8F, 0x00, 0x0A, 0x09, 0x00]),
                       .error(device: 3, feature: 0, fnsw: 0x0A, code: 0x09))
    }

    func testDecodeTooShortIsOther() {
        XCTAssertEqual(Report([0x11, 0x01]), .other)
    }

    func testIsReplyAcceptsResponseAndError() {
        let request = HIDPP.getFeature(device: 1, id: 0x1B04)
        XCTAssertTrue(HIDPP.isReply(Report(long([0x11, 0x01, 0x00, 0x0A, 0x0A])), to: request))
        XCTAssertTrue(HIDPP.isReply(Report([0x10, 0x01, 0x8F, 0x00, 0x0A, 0x09, 0x00]), to: request))
    }

    func testIsReplyRejectsOtherDeviceFeatureOrFunction() {
        let request = HIDPP.getFeature(device: 1, id: 0x1B04)
        XCTAssertFalse(HIDPP.isReply(Report(long([0x11, 0x02, 0x00, 0x0A, 0x0A])), to: request))
        XCTAssertFalse(HIDPP.isReply(Report(long([0x11, 0x01, 0x05, 0x0A, 0x0A])), to: request))
        XCTAssertFalse(HIDPP.isReply(Report(long([0x11, 0x01, 0x00, 0x1A, 0x0A])), to: request))
        XCTAssertFalse(HIDPP.isReply(Report(long([0x11, 0x01, 0x00, 0x00, 0x00, 0xFD])), to: request))
    }

    func testThumbEventButtonAndMove() {
        XCTAssertEqual(Report(long([0x11, 0x01, 0x0A, 0x00, 0x00, 0xFD])).thumbEvent(device: 1, reprogIndex: 10),
                       .button(pressed: true))
        XCTAssertEqual(Report(long([0x11, 0x01, 0x0A, 0x00])).thumbEvent(device: 1, reprogIndex: 10),
                       .button(pressed: false))
        XCTAssertEqual(Report(long([0x11, 0x01, 0x0A, 0x10, 0xFE, 0xD4, 0x00, 0x05])).thumbEvent(device: 1, reprogIndex: 10),
                       .move(dx: -300))
    }

    func testThumbEventIgnoresOtherFeatureIndex() {
        // A battery event at feature index 8 has the same shape as a buttons notification.
        XCTAssertNil(Report(long([0x11, 0x01, 0x08, 0x00, 0x00, 0xFD])).thumbEvent(device: 1, reprogIndex: 10))
        XCTAssertNil(Report(long([0x11, 0x01, 0x08, 0x10, 0xFE, 0xD4])).thumbEvent(device: 1, reprogIndex: 10))
    }

    func testThumbEventIgnoresOtherDevice() {
        XCTAssertNil(Report(long([0x11, 0x02, 0x0A, 0x00, 0x00, 0xFD])).thumbEvent(device: 1, reprogIndex: 10))
    }

    func testThumbEventReportsConnectionForAnyDevice() {
        // Before the mouse is found, the device index is 0.
        XCTAssertEqual(Report([0x10, 0x01, 0x41, 0x04, 0x02, 0x7A, 0x40]).thumbEvent(device: 0, reprogIndex: 0),
                       .linked(true))
        XCTAssertEqual(Report([0x10, 0x02, 0x41, 0x04, 0x42, 0x7A, 0x40]).thumbEvent(device: 1, reprogIndex: 10),
                       .linked(false))
    }

    func testThumbEventOtherButtonIsRelease() {
        // Only the watched CID counts as pressed.
        XCTAssertEqual(Report(long([0x11, 0x01, 0x0A, 0x00, 0x00, 0x53])).thumbEvent(device: 1, reprogIndex: 10),
                       .button(pressed: false))
    }
}
```

- [ ] **Step 3: Run the tests to make sure they fail**

Run: `cd ~/code/thumb-gestures && swift test 2>&1 | tail -20`
Expected: build FAIL with errors like "cannot find 'HIDPP' in scope".

- [ ] **Step 4: Write the implementation**

`Sources/ThumbGesturesCore/HIDPP.swift`:

```swift
// Logitech HID++ 2.0 messages for the thumb button: build requests and decode reports.
// This file does no I/O.

public enum HIDPP {
    public static let logitechVendorID = 0x046D
    public static let unifyingReceiverProductID = 0xC52B
    public static let vendorUsagePage = 0xFF00

    public static let shortReportID: UInt8 = 0x10
    public static let longReportID: UInt8 = 0x11
    public static let longLength = 20
    public static let softwareID: UInt8 = 0x0A

    public static let reprogControlsV4: UInt16 = 0x1B04
    public static let thumbButton: UInt16 = 0x00FD

    /// setCidReporting flags: divert + valid, raw XY + valid.
    public static let divertWithRawXY: UInt8 = 0x33
    /// setCidReporting flags: divert off + valid, raw XY off + valid.
    public static let undivert: UInt8 = 0x22

    /// A long request: report ID, device index, feature index, function and software ID, params.
    public static func request(device: UInt8, feature: UInt8, function: UInt8, params: [UInt8] = []) -> [UInt8] {
        var bytes = [longReportID, device, feature, (function << 4) | softwareID] + params
        bytes += [UInt8](repeating: 0, count: max(0, longLength - bytes.count))
        return bytes
    }

    /// Root.getFeature: the reply's first param is the feature index (0 = not present).
    public static func getFeature(device: UInt8, id: UInt16) -> [UInt8] {
        request(device: device, feature: 0x00, function: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF)])
    }

    /// REPROG_CONTROLS_V4.setCidReporting, with no remap.
    public static func setCidReporting(device: UInt8, reprogIndex: UInt8, cid: UInt16, flags: UInt8) -> [UInt8] {
        request(device: device, feature: reprogIndex, function: 3,
                params: [UInt8(cid >> 8), UInt8(cid & 0xFF), flags, 0, 0])
    }

    /// True if the report is the response or the error for this request.
    public static func isReply(_ report: Report, to request: [UInt8]) -> Bool {
        switch report {
        case let .response(device, feature, fnsw, _), let .error(device, feature, fnsw, _):
            return device == request[1] && feature == request[2] && fnsw == request[3]
        default:
            return false
        }
    }
}

public enum Report: Equatable {
    case response(device: UInt8, feature: UInt8, fnsw: UInt8, params: [UInt8])
    case error(device: UInt8, feature: UInt8, fnsw: UInt8, code: UInt8)
    /// Diverted buttons that are down now. Empty = all released.
    case buttons(device: UInt8, feature: UInt8, cids: [UInt16])
    /// Raw movement during a diverted hold.
    case rawXY(device: UInt8, feature: UInt8, dx: Int, dy: Int)
    /// A device on the receiver connected (linked) or disconnected.
    case connection(device: UInt8, linked: Bool)
    case other

    public init(_ r: [UInt8]) {
        guard r.count >= 7 else { self = .other; return }
        let device = r[1]

        // 0xFF = HID++ 2.0 error, 0x8F = HID++ 1.0 error. Same layout.
        if r[2] == 0xFF || r[2] == 0x8F {
            self = .error(device: device, feature: r[3], fnsw: r[4], code: r[5])
            return
        }
        // Receiver device connection notification. Bit 6 of byte 4 = link not established.
        if r[0] == HIDPP.shortReportID && r[2] == 0x41 {
            self = .connection(device: device, linked: r[4] & 0x40 == 0)
            return
        }
        guard r[0] == HIDPP.longReportID, r.count >= HIDPP.longLength else { self = .other; return }

        let fnsw = r[3]
        if fnsw & 0x0F == HIDPP.softwareID {
            self = .response(device: device, feature: r[2], fnsw: fnsw, params: Array(r[4..<HIDPP.longLength]))
            return
        }
        guard fnsw & 0x0F == 0 else { self = .other; return }

        switch fnsw >> 4 {
        case 0:
            let cids = stride(from: 4, to: 12, by: 2)
                .map { UInt16(r[$0]) << 8 | UInt16(r[$0 + 1]) }
                .filter { $0 != 0 }
            self = .buttons(device: device, feature: r[2], cids: cids)
        case 1:
            let dx = Int(Int16(bitPattern: UInt16(r[4]) << 8 | UInt16(r[5])))
            let dy = Int(Int16(bitPattern: UInt16(r[6]) << 8 | UInt16(r[7])))
            self = .rawXY(device: device, feature: r[2], dx: dx, dy: dy)
        default:
            self = .other
        }
    }
}

public enum ThumbEvent: Equatable {
    case button(pressed: Bool)
    case move(dx: Int)
    case linked(Bool)
}

extension Report {
    /// The event for the watched button, or nil if the report is not for it.
    /// Connection notifications count for any device, so a divert can start before the mouse is found.
    public func thumbEvent(device: UInt8, reprogIndex: UInt8, cid: UInt16 = HIDPP.thumbButton) -> ThumbEvent? {
        switch self {
        case let .buttons(d, f, cids) where d == device && f == reprogIndex:
            return .button(pressed: cids.contains(cid))
        case let .rawXY(d, f, dx, _) where d == device && f == reprogIndex:
            return .move(dx: dx)
        case let .connection(_, linked):
            return .linked(linked)
        default:
            return nil
        }
    }
}
```

- [ ] **Step 5: Run the tests to make sure they pass**

Run: `cd ~/code/thumb-gestures && swift test 2>&1 | grep -E "Executed|error|failed"`
Expected: `Executed 17 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
cd ~/code/thumb-gestures
git add Package.swift .gitignore Sources Tests
git commit -m "Add HID++ message layer with tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Gesture state machine and settings

**Files:**
- Create: `Sources/ThumbGesturesCore/Gesture.swift`
- Test: `Tests/ThumbGesturesCoreTests/GestureTests.swift`

**Interfaces:**
- Consumes: `ThumbEvent` from Task 1.
- Produces:
  - `enum GestureAction: Equatable { case missionControl, spaceLeft, spaceRight }`
  - `struct Gesture` with `init(distance: Int)`, `let distance: Int`, `private(set) var isHeld: Bool`, `mutating func handle(_ event: ThumbEvent) -> GestureAction?`, `mutating func reset()`.
  - `enum Settings` with `static let defaultSwitchDistance = 600` and `static func switchDistance(_ value: Any?) -> Int`.

- [ ] **Step 1: Write the failing tests**

`Tests/ThumbGesturesCoreTests/GestureTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `cd ~/code/thumb-gestures && swift test 2>&1 | tail -20`
Expected: build FAIL with errors like "cannot find 'Gesture' in scope".

- [ ] **Step 3: Write the implementation**

`Sources/ThumbGesturesCore/Gesture.swift`:

```swift
// The thumb button gesture: a click, or a hold with a horizontal movement.
// This file does no I/O.

public enum GestureAction: Equatable {
    case missionControl
    case spaceLeft
    case spaceRight
}

public struct Gesture {
    /// Horizontal movement, in mouse counts, that starts a Space switch.
    public let distance: Int
    public private(set) var isHeld = false
    private var total = 0
    private var switched = false

    public init(distance: Int) {
        self.distance = max(1, distance)
    }

    public mutating func handle(_ event: ThumbEvent) -> GestureAction? {
        switch event {
        case .button(pressed: true):
            // The mouse can report "pressed" again during a hold. Keep the hold.
            if !isHeld {
                isHeld = true
                total = 0
                switched = false
            }
            return nil
        case .button(pressed: false):
            guard isHeld else { return nil }
            isHeld = false
            return switched ? nil : .missionControl
        case .move(let dx):
            guard isHeld, !switched else { return nil }
            total += dx
            guard abs(total) >= distance else { return nil }
            switched = true
            // Like a natural trackpad swipe: moving left pushes the Space away and shows the one on the right.
            return total < 0 ? .spaceRight : .spaceLeft
        case .linked:
            // A release can get lost while the mouse reconnects.
            reset()
            return nil
        }
    }

    public mutating func reset() {
        isHeld = false
        total = 0
        switched = false
    }
}

public enum Settings {
    public static let defaultSwitchDistance = 600

    /// The SwitchDistance user default, or the default if it is missing or not a positive number.
    public static func switchDistance(_ value: Any?) -> Int {
        if let number = value as? Int, number > 0 { return number }
        return defaultSwitchDistance
    }
}
```

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `cd ~/code/thumb-gestures && swift test 2>&1 | grep -E "Executed|error|failed"`
Expected: `Executed 31 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
cd ~/code/thumb-gestures
git add Sources/ThumbGesturesCore/Gesture.swift Tests/ThumbGesturesCoreTests/GestureTests.swift
git commit -m "Add gesture state machine and settings with tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The app, the build script, and the hardware checks

This task has the first test on the mouse. **Step 7 is a stop point.** If the raw XY mode does not work, stop and report to the user. Do not change to a different approach without the user's approval.

**Files:**
- Modify: `Package.swift` (add the executable target)
- Create: `Sources/ThumbGestures/Log.swift`
- Create: `Sources/ThumbGestures/Receiver.swift`
- Create: `Sources/ThumbGestures/Actions.swift`
- Create: `Sources/ThumbGestures/main.swift`
- Create: `Resources/Info.plist`
- Create: `build.sh`

**Interfaces:**
- Consumes: everything that Task 1 and Task 2 produce.
- Produces:
  - `build/Thumb Gestures.app` from `./build.sh`. Task 4 adds the icon step to this script.
  - `func log(_ message: String)` and `let verbose: Bool` (app target).
  - `final class Receiver` with `static let notPermitted: IOReturn`, `var onReport: (([UInt8]) -> Void)?`, `var onAttach: (() -> Void)?`, `var onDetach: (() -> Void)?`, `func start() -> IOReturn`, `func send(_ request: [UInt8], timeout: TimeInterval = 1.5) -> [UInt8]?`.
  - `enum Actions` with `static func perform(_ action: GestureAction)`.

- [ ] **Step 1: Add the executable target**

Replace `Package.swift` with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThumbGestures",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ThumbGesturesCore"),
        .executableTarget(name: "ThumbGestures", dependencies: ["ThumbGesturesCore"]),
        .testTarget(name: "ThumbGesturesCoreTests", dependencies: ["ThumbGesturesCore"]),
    ]
)
```

- [ ] **Step 2: Write the log helper**

`Sources/ThumbGestures/Log.swift`:

```swift
import Foundation

let verbose = CommandLine.arguments.contains("--verbose")

private let timestamp = ISO8601DateFormatter()

func log(_ message: String) {
    print("\(timestamp.string(from: Date())) \(message)")
}
```

- [ ] **Step 3: Write the receiver**

`Sources/ThumbGestures/Receiver.swift`:

```swift
import Foundation
import IOKit.hid
import ThumbGesturesCore

/// The HID++ interface of a Logitech Unifying receiver.
final class Receiver {
    /// kIOReturnNotPermitted: macOS blocked the open (Input Monitoring).
    static let notPermitted = IOReturn(bitPattern: 0xE00002E2)

    /// Every input report that is not the reply to a pending request.
    var onReport: (([UInt8]) -> Void)?
    var onAttach: (() -> Void)?
    var onDetach: (() -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var pending: [UInt8]?
    private var reply: Report?

    init() {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: HIDPP.logitechVendorID,
            kIOHIDProductIDKey: HIDPP.unifyingReceiverProductID,
            kIOHIDPrimaryUsagePageKey: HIDPP.vendorUsagePage,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<Receiver>.fromOpaque(context!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<Receiver>.fromOpaque(context!).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func start() -> IOReturn {
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Sends a request and waits for its reply. Returns the reply params, or nil on an error or a timeout.
    func send(_ request: [UInt8], timeout: TimeInterval = 1.5) -> [UInt8]? {
        guard let device else { return nil }
        pending = request
        reply = nil
        defer { pending = nil }

        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(request[0]), request, request.count)
        guard result == kIOReturnSuccess else {
            log(String(format: "Send failed: 0x%08X", result))
            return nil
        }
        let end = Date().addingTimeInterval(timeout)
        while reply == nil, Date() < end {
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
        }
        if case let .response(_, _, _, params)? = reply { return params }
        return nil
    }

    private func attach(_ newDevice: IOHIDDevice) {
        device = newDevice
        IOHIDDeviceRegisterInputReportCallback(newDevice, buffer, 64, { context, _, _, _, _, report, length in
            let receiver = Unmanaged<Receiver>.fromOpaque(context!).takeUnretainedValue()
            receiver.received(Array(UnsafeBufferPointer(start: report, count: length)))
        }, Unmanaged.passUnretained(self).toOpaque())
        onAttach?()
    }

    private func detach(_ oldDevice: IOHIDDevice) {
        guard let device, CFEqual(device, oldDevice) else { return }
        self.device = nil
        onDetach?()
    }

    private func received(_ bytes: [UInt8]) {
        let report = Report(bytes)
        if let pending, reply == nil, HIDPP.isReply(report, to: pending) {
            reply = report
            return
        }
        onReport?(bytes)
    }
}
```

- [ ] **Step 4: Write the actions**

`Sources/ThumbGestures/Actions.swift`:

```swift
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
```

- [ ] **Step 5: Write the main file**

`Sources/ThumbGestures/main.swift`:

```swift
// Thumb Gestures — actions for the thumb button of a Logitech MX Vertical.
//
// Click: Mission Control. Hold and move left or right: switch one Space.
// The app diverts the button through Logitech HID++ on the receiver, so
// Logi Options+ is not necessary. The mouse forgets the divert when it
// reconnects, so the app sends it again after a connect, a wake, or a plug-in.

import AppKit
import ApplicationServices
import IOKit.hid
import ThumbGesturesCore

setvbuf(stdout, nil, _IOLBF, 0)

// Two copies would both act on each click.
let lockPath = NSTemporaryDirectory() + "thumbgestures.lock"
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    log("Thumb Gestures is already running. This copy will exit.")
    exit(0)
}

// Accessibility is necessary to post the ⌃← and ⌃→ key events. A running
// process does not see the permission change, so exit and let launchd start
// a new copy that does. Show the system prompt only on the first try.
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let promptedKey = "PromptedForAccessibility"
let prompt = !UserDefaults.standard.bool(forKey: promptedKey)
if !AXIsProcessTrustedWithOptions([promptKey: prompt] as CFDictionary) {
    UserDefaults.standard.set(true, forKey: promptedKey)
    log("Waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility).")
    sleep(5)
    exit(1)
}

var gesture = Gesture(distance: Settings.switchDistance(UserDefaults.standard.object(forKey: "SwitchDistance")))
let receiver = Receiver()
var deviceIndex: UInt8 = 0
var reprogIndex: UInt8 = 0
var divertPending = false

/// Finds the mouse on the receiver and diverts the thumb button with raw movement.
func divert() {
    gesture.reset()
    deviceIndex = 0
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
            return
        }
    }
    log("No mouse answered. Waiting for it to connect.")
}

/// Gives the thumb button back to the mouse.
func undivert() {
    guard deviceIndex != 0 else { return }
    _ = receiver.send(HIDPP.setCidReporting(device: deviceIndex, reprogIndex: reprogIndex,
                                            cid: HIDPP.thumbButton, flags: HIDPP.undivert))
    log("Thumb button given back to the mouse.")
}

/// Diverts after a delay. Many triggers close together cause one divert.
func scheduleDivert(after delay: TimeInterval) {
    guard !divertPending else { return }
    divertPending = true
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        divertPending = false
        divert()
    }
}

receiver.onReport = { bytes in
    guard let event = Report(bytes).thumbEvent(device: deviceIndex, reprogIndex: reprogIndex) else { return }
    if verbose { log("\(event)") }
    if case .linked(let linked) = event {
        log(linked ? "Mouse connected." : "Mouse disconnected.")
        if linked { scheduleDivert(after: 0.5) }
    }
    if let action = gesture.handle(event) {
        log("Action: \(action)")
        Actions.perform(action)
    }
}
receiver.onAttach = {
    log("Receiver found.")
    scheduleDivert(after: 0.5)
}
receiver.onDetach = {
    log("Receiver removed.")
    deviceIndex = 0
    gesture.reset()
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
) { _ in
    log("Woke from sleep.")
    scheduleDivert(after: 2)
}

// launchd sends SIGTERM at logout and at `launchctl bootout`. Ctrl-C sends SIGINT.
var signalSources: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        undivert()
        exit(0)
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
log("Thumb Gestures is running (switch distance \(gesture.distance)). Waiting for the receiver.")
CFRunLoopRun()
```

- [ ] **Step 6: Write the Info.plist and the build script**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Thumb Gestures</string>
    <key>CFBundleDisplayName</key><string>Thumb Gestures</string>
    <key>CFBundleIdentifier</key><string>local.thumbgestures.ThumbGestures</string>
    <key>CFBundleExecutable</key><string>ThumbGestures</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Thumb Gestures</string>
</dict>
</plist>
```

`build.sh` (then run `chmod +x build.sh`):

```bash
#!/bin/bash
# Build "Thumb Gestures.app" into ./build.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Thumb Gestures.app"
swift build -c release --product ThumbGestures
BIN="$(swift build -c release --show-bin-path)/ThumbGestures"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/ThumbGestures"

codesign --force --sign - "$APP"
echo "Built $APP"
```

Run: `cd ~/code/thumb-gestures && chmod +x build.sh && ./build.sh 2>&1 | tail -3 && swift test 2>&1 | grep Executed`
Expected: `Built build/Thumb Gestures.app` and `Executed 31 tests, with 0 failures`.

- [ ] **Step 7: Hardware check — raw XY (STOP POINT)**

The user must be at the mouse. Tell the user what to do before you start the run: "Push the thumb button once. Then hold it and move the mouse left, release, hold it and move right, release. Look at the pointer during the holds."

The terminal app needs Accessibility for this run, the same as the Scroll Split test. If the log says "Waiting for Accessibility permission", tell the user to turn on the terminal app in System Settings > Privacy & Security > Accessibility for the test, and run again.

Run in the background (60 s, then SIGINT):

```bash
cd ~/code/thumb-gestures && ("build/Thumb Gestures.app/Contents/MacOS/ThumbGestures" --verbose & PID=$!; sleep 60; kill -INT $PID; wait $PID; echo "exit $?")
```

Expected log:
- `Receiver found.` then `Thumb button ready (device 1, feature index 10).`
- For each push: `button(pressed: true)`, then `button(pressed: false)`, then `Action: missionControl` (only when there was no switch).
- During a hold with movement: many `move(dx: ...)` lines, negative for left and positive for right.
- `Thumb button given back to the mouse.` and `exit 0` at the end.
- Ask the user: the pointer must stay in place during a hold.

If there are no `move` lines, or the pointer moves during a hold, or the divert reply is an error: **STOP.** Report the log to the user. The fallback (an event tap for the movement) is a design change and needs the user's approval.

If Input Monitoring blocks the open (`Waiting for Input Monitoring permission`), note it for the README in Task 4 and continue after the user turns it on.

- [ ] **Step 8: Hardware check — the actions**

Tell the user: "Make sure that you have at least 2 Spaces (for example a full-screen app). Click the thumb button once. Then hold and move left, and hold and move right. Tell me what happened each time."

Run the same command as Step 7.

Expected:
- A click opens Mission Control.
- Hold + move left switches to the Space on the right. Hold + move right switches to the Space on the left.
- A long movement in one hold switches only one Space.
- Ask the user if 600 counts feels correct. If not, change `Settings.defaultSwitchDistance` and the matching test values in `GestureTests.swift` (the tests use 600 through `Gesture(distance: 600)`; only `testSwitchDistanceFallsBackToDefault` depends on the default), and run `swift test` again.

If ⌃← / ⌃→ do not switch Spaces: check `defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys` for keys 79 and 81 (`enabled = 1`). If they are enabled and it still fails, change the flags in `pressControlArrow` to `[.maskControl, .maskSecondaryFn, .maskNumericPad]`, build, and test again. If this also fails, stop and report to the user.

- [ ] **Step 9: Commit**

```bash
cd ~/code/thumb-gestures
git add Package.swift Sources/ThumbGestures Resources/Info.plist build.sh
git commit -m "Add Thumb Gestures app: receiver, actions, and wiring

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Icon, install scripts, README, and the installed tests

**Files:**
- Create: `tools/make-icon.swift`
- Modify: `build.sh` (add the icon step)
- Create: `install.sh`, `uninstall.sh`
- Create: `README.md`, `LICENSE`, `docs/icon.png`

**Interfaces:**
- Consumes: `build.sh` from Task 3.
- Produces: `/Applications/Thumb Gestures.app` and `~/Library/LaunchAgents/local.thumbgestures.ThumbGestures.plist` after `./install.sh`.

- [ ] **Step 1: Write the icon script**

`tools/make-icon.swift`:

```swift
// Draws the Thumb Gestures app icon and writes an .iconset folder.
// Usage: swift tools/make-icon.swift <output.iconset>

import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// A horizontal arrow from x0 (tail) to x1 (tip) on the line y, in a 1024 canvas.
func arrowPath(from x0: CGFloat, to x1: CGFloat, y: CGFloat) -> CGPath {
    let shaftH: CGFloat = 64, headH: CGFloat = 200, headW: CGFloat = 150
    let neck = x1 - (x1 > x0 ? headW : -headW)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x1, y: y))
    p.addLine(to: CGPoint(x: neck, y: y + headH / 2))
    p.addLine(to: CGPoint(x: neck, y: y + shaftH / 2))
    p.addLine(to: CGPoint(x: x0, y: y + shaftH / 2))
    p.addLine(to: CGPoint(x: x0, y: y - shaftH / 2))
    p.addLine(to: CGPoint(x: neck, y: y - shaftH / 2))
    p.addLine(to: CGPoint(x: neck, y: y - headH / 2))
    p.closeSubpath()
    return p
}

func fill(_ ctx: CGContext, _ path: CGPath, light: UInt32, dark: UInt32) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: nil, colors: [color(light), color(dark)] as CFArray, locations: [0, 1])!
    let box = path.boundingBox
    ctx.drawLinearGradient(g, start: CGPoint(x: box.midX, y: box.maxY),
                           end: CGPoint(x: box.midX, y: box.minY), options: [])
    ctx.restoreGState()
}

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // macOS icon grid: 824 pt body inside a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(color(0x1E1B2E)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [color(0x3A2F5C), color(0x16132A)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

    // Left and right arrows: the Space switch.
    fill(ctx, arrowPath(from: 410, to: 190, y: 512), light: 0x7FE3C8, dark: 0x3FB59A)
    fill(ctx, arrowPath(from: 614, to: 834, y: 512), light: 0x7FE3C8, dark: 0x3FB59A)

    // The thumb button in the center.
    let button = CGPath(ellipseIn: CGRect(x: 422, y: 422, width: 180, height: 180), transform: nil)
    fill(ctx, button, light: 0xFFB36B, dark: 0xF0784A)

    // Soft top highlight.
    let shine = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 640), options: [])
    ctx.restoreGState()

    ctx.addPath(shape); ctx.setStrokeColor(color(0xFFFFFF, 0.10)); ctx.setLineWidth(3); ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(size: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(size: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
```

- [ ] **Step 2: Add the icon step to the build script**

In `build.sh`, replace the line `codesign --force --sign - "$APP"` with:

```bash
swift tools/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
```

Run: `cd ~/code/thumb-gestures && ./build.sh 2>&1 | tail -1 && mkdir -p docs && cp build/AppIcon.iconset/icon_256x256.png docs/icon.png`
Expected: `Built build/Thumb Gestures.app`. Open `docs/icon.png` and show it to the user.

- [ ] **Step 3: Write the install and uninstall scripts**

`install.sh`:

```bash
#!/bin/bash
# Build Thumb Gestures, copy it to /Applications, and start it at login.
set -euo pipefail
cd "$(dirname "$0")"

LABEL="local.thumbgestures.ThumbGestures"
APP="/Applications/Thumb Gestures.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/ThumbGestures.log"

./build.sh

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -rf "$APP"
cp -R "build/Thumb Gestures.app" "$APP"

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>AssociatedBundleIdentifiers</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/ThumbGestures</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $APP"
echo "Allow 'Thumb Gestures' in System Settings > Privacy & Security > Accessibility."
echo "Log: $LOG"
```

`uninstall.sh`:

```bash
#!/bin/bash
# Stop Thumb Gestures and remove the app and the login item.
LABEL="local.thumbgestures.ThumbGestures"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "/Applications/Thumb Gestures.app"
echo "Removed. Also remove 'Thumb Gestures' from System Settings > Privacy & Security > Accessibility."
```

Run: `cd ~/code/thumb-gestures && chmod +x install.sh uninstall.sh`

- [ ] **Step 4: Write the LICENSE**

`LICENSE`: the MIT license text, with the line `Copyright (c) 2026 Eduards Egle`. Copy the text from `~/code/scrollsplit/LICENSE`.

Run: `cp ~/code/scrollsplit/LICENSE ~/code/thumb-gestures/LICENSE && head -3 ~/code/thumb-gestures/LICENSE`
Expected: `MIT License` and `Copyright (c) 2026 Eduards Egle`.

- [ ] **Step 5: Write the README**

`README.md` (if Task 3 Step 7 showed that Input Monitoring is necessary, add it to install step 3 and to Troubleshooting):

````markdown
<p align="center">
  <img src="docs/icon.png" width="128" alt="Thumb Gestures icon">
</p>

<h1 align="center">Thumb Gestures</h1>

<p align="center">Mission Control and Space switching on the Logitech MX Vertical thumb button. No Logi Options+.</p>

---

## Why

The Logitech MX Vertical has a button on top of the thumb rest. Only Logi Options+ can assign an action to it. The button sends no normal mouse button event, so other remap tools cannot see it.

Thumb Gestures is a tiny background app that gives the button these actions:

| Input | Action |
|---|---|
| Click the thumb button | Open Mission Control |
| Hold the thumb button and move the mouse left | Switch to the Space on the right |
| Hold the thumb button and move the mouse right | Switch to the Space on the left |

The direction is the same as a trackpad swipe with natural scrolling. One hold switches one Space. The pointer stays in place during a hold.

## How it works

Thumb Gestures talks to the mouse through the Logitech HID++ protocol on the Unifying receiver, the same channel that Logi Options+ uses. It tells the mouse to send the thumb button presses and the movement during a hold to the app ("divert"). The app then sends the macOS shortcuts ⌃← or ⌃→ ("Move left/right a space"), or opens Mission Control.

The mouse forgets the divert when it sleeps or reconnects. The app sends it again after a reconnect, a wake from sleep, or a receiver plug-in. When the app stops, it gives the button back to the mouse.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)
- A Logitech MX Vertical on a Logitech Unifying receiver (USB ID `046d:c52b`). Bluetooth and Bolt receivers are not supported yet.
- The "Move left a space" and "Move right a space" shortcuts enabled in System Settings > Keyboard > Keyboard Shortcuts > Mission Control (they are enabled by default).

## Install

1. Clone the repo and run the installer:
   ```bash
   git clone https://github.com/EduardsE/thumb-gestures.git
   cd thumb-gestures
   ./install.sh
   ```
2. Open System Settings > Privacy & Security > Accessibility and turn on **Thumb Gestures**. If it is not in the list, click **+** and select `/Applications/Thumb Gestures.app`.

The installer builds `Thumb Gestures.app`, copies it to `/Applications`, and adds a LaunchAgent so it starts at login. After you give the permission, Thumb Gestures starts on its own within about 15 seconds.

To open the Accessibility settings directly:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

## Uninstall

```bash
./uninstall.sh
```

Then remove **Thumb Gestures** from System Settings > Privacy & Security > Accessibility.

## Options

The switch distance is the horizontal movement, in mouse counts, that starts a Space switch. The default is 600 (about 1.5 cm at 1000 DPI). To change it:

```bash
defaults write local.thumbgestures.ThumbGestures SwitchDistance -int 800
launchctl kickstart -k gui/$(id -u)/local.thumbgestures.ThumbGestures
```

## Test without installing

```bash
./build.sh
"build/Thumb Gestures.app/Contents/MacOS/ThumbGestures" --verbose
```

`--verbose` prints each button event and movement. When you run it from a terminal, macOS checks the Accessibility permission of the terminal app, not of Thumb Gestures. Press Ctrl-C to stop. The app then gives the button back to the mouse.

## Troubleshooting

- **Nothing happens.** Check the log at `~/Library/Logs/ThumbGestures.log`. It must show `Thumb button ready`. If it says it is waiting for permission, turn on Thumb Gestures in the Accessibility settings.
- **Do not run Logi Options+ at the same time.** It also takes control of the button.
- **The Space does not switch.** Make sure that you have more than one Space (a full-screen app is a Space), and that the Mission Control shortcuts are enabled.
- **It stopped after a reinstall.** Each build has a new ad-hoc signature, so macOS can drop the permission. Turn it off and on again in the Accessibility settings.
- **The button does nothing after a crash.** The mouse still diverts the button. Turn the mouse off and on to give the button back.

## Notes

- Tested with a Logitech MX Vertical on a Unifying receiver.
- Works next to [Scroll Split](https://github.com/EduardsE/scroll-split).

## License

[MIT](LICENSE)
````

- [ ] **Step 6: Install and run the installed tests**

Run: `cd ~/code/thumb-gestures && ./install.sh 2>&1 | tail -3`

Then tell the user: "Turn on Thumb Gestures in System Settings > Privacy & Security > Accessibility." Give the user this command to open the page:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

After the user confirms, check the log:

Run: `tail -5 ~/Library/Logs/ThumbGestures.log`
Expected: `Thumb button ready (device 1, feature index 10).` If the log still says "Waiting for Accessibility permission" after 15 s, run `launchctl kickstart -k gui/$(id -u)/local.thumbgestures.ThumbGestures`.

Ask the user to do each check below, one at a time, and report the result:

1. A click opens Mission Control. Hold + move left and hold + move right switch Spaces in the correct directions.
2. Scroll Split still works: the trackpad scrolls natural, and the mouse wheel scrolls classic.
3. Sleep and wake: put the Mac to sleep (Apple menu > Sleep), wake it, wait 5 s, and click the thumb button. Mission Control must open. The log must show `Woke from sleep.` and `Thumb button ready`.
4. Reconnect: turn the mouse off with its switch on the bottom, wait 5 s, turn it on, and click the thumb button. The log must show `Mouse disconnected.`, `Mouse connected.`, and `Thumb button ready`.
5. Give back: run `launchctl bootout gui/$(id -u)/local.thumbgestures.ThumbGestures`. The log must show `Thumb button given back to the mouse.` Then run `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.thumbgestures.ThumbGestures.plist` to start it again, and check for `Thumb button ready`.

If a check fails, stop and report the log to the user.

- [ ] **Step 7: Commit**

```bash
cd ~/code/thumb-gestures
git add tools build.sh install.sh uninstall.sh README.md LICENSE docs/icon.png
git commit -m "Add icon, install scripts, README, and license

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Publish the repo

**Files:** none.

**Interfaces:**
- Consumes: the committed repo from Tasks 1–4.
- Produces: the public repo `https://github.com/EduardsE/thumb-gestures`.

- [ ] **Step 1: Ask the user before you publish**

Tell the user: "All tests pass. I am ready to make the public repo `EduardsE/thumb-gestures` and push `main`. The commits use your git email. Do you approve?" Wait for a clear yes.

- [ ] **Step 2: Make the repo and push**

```bash
cd ~/code/thumb-gestures
gh repo create EduardsE/thumb-gestures --public --source . --push \
  --description "Mission Control and Space switching on the Logitech MX Vertical thumb button. No Logi Options+."
gh repo edit EduardsE/thumb-gestures --add-topic macos --add-topic logitech --add-topic mx-vertical --add-topic hidpp --add-topic swift
gh repo view EduardsE/thumb-gestures --json url,visibility -q '.url + " " + .visibility'
```

Expected: `https://github.com/EduardsE/thumb-gestures PUBLIC`.

- [ ] **Step 3: Link Scroll Split to the new repo (optional)**

Ask the user if the Scroll Split README must have a link to Thumb Gestures. Do not change Scroll Split without a yes.
