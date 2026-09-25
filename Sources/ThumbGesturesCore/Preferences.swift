// The user settings: the switch mode and a distance preset for each mode.
// The menu writes them to the defaults domain. This file does no I/O.

import Foundation

public enum Mode: String, CaseIterable {
    case quickSwipe
    case followHand
}

public enum Preset: String, CaseIterable {
    case short
    case medium
    case long
}

public struct Preferences: Equatable {
    public static let modeKey = "Mode"
    public static let quickSwipeDistanceKey = "QuickSwipeDistance"
    public static let followHandDistanceKey = "FollowHandDistance"
    public static let exitSpeedFactorKey = "ExitSpeedFactor"

    public var mode: Mode = .quickSwipe
    public var quickPreset: Preset = .medium
    public var followPreset: Preset = .medium

    public init() {}

    /// Reads the stored values. A missing or bad value gives the default.
    public init(defaults: [String: Any]) {
        mode = (defaults[Self.modeKey] as? String).flatMap(Mode.init(rawValue:)) ?? .quickSwipe
        quickPreset = (defaults[Self.quickSwipeDistanceKey] as? String).flatMap(Preset.init(rawValue:)) ?? .medium
        followPreset = (defaults[Self.followHandDistanceKey] as? String).flatMap(Preset.init(rawValue:)) ?? .medium
    }

    public var defaultsValues: [String: String] {
        [Self.modeKey: mode.rawValue,
         Self.quickSwipeDistanceKey: quickPreset.rawValue,
         Self.followHandDistanceKey: followPreset.rawValue]
    }

    /// The preset of the selected mode.
    public var preset: Preset {
        get { mode == .quickSwipe ? quickPreset : followPreset }
        set {
            if mode == .quickSwipe { quickPreset = newValue } else { followPreset = newValue }
        }
    }

    /// Quick swipe: horizontal movement, in mouse counts, that starts a switch.
    public var switchDistance: Int {
        switch quickPreset {
        case .short: return 400
        case .medium: return 600
        case .long: return 900
        }
    }

    /// Follow hand: mouse counts for one full Space.
    public var followScale: Double {
        switch followPreset {
        case .short: return 1000
        case .medium: return 1500
        case .long: return 2200
        }
    }

    /// The hidden ExitSpeedFactor setting, or 1 if it is missing or not a positive number.
    public static func exitSpeedFactor(_ value: Any?) -> Double {
        if let number = value as? NSNumber, number.doubleValue > 0 { return number.doubleValue }
        return 1
    }
}
