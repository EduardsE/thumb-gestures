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
