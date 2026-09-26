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
    perform(controller.cancel())
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
    perform(controller.cancel())
    undivert()
    exit(0)
}

/// Does the controller's outputs.
func perform(_ outputs: [ThumbOutput]) {
    for output in outputs {
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
    perform(controller.handle(event, now: ProcessInfo.processInfo.systemUptime))
}
receiver.onAttach = {
    log("Receiver found.")
    scheduleDivert(after: 0.5)
}
receiver.onDetach = {
    log("Receiver removed.")
    deviceIndex = 0
    perform(controller.cancel())
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
