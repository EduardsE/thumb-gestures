import AppKit
import ThumbGesturesCore

/// The menu bar icon and its menu. It shows the state and calls back on each choice.
final class StatusMenu: NSObject {
    enum Status {
        case ready
        case waiting
        case paused
    }

    var onSelectMode: ((Mode) -> Void)?
    var onSelectPreset: ((Preset) -> Void)?
    var onPause: (() -> Void)?
    var onOpenLog: (() -> Void)?
    var onQuit: (() -> Void)?

    var status: Status = .waiting { didSet { update() } }
    var preferences = Preferences() { didSet { update() } }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var modeItems: [NSMenuItem] = []
    private var presetItems: [NSMenuItem] = []
    private let pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        for (mode, title) in [(Mode.quickSwipe, "Quick Swipe"), (.followHand, "Follow Hand")] {
            let modeItem = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
            modeItem.target = self
            modeItem.representedObject = mode.rawValue
            menu.addItem(modeItem)
            modeItems.append(modeItem)
        }
        menu.addItem(.separator())

        let distance = NSMenuItem(title: "Distance", action: nil, keyEquivalent: "")
        let distanceMenu = NSMenu()
        distanceMenu.autoenablesItems = false
        for (preset, title) in [(Preset.short, "Short"), (.medium, "Medium"), (.long, "Long")] {
            let presetItem = NSMenuItem(title: title, action: #selector(selectPreset(_:)), keyEquivalent: "")
            presetItem.target = self
            presetItem.representedObject = preset.rawValue
            distanceMenu.addItem(presetItem)
            presetItems.append(presetItem)
        }
        distance.submenu = distanceMenu
        menu.addItem(distance)
        menu.addItem(.separator())

        pauseItem.action = #selector(pause)
        pauseItem.target = self
        menu.addItem(pauseItem)
        let logItem = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Thumb Gestures", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        update()
    }

    private func update() {
        switch status {
        case .ready:
            statusLine.title = "Ready"
            setIcon("arrow.left.and.right", dimmed: false)
        case .waiting:
            statusLine.title = "Waiting for the mouse"
            setIcon("exclamationmark.triangle", dimmed: false)
        case .paused:
            statusLine.title = "Paused"
            setIcon("arrow.left.and.right", dimmed: true)
        }
        pauseItem.title = status == .paused ? "Resume" : "Pause"
        for modeItem in modeItems {
            modeItem.state = modeItem.representedObject as? String == preferences.mode.rawValue ? .on : .off
        }
        for presetItem in presetItems {
            presetItem.state = presetItem.representedObject as? String == preferences.preset.rawValue ? .on : .off
        }
    }

    private func setIcon(_ symbol: String, dimmed: Bool) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Thumb Gestures")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.appearsDisabled = dimmed
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = Mode(rawValue: raw) else { return }
        onSelectMode?(mode)
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = Preset(rawValue: raw) else { return }
        onSelectPreset?(preset)
    }

    @objc private func pause() { onPause?() }
    @objc private func openLog() { onOpenLog?() }
    @objc private func quit() { onQuit?() }
}
