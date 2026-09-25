# Thumb Gestures Settings Menu — Design

Date: 2026-09-25
Status: Draft, waiting for review
Builds on: `2026-09-25-thumb-gestures-design.md` and the C2 spike (branch `spike/follow-hand`)

## Purpose

Thumb Gestures now has two ways to switch Spaces, and the user wants to keep both:

- **Quick swipe (C1):** after a distance, one quick live swipe (the current `main` behavior).
- **Follow hand (C2):** during a hold, the Space follows the hand, and macOS completes or cancels on release (the spike).

Today the only way to change settings is `defaults write` and a restart. This change adds a menu bar menu to select the mode and the distance, to pause, to open the log, and to quit. Changes apply without a restart.

## Decisions

- **Menu bar icon with a menu** (AppKit `NSStatusItem`), in the same process. No settings window, no SwiftUI.
- **Three distance presets for each mode.** Each mode keeps its own preset.
- **Exit speed stays hidden** (`ExitSpeedFactor`, default 1).
- **Old keys are removed:** `SwitchDistance`, `FollowScale`, `FollowHand`. The menu is the only way to set mode and distance.
- **The C2 spike code is not kept.** `FollowGesture` is written again with TDD in the core.
- **Default mode:** Quick swipe, Medium.

## The menu

```
[icon]
   Ready                          (disabled status line)
 ─────────────
 ✓ Quick Swipe
   Follow Hand
 ─────────────
   Distance              ▸  Short / ✓ Medium / Long
 ─────────────
   Pause                          (Resume while paused)
   Open Log
 ─────────────
   Quit Thumb Gestures
```

- **Status line** (disabled item): `Ready`, `Waiting for the mouse`, or `Paused`.
- **Mode items:** a checkmark on the selected mode. A change applies at the next press of the thumb button, never during a hold.
- **Distance submenu:** the presets of the selected mode, with a checkmark on its current preset. A change applies at the next press.
- **Pause:** gives the button back to the mouse (undivert). The item then shows `Resume`. Resume diverts the button again. Pause is not saved; a restart is not paused.
- **Open Log:** opens `~/Library/Logs/ThumbGestures.log` in Console (`/System/Applications/Utilities/Console.app`).
- **Quit Thumb Gestures:** the same path as SIGTERM: undivert, then exit with code 0. launchd does not restart the app until the next login.
- **Icon** (template SF Symbol, so it follows the menu bar color):
  - Ready: `arrow.left.and.right`
  - Waiting for the mouse: `exclamationmark.triangle`
  - Paused: `arrow.left.and.right` with `appearsDisabled = true`

## Presets

| Preset | Quick swipe: switch distance (counts) | Follow hand: counts for one Space |
|---|---|---|
| Short | 400 | 1000 |
| Medium | 600 | 1500 |
| Long | 900 | 2200 |

## Stored settings

Domain `local.thumbgestures.ThumbGestures`:

| Key | Type | Values | Default |
|---|---|---|---|
| `Mode` | String | `quickSwipe`, `followHand` | `quickSwipe` |
| `QuickSwipeDistance` | String | `short`, `medium`, `long` | `medium` |
| `FollowHandDistance` | String | `short`, `medium`, `long` | `medium` |
| `ExitSpeedFactor` | Number | > 0 | 1 |

A missing or bad value gives the default. The menu writes the three string keys. `ExitSpeedFactor` has no menu item.

## Follow hand behavior (from the spike, now specified)

- A hold starts with `total = 0`. Each `move(dx)` adds `dx` to `total`.
- **Dead zone:** 30 counts. While `|total| <= 30`, nothing is sent. When `|total| > 30`, send `began` (offset 0) and then `changed`.
- **Offset:** `-total / scale`. Moving left gives a positive offset, which brings in the Space on the right. `scale` = the preset value.
- **Changed:** one `changed` frame for each `move` after the swipe starts.
- **Exit speed:** from the offset samples of the last 0.1 s: `(lastOffset - firstOffset) / (lastTime - firstTime) × ExitSpeedFactor`. 0 if there are fewer than 2 samples, or if no time passed.
- **Release:** if a swipe started, send `ended` with the current offset and the exit speed. If no swipe started, the release is a click: Mission Control.
- **Repeated press** during a hold: ignored (the hold continues).
- **Link change** (connect or disconnect) during a hold: if a swipe started, send `ended` with the current offset and exit speed 0. Then reset.

## Architecture

### Core (`ThumbGesturesCore`, no I/O, unit tests)

| File | Change | Interface |
|---|---|---|
| `Preferences.swift` | New. Replaces `Settings` in `Gesture.swift`. | `enum Mode: String, CaseIterable { quickSwipe, followHand }`; `enum Preset: String, CaseIterable { short, medium, long }`; `struct Preferences: Equatable { mode, quickPreset, followPreset; init(); init(defaults: [String: Any]); var defaultsValues: [String: String]; var switchDistance: Int; var followScale: Double; static func exitSpeedFactor(_ value: Any?) -> Double }` |
| `FollowGesture.swift` | New (TDD). | `struct FollowGesture { init(scale: Double, exitFactor: Double); mutating func handle(_ event: ThumbEvent, now: Double) -> [FollowOutput]; mutating func reset() }`; `enum FollowOutput: Equatable { case frame(SwipeFrame), missionControl }` |
| `ThumbController.swift` | New. | `enum ThumbOutput: Equatable { case missionControl, quickSwipe(GestureAction), frame(SwipeFrame) }`; `struct ThumbController { init(preferences: Preferences, exitFactor: Double); private(set) var preferences; mutating func apply(_ preferences: Preferences); mutating func handle(_ event: ThumbEvent, now: Double) -> [ThumbOutput]; mutating func reset() }` |
| `DivertCoordinator` | Add pause. | `private(set) var isPaused`; `mutating func setPaused(_ paused: Bool)`; new `Next` case `.undivert`. While paused, `begin()` returns false and does not remember a trigger. A divert that was running when the pause started ends with `.undivert` if it succeeded, and `.idle` if it failed (quit still wins). |
| `DockSwipe.swift` | `SwipeFrame` gets a public `init`. | |
| `Gesture.swift` | Remove `Settings`. `Gesture` is unchanged. | |

`ThumbController` rules:

- `apply` stores the new preferences. They take effect at the next `button(pressed: true)` when no hold is active. If no hold is active, they take effect at once.
- Quick swipe mode: events go to `Gesture(distance: preferences.switchDistance)`. `.missionControl` → `.missionControl`. `.spaceLeft`/`.spaceRight` → `.quickSwipe(action)`.
- Follow hand mode: events go to `FollowGesture(scale: preferences.followScale, exitFactor:)`. Outputs map one to one.
- `reset` resets both gestures.

### App (`ThumbGestures`)

| File | Change |
|---|---|
| `StatusMenu.swift` | New. Owns the `NSStatusItem` and the menu. Rebuilds the check marks and the status line when the state changes. Calls closures for: select mode, select preset, pause/resume, open log, quit. |
| `main.swift` | `NSApplication.shared` with `setActivationPolicy(.accessory)`; `NSApp.run()` replaces `CFRunLoopRun()`. Reads `Preferences(defaults:)` at start. Sends events to `ThumbController` and does the outputs. Menu actions update `Preferences`, write `defaultsValues` to `UserDefaults`, and call `controller.apply`. Pause: `coordinator.setPaused(true)`, cancel a waiting divert, undivert. Resume: `setPaused(false)`, schedule a divert at 0.1 s. Quit: the SIGTERM path. Status: `Ready` after a successful divert, `Waiting for the mouse` after a failed divert or a receiver removal, `Paused` during pause. |
| `Actions.swift` | `post(_ frame:)` becomes internal. `perform(.spaceLeft/.spaceRight)` is unchanged (quick swipe). |
| `FollowGesture.swift` (spike, app target) | Removed. |
| `install.sh` | After `launchctl bootout`, wait until `launchctl print gui/$(id -u)/$LABEL` fails, for a maximum of 5 s, before `bootstrap`. |

### Data flow

1. HID report → `Report` → `ThumbEvent` (unchanged).
2. `ThumbController.handle(event, now: systemUptime)` → `[ThumbOutput]`.
3. `.missionControl` → `Actions.perform(.missionControl)`; `.quickSwipe(a)` → `Actions.perform(a)`; `.frame(f)` → `Actions.post(f)`.
4. Menu → `Preferences` → `UserDefaults` + `controller.apply`.

## Error handling

| Condition | Behavior |
|---|---|
| No mouse diverted | Icon `exclamationmark.triangle`, status `Waiting for the mouse`. Retries as today. |
| Pause during a divert | The running divert finishes. Its `end` returns `.undivert` (success) or `.idle` (failure), so the button is not left diverted. A trigger during pause does not divert. |
| Quit or SIGTERM during a divert | As today: the divert ends, then undivert and exit. |
| A menu is open | macOS pauses HID callbacks in the default run-loop mode. The button works again when the menu closes. |
| Mode or preset change during a hold | Applies at the next press. |
| Bad stored values | Defaults (Quick swipe, Medium, Medium, factor 1). |

## Tests

Unit tests:

- `Preferences`: defaults; every mode and preset round-trips through `defaultsValues`; bad strings and wrong types fall back; the preset table values; `exitSpeedFactor` with nil, 0, negative, text, and 2.5.
- `FollowGesture`: a click gives `.missionControl`; a move inside the dead zone and a release gives `.missionControl`; a move past the dead zone gives `began` then `changed`; the offset sign (left → positive); `changed` for each later move; release gives `ended` with the exit speed from the last 0.1 s; old samples are dropped; exit speed 0 with one sample; a repeated press keeps the hold; a link change during a swipe gives `ended` with exit speed 0 and resets; a link change without a swipe gives nothing.
- `ThumbController`: quick swipe outputs; follow hand outputs; `apply` during a hold changes nothing until the next press; `apply` when idle takes effect at once; the preset distance is used.
- `DivertCoordinator`: `begin` returns false while paused; a trigger during pause is not remembered; after `setPaused(false)`, `begin` returns true; a pause during a successful divert gives `.undivert`, during a failed one `.idle`; a quit during a paused divert gives `.quit`.

Manual tests with the mouse:

1. The icon and the status line show `Ready`.
2. Quick Swipe and Follow Hand both work, and a change applies without a restart.
3. Each distance preset changes the feel in both modes.
4. Pause: the thumb button changes the pointer speed (normal mouse function). Resume: the gestures work again.
5. Open Log opens Console with the log.
6. Quit: the log shows `Thumb button given back to the mouse`, and the icon goes away.
7. Mouse off and on while paused: the app does not divert.
8. `./install.sh` twice in a row succeeds.

## Acceptance criteria

- All unit tests pass.
- All manual tests pass.
- README describes the menu, the modes, and the presets; the old `defaults` keys are removed from it.
- `main` gets the change after the tests pass; the `spike/follow-hand` branch can then be deleted.
