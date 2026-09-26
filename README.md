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

The direction is the same as a trackpad swipe with natural scrolling. The pointer stays in place during a hold. There are two switch modes, and you select one in the menu bar:

- **Quick Swipe:** after a short movement, one quick swipe switches one Space. One hold switches one Space.
- **Follow Hand:** the Space moves with your hand during the hold, as on a trackpad. On release, macOS completes the switch or goes back, from how far and how fast you moved.

## How it works

Thumb Gestures talks to the mouse through the Logitech HID++ protocol on the Unifying receiver, the same channel that Logi Options+ uses. It tells the mouse to send the thumb button presses and the movement during a hold to the app ("divert"). For a Space switch, the app sends the same swipe events that a trackpad sends. Thus a quick second switch interrupts the animation, as on a trackpad. For a click, it opens Mission Control.

The swipe events are undocumented macOS events (Mac Mouse Fix uses the same ones). A macOS update can change them.

The mouse forgets the divert when it sleeps or reconnects. The app turns on the receiver's connect notifications and sends the divert again after a reconnect, a wake from sleep, or a receiver plug-in. If a divert fails, the app tries again after 2, 5, 15, and then every 30 seconds. When the app stops, it gives the button back to the mouse.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)
- A Logitech MX Vertical on a Logitech Unifying receiver (USB ID `046d:c52b`). Bluetooth and Bolt receivers are not supported yet.

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

## Menu

Thumb Gestures has an icon in the menu bar. Its menu has:

- A status line: **Ready**, **Waiting for the mouse**, or **Paused**.
- **Quick Swipe** and **Follow Hand**: the switch mode.
- **Distance**: Short, Medium, or Long, for the selected mode. Each mode keeps its own choice.
- **Pause** / **Resume**: gives the button back to the mouse (it then changes the pointer speed), or takes it again.
- **Open Log**: opens the log in Console.
- **Quit Thumb Gestures**: gives the button back and stops the app until the next login.

A change applies at the next press of the thumb button. No restart is necessary.

| Distance | Quick Swipe: movement to switch | Follow Hand: movement for one full Space |
|---|---|---|
| Short | 400 counts (about 1 cm) | 1000 counts (about 2.5 cm) |
| Medium | 600 counts (about 1.5 cm) | 1500 counts (about 4 cm) |
| Long | 900 counts (about 2.3 cm) | 2200 counts (about 5.5 cm) |

The distances in cm are for 1000 DPI.

Advanced: in Follow Hand mode, `ExitSpeedFactor` changes how much a flick counts on release (default 1):

```bash
defaults write local.thumbgestures.ThumbGestures ExitSpeedFactor -float 1.5
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
- **The button does nothing while a menu is open.** macOS pauses the mouse events during a menu. Close the menu.
- **Do not run Logi Options+ at the same time.** It also takes control of the button.
- **The Space does not switch.** Make sure that you have more than one Space (a full-screen app is a Space).
- **It stopped after a reinstall.** Each build has a new ad-hoc signature, so macOS can drop the permission. Remove Thumb Gestures from the Accessibility settings and add it again. To prevent this, see [Keep the permission across rebuilds](#keep-the-permission-across-rebuilds).
- **The button does nothing after a crash.** The mouse still diverts the button. Turn the mouse off and on to give the button back.

## Keep the permission across rebuilds

`build.sh` signs with a code-signing certificate named `Local App Signing` if your login keychain has one. Otherwise it signs ad-hoc. With a certificate, macOS keeps the Accessibility permission when you rebuild. To create one (a self-signed certificate is enough, and it does not need to be trusted):

```bash
cat > /tmp/cert.cnf <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Local App Signing
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/key.pem -out /tmp/cert.pem -days 3650 -config /tmp/cert.cnf
openssl pkcs12 -export -legacy -inkey /tmp/key.pem -in /tmp/cert.pem -name "Local App Signing" -out /tmp/id.p12 -passout pass:temp
security import /tmp/id.p12 -k ~/Library/Keychains/login.keychain-db -P temp -T /usr/bin/codesign
rm /tmp/key.pem /tmp/id.p12 /tmp/cert.pem /tmp/cert.cnf
```

To use a different certificate, set `SIGN_IDENTITY` when you run `./install.sh`.

## Notes

- Tested with a Logitech MX Vertical on a Unifying receiver.
- Works next to [Scroll Split](https://github.com/EduardsE/scroll-split).

## License

[MIT](LICENSE)
