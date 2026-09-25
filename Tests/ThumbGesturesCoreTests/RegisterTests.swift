import XCTest
@testable import ThumbGesturesCore

final class RegisterTests: XCTestCase {
    func testReadNotificationsRequestBytes() {
        XCTAssertEqual(HIDPP.readRegister(device: 0xFF, address: HIDPP.notificationsRegister),
                       [0x10, 0xFF, 0x81, 0x00, 0x00, 0x00, 0x00])
    }

    func testWriteNotificationsRequestBytes() {
        XCTAssertEqual(HIDPP.writeRegister(device: 0xFF, address: 0x00, params: [0x00, 0x01, 0x00]),
                       [0x10, 0xFF, 0x80, 0x00, 0x00, 0x01, 0x00])
    }

    func testWirelessNotificationsFlagIsAddedAndOtherBitsKept() {
        XCTAssertEqual(HIDPP.withWirelessNotifications([0x00, 0x00, 0x00]), [0x00, 0x01, 0x00])
        XCTAssertEqual(HIDPP.withWirelessNotifications([0x10, 0x08, 0x02]), [0x10, 0x09, 0x02])
        XCTAssertEqual(HIDPP.withWirelessNotifications([0x00, 0x01, 0x00]), [0x00, 0x01, 0x00])
    }

    func testDecodeRegisterReply() {
        XCTAssertEqual(Report([0x10, 0xFF, 0x81, 0x00, 0x00, 0x01, 0x00]),
                       .register(device: 0xFF, subID: 0x81, address: 0x00, params: [0x00, 0x01, 0x00]))
    }

    func testRegisterReplyAndErrorMatchTheRequest() {
        let read = HIDPP.readRegister(device: 0xFF, address: 0x00)
        XCTAssertTrue(HIDPP.isReply(Report([0x10, 0xFF, 0x81, 0x00, 0x00, 0x00, 0x00]), to: read))
        XCTAssertTrue(HIDPP.isReply(Report([0x10, 0xFF, 0x8F, 0x81, 0x00, 0x02, 0x00]), to: read))
        XCTAssertFalse(HIDPP.isReply(Report([0x10, 0xFF, 0x80, 0x00, 0x00, 0x00, 0x00]), to: read))
        XCTAssertFalse(HIDPP.isReply(Report([0x10, 0x01, 0x81, 0x00, 0x00, 0x00, 0x00]), to: read))
    }

    func testRegisterReplyIsNotAThumbEvent() {
        XCTAssertNil(Report([0x10, 0xFF, 0x81, 0x00, 0x00, 0x01, 0x00]).thumbEvent(device: 1, reprogIndex: 10))
    }
}
