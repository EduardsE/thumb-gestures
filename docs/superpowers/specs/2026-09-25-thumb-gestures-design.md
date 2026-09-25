# Thumb Gestures — Design

Date: 2026-09-25
Status: Draft, waiting for review

## Purpose

The Logitech MX Vertical has a thumb button (the "DPI switch"). Without Logi Options+, macOS cannot assign an action to it, and the button sends no normal mouse button event. Thumb Gestures is a small background app that takes control of this button through the Logitech HID++ protocol and gives it these actions:

| Input | Action |
|---|---|
| Push and release the thumb button (no switch happened) | Open Mission Control |
| Hold the thumb button and move the mouse **left** | Switch to the Space on the **right** (⌃→) |
| Hold the thumb button and move the mouse **right** | Switch to the Space on the **left** (⌃←) |

The direction is the same as a trackpad swipe with natural scrolling: you push the current Space away.

## Decisions

- **Step switch, not a fluid gesture.** The app sends the official "Move left/right a space" shortcuts (⌃← / ⌃→). macOS shows its normal animation. No private gesture events.
- **One switch for each hold.** After the first switch, more movement does nothing until the release.
- **Separate app.** Scroll Split stays unchanged.
- **HID++ raw movement.** During a hold, the mouse sends its movement only to the app (raw XY divert). The pointer stays in place. No event tap for the movement.
- **Public repo** `EduardsE/thumb-gestures`, MIT license.

## Scope

In scope:

- An MX Vertical on a Logitech Unifying receiver (`046d:c52b`). This is the tested setup.
- The thumb button (CID `0xFD`) only.

Out of scope (the code must not block these later, but they are not built or tested now):

- Bluetooth direct connection (usage page `0xFF43`, device index `0xFF`).
- Bolt receivers.
- Other buttons, other mice, a settings window, fluid gestures.

## Facts from the spike (2026-09-25)

- The receiver exposes a HID++ interface: vendor `0x046D`, product `0xC52B`, primary usage page `0xFF00`.
- The mouse is at device index 1: "MX Vertical Advanced Ergonomic Mouse".
- REPROG_CONTROLS_V4 (feature `0x1B04`) is at feature index 10 on this mouse. The code must look it up and not hard-code it.
- CID `0xFD`: flags `0x71` (reprogrammable, divertable, persistently divertable), additional flags `0x05` (bit 0 = raw XY supported).
- Divert with flags `0x03` works: the mouse sends "pressed [0xFD]" and "released []" events, and undivert with `0x02` gives the button back.
- The raw XY mode is **not tested yet**. It is the first implementation step.

## HID++ protocol details

All requests use the long report:

```
[0x11, deviceIndex, featureIndex, (function << 4) | swID, params... ] padded to 20 bytes
```

- `swID` = `0x0A`. A response has the same first four bytes.
- An error response has byte 2 = `0xFF` (HID++ 2.0) or `0x8F` (HID++ 1.0).
- The IOKit call is `IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, bytes, 20)`. The buffer includes the report ID.

Requests:

| Request | Feature index | Function | Params | Response |
|---|---|---|---|---|
| Root.getFeature | `0x00` | 0 | featureID (2 bytes, big-endian) | byte 4 = feature index (0 = not present) |
| Reprog.setCidReporting | reprog | 3 | CID (2 bytes), flags (1), remap CID (2 bytes, 0) | echo |

`setCidReporting` flags:

| Bit | Name | Value |
|---|---|---|
| 0 | divert | 0x01 |
| 1 | divert valid | 0x02 |
| 4 | raw XY | 0x10 |
| 5 | raw XY valid | 0x20 |

- Divert with raw XY: `0x33`.
- Undivert: `0x22`.

Notifications from the mouse (swID nibble = 0):

| Notification | Bytes | Meaning |
|---|---|---|
| Diverted buttons | `[0x11, idx, reprog, 0x00, cid1(2), cid2(2), cid3(2), cid4(2) ...]` | CIDs that are pressed now. All zero = released. |
| Diverted raw XY | `[0x11, idx, reprog, 0x10, dx(2), dy(2) ...]` | Signed 16-bit, big-endian. |
| Device connection (HID++ 1.0, from the receiver) | `[0x10, idx, 0x41, x, flags, ...]` | Bit 6 (`0x40`) of byte 4 set = link not established. Clear = the mouse connected. |

## Architecture

A Swift package with a library target (logic without I/O), an executable target, and a test target.

| File | Target | Job | Depends on |
|---|---|---|---|
| `HIDPP.swift` | Core (library) | Make request bytes. Decode reports into `enum Report { buttons([UInt16]), rawXY(dx: Int, dy: Int), connected(Bool), response(...), error }`. | Nothing |
| `Gesture.swift` | Core (library) | State machine. Input: `press`, `move(dx)`, `release`. Output: `Action?` (`.missionControl`, `.spaceLeft`, `.spaceRight`). | Nothing |
| `Receiver.swift` | App | IOHIDManager: find the `0xFF00` interface, send requests and wait for the response, deliver notifications, report plug and unplug. | Core |
| `Actions.swift` | App | Post ⌃← / ⌃→ as CGEvents. Open `/System/Applications/Mission Control.app`. | AppKit, CoreGraphics |
| `main.swift` | App | Single-instance lock, Accessibility check, wiring, the divert/undivert life cycle, signals, the run loop. | All |

### Gesture state machine

```
idle --press--> held(total = 0, switched = false)
held --move(dx)--> total += dx
                   if !switched and |total| >= distance:
                       switched = true
                       emit total < 0 ? .spaceRight : .spaceLeft
held --release--> idle; emit switched ? nil : .missionControl
idle --move/release--> ignore
```

- Only `dx` counts. `dy` is ignored.
- `distance` is in mouse counts. The default is 600 (about 1.5 cm at 1000 DPI). It comes from `defaults read local.thumbgestures.ThumbGestures SwitchDistance`. The final default is tuned in the manual test.
- A "buttons" notification that contains `0xFD` is `press`. One that does not contain `0xFD` while in `held` is `release`.

### Life cycle of the divert

The app sends "divert `0xFD` with `0x33`" at these times:

1. At start, after it finds the mouse.
2. When the receiver reports that the mouse connected (device connection notification).
3. When macOS wakes from sleep (`NSWorkspace.didWakeNotification`), after a delay of 2 s.
4. When IOHIDManager reports a new receiver (plugged in again).

At each divert, the app looks up the device index and the feature index again, because they can change. The app also resets the gesture state to `idle`, so a lost "released" event cannot leave the state in `held`.

On SIGTERM and SIGINT, the app sends "undivert `0xFD` with `0x22`" and then exits with code 0.

## Error handling

| Condition | Behavior |
|---|---|
| No receiver | Log it. Wait for the plug-in callback. Do not exit. |
| The mouse does not answer (asleep or off) | The request times out after 1.5 s. Log it. The next connection notification sends the divert again. |
| The feature or the CID is not present | Log it and wait. |
| No Accessibility permission | Log it. Show the system prompt only on the first start. Exit with code 1, so launchd starts it again after 10 s. The same as Scroll Split. |
| The HID++ interface needs Input Monitoring | Find out in step 1. If yes, add a check and a README note the same as for Accessibility. |
| A second copy starts | The `flock` lock fails. Exit with code 0. |

## Install and packaging

The same as Scroll Split:

- `build.sh`: `swift build -c release`. It makes `build/Thumb Gestures.app` with `Info.plist`, an icon made by `tools/make-icon.swift`, and an ad-hoc signature.
- `install.sh`: copies the app to `/Applications` and writes the LaunchAgent `~/Library/LaunchAgents/local.thumbgestures.ThumbGestures.plist`. The LaunchAgent has `RunAtLoad`, `KeepAlive SuccessfulExit=false`, `ThrottleInterval 10`, and `AssociatedBundleIdentifiers`. The log is `~/Library/Logs/ThumbGestures.log`.
- `uninstall.sh`: removes the LaunchAgent and the app.
- Bundle ID `local.thumbgestures.ThumbGestures`. `LSUIElement` = true. macOS 13 or later.
- README with the use case, install steps, permissions, the `SwitchDistance` option, and troubleshooting. MIT license.

## Tests

Unit tests (`swift test`):

- `HIDPP`:
  - The getFeature request bytes and the setCidReporting request bytes (`0x33` and `0x22`).
  - Decode a buttons notification with `0xFD` and an empty one.
  - Decode a raw XY notification with negative and positive values.
  - Decode a connection notification with the link bit set and clear.
  - Decode an error response.
- `Gesture`:
  - A press and a release give `.missionControl`.
  - A press, a move of −600, and a release give `.spaceRight` once and nothing on the release.
  - A press and a move of +600 give `.spaceLeft`.
  - Many moves in one hold give a maximum of one switch.
  - Small moves that add up to the distance give a switch.
  - A move below the distance and a release give `.missionControl`.
  - Moves and releases in `idle` give nothing.

Manual tests with the mouse:

1. Raw XY spike: divert with `0x33`, hold, and move. The pointer stays in place and the log shows `dx, dy`.
2. A click opens Mission Control.
3. A hold and a move left switches to the Space on the right. The opposite direction also works.
4. One hold gives only one switch.
5. After sleep and wake, the button still works.
6. After the mouse turns off and on, the button still works.
7. After `launchctl bootout`, the thumb button has its usual function again.

## Acceptance criteria

- All unit tests pass.
- All manual tests pass on the MX Vertical with the Unifying receiver.
- Scroll Split still works at the same time.
- The public repo `EduardsE/thumb-gestures` has the code, the README, and the license.

## Changes after implementation (2026-09-25)

- **Live swipe instead of shortcuts.** macOS ignores ⌃← / ⌃→ during the Space animation, so a quick second switch was lost. A spike showed that the undocumented "dock swipe" event pair (the events a trackpad sends; field numbers as in Mac Mouse Fix) switches Spaces, and that a second swipe 0.15 s later interrupts the animation. The app now posts one quick swipe (20 steps, 8 ms apart, exit speed 3; offset +1 = the Space on the right) for each switch. The gesture logic (distance, one switch for each hold) did not change. This replaces the "no private gesture events" decision, at the user's request.
- **Recovery.** A failed divert is retried after 2, 5, 15, and then every 30 s. The last working indices stay until a divert succeeds. The app turns on the receiver's wireless notifications (HID++ 1.0 register 0x00, flag 0x000100), because without them the receiver sends no 0x41 connection notification. `DivertCoordinator` makes sure that diverts never nest, and that a stop signal during a divert waits for it to end and then gives the button back.
- **Single instance.** A second copy waits for the lock instead of exiting with code 0, because launchd does not restart the app after a clean exit.
- **Signing.** `build.sh` signs with a local certificate `Local App Signing` if one exists, so the Accessibility permission survives rebuilds.
- **Next:** try C2, a swipe that follows the hand during a hold, as a separate change.
