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

var gesture = Gesture(distance: Preferences(defaults: UserDefaults.standard.dictionaryRepresentation()).switchDistance)
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
    gesture.reset()
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
            return true
        }
    }
    return false
}

/// Runs a divert now, unless one is running already. Then does what the coordinator says.
func divert() {
    guard coordinator.begin() else { return }
    switch coordinator.end(success: divertOnce()) {
    case .idle:
        break
    case .runAgain:
        scheduleDivert(after: 0.5)
    case .retry(let delay):
        if coordinator.failures == 1 { log("No mouse answered. Trying again in the background.") }
        scheduleDivert(after: delay)
    case .quit:
        undivertAndExit()
    }
}

/// Diverts after a delay. A new request replaces a waiting one.
func scheduleDivert(after delay: TimeInterval) {
    divertTimer?.cancel()
    let work = DispatchWorkItem { divert() }
    divertTimer = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
}

/// Gives the thumb button back to the mouse and exits.
func undivertAndExit() -> Never {
    if deviceIndex != 0 {
        _ = receiver.send(HIDPP.setCidReporting(device: deviceIndex, reprogIndex: reprogIndex,
                                                cid: HIDPP.thumbButton, flags: HIDPP.undivert))
        log("Thumb button given back to the mouse.")
    }
    exit(0)
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
log("Thumb Gestures is running (switch distance \(gesture.distance)). Waiting for the receiver.")
CFRunLoopRun()
