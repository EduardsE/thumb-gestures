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
