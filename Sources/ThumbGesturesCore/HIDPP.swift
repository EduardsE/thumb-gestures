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

    /// The receiver itself, for HID++ 1.0 register requests.
    public static let receiverIndex: UInt8 = 0xFF
    /// Receiver register with the notification flags.
    public static let notificationsRegister: UInt8 = 0x00

    /// HID++ 1.0 register read (short report).
    public static func readRegister(device: UInt8, address: UInt8) -> [UInt8] {
        [shortReportID, device, 0x81, address, 0, 0, 0]
    }

    /// HID++ 1.0 register write (short report, 3 param bytes).
    public static func writeRegister(device: UInt8, address: UInt8, params: [UInt8]) -> [UInt8] {
        let padded = Array((params + [0, 0, 0]).prefix(3))
        return [shortReportID, device, 0x80, address] + padded
    }

    /// The notifications register value with the "wireless notifications" flag (0x000100) set.
    /// Without it, the receiver does not report when the mouse connects.
    public static func withWirelessNotifications(_ params: [UInt8]) -> [UInt8] {
        var flags = Array((params + [0, 0, 0]).prefix(3))
        flags[1] |= 0x01
        return flags
    }

    /// True if the report is the response or the error for this request.
    public static func isReply(_ report: Report, to request: [UInt8]) -> Bool {
        switch report {
        case let .response(device, feature, fnsw, _), let .error(device, feature, fnsw, _),
             let .register(device, feature, fnsw, _):
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
    /// The reply to a HID++ 1.0 register read (0x81) or write (0x80).
    case register(device: UInt8, subID: UInt8, address: UInt8, params: [UInt8])
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
        if r[0] == HIDPP.shortReportID && (r[2] == 0x80 || r[2] == 0x81) {
            self = .register(device: device, subID: r[2], address: r[3], params: Array(r[4..<7]))
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
    /// Before the mouse is found (device 0), a connection of any device counts, so a divert can start.
    /// After that, only the mouse's own connection counts, so another device cannot end a hold.
    public func thumbEvent(device: UInt8, reprogIndex: UInt8, cid: UInt16 = HIDPP.thumbButton) -> ThumbEvent? {
        switch self {
        case let .buttons(d, f, cids) where d == device && f == reprogIndex:
            return .button(pressed: cids.contains(cid))
        case let .rawXY(d, f, dx, _) where d == device && f == reprogIndex:
            return .move(dx: dx)
        case let .connection(d, linked) where device == 0 || d == device:
            return .linked(linked)
        default:
            return nil
        }
    }
}
