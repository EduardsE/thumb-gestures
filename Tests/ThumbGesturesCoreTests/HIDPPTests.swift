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

    func testThumbEventReportsConnectionForAnyDeviceBeforeTheMouseIsFound() {
        // Before the mouse is found, the device index is 0.
        XCTAssertEqual(Report([0x10, 0x01, 0x41, 0x04, 0x02, 0x7A, 0x40]).thumbEvent(device: 0, reprogIndex: 0),
                       .linked(true))
        XCTAssertEqual(Report([0x10, 0x02, 0x41, 0x04, 0x42, 0x7A, 0x40]).thumbEvent(device: 0, reprogIndex: 0),
                       .linked(false))
    }

    func testThumbEventReportsConnectionOfTheMouse() {
        XCTAssertEqual(Report([0x10, 0x01, 0x41, 0x04, 0x42, 0x7A, 0x40]).thumbEvent(device: 1, reprogIndex: 10),
                       .linked(false))
    }

    func testThumbEventIgnoresConnectionOfAnotherDevice() {
        // For example a keyboard on the same receiver. It must not end the user's hold.
        XCTAssertNil(Report([0x10, 0x02, 0x41, 0x04, 0x42, 0x7A, 0x40]).thumbEvent(device: 1, reprogIndex: 10))
    }

    func testThumbEventOtherButtonIsRelease() {
        // Only the watched CID counts as pressed.
        XCTAssertEqual(Report(long([0x11, 0x01, 0x0A, 0x00, 0x00, 0x53])).thumbEvent(device: 1, reprogIndex: 10),
                       .button(pressed: false))
    }
}
