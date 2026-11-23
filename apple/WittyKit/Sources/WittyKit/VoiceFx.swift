// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Karaoke's Voice settings, as the website's web/src/audio/voiceFx.ts (WittyMediaServer #524, #518): what can be done
// to the singer's part and to the music under it once a song is in separate parts. The rules only: the controls, their
// ranges, the nine presets, what's kept and how it reads back. The app's StemPlayer turns them into audio units.

/// One control of Voice settings.
public struct FxControl: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let min: Double
    public let max: Double
    public let step: Double
    public let unit: String
    public let help: String
}

/// A group of controls, as Advanced lists them.
public struct FxGroup: Equatable, Sendable, Identifiable {
    public let title: String
    public let controls: [FxControl]
    public var id: String { title }
}

/// A preset: As recorded, or one of nine kinds of voice.
public struct VoicePreset: Equatable, Sendable, Identifiable {
    public let id: String
    /// `female`, `mid` or `low`; empty for As recorded.
    public let range: String
    /// `high`, `medium` or `low`; empty for As recorded.
    public let level: String
    public let name: String
    public let values: [String: Double]
}

/// Every control's value by its id. Off is each one's default, so a song sounds as it was made.
public struct VoiceFx: Codable, Equatable, Sendable {
    public private(set) var values: [String: Double]

    public init(_ values: [String: Double] = [:]) {
        var out = VoiceFx.offValues
        for control in VoiceFx.controls {
            if let v = values[control.id], v.isFinite { out[control.id] = Swift.min(control.max, Swift.max(control.min, v)) }
        }
        self.values = out
    }

    public subscript(_ id: String) -> Double { values[id] ?? VoiceFx.offValues[id] ?? 0 }

    /// The same, with one control moved (kept within its range).
    public func with(_ id: String, _ value: Double) -> VoiceFx {
        var next = values
        next[id] = value
        return VoiceFx(next)
    }

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode([String: Double].self)) ?? [:]
        self.init(raw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }

    public static let groups: [FxGroup] = [
        FxGroup(title: "Voice tone", controls: [
            FxControl(id: "lowCut", label: "Low cut", min: 20, max: 400, step: 10, unit: "Hz", help: "Takes out rumble and breath below this"),
            FxControl(id: "bass", label: "Warmth", min: -12, max: 12, step: 1, unit: "dB", help: "The low end of the voice"),
            FxControl(id: "presence", label: "Presence", min: -12, max: 12, step: 1, unit: "dB", help: "Brings the words forward"),
            FxControl(id: "air", label: "Air", min: -12, max: 12, step: 1, unit: "dB", help: "Brightness and breath on top"),
        ]),
        FxGroup(title: "Voice dynamics and place", controls: [
            FxControl(id: "compress", label: "Compression", min: 0, max: 100, step: 5, unit: "%", help: "Evens out loud and quiet lines"),
            FxControl(id: "pan", label: "Pan", min: -100, max: 100, step: 5, unit: "", help: "Left or right of centre"),
            FxControl(id: "double", label: "Doubling", min: 0, max: 100, step: 5, unit: "%", help: "A second, slightly late voice, for a fuller sound"),
        ]),
        FxGroup(title: "Voice echo and reverb", controls: [
            FxControl(id: "echo", label: "Echo", min: 0, max: 100, step: 5, unit: "%", help: "How loud the echo is"),
            FxControl(id: "echoTime", label: "Echo time", min: 60, max: 900, step: 20, unit: "ms", help: "How long before it comes back"),
            FxControl(id: "echoRepeats", label: "Echo repeats", min: 0, max: 80, step: 5, unit: "%", help: "How much each echo echoes again"),
            FxControl(id: "reverb", label: "Reverb", min: 0, max: 100, step: 5, unit: "%", help: "The sound of a room"),
            FxControl(id: "room", label: "Room size", min: 0.3, max: 5, step: 0.1, unit: "s", help: "From a small room to a hall"),
        ]),
        FxGroup(title: "Background Music", controls: [
            FxControl(id: "musicBass", label: "Bass", min: -12, max: 12, step: 1, unit: "dB", help: "The low end of the music"),
            FxControl(id: "musicTreble", label: "Treble", min: -12, max: 12, step: 1, unit: "dB", help: "The top of the music"),
            FxControl(id: "pocket", label: "Room for the voice", min: 0, max: 12, step: 1, unit: "dB", help: "Dips the music where voices sit, so the voice comes through"),
        ]),
    ]

    public static let controls: [FxControl] = groups.flatMap(\.controls)

    public static let offValues: [String: Double] = [
        "lowCut": 20, "bass": 0, "presence": 0, "air": 0, "compress": 0, "pan": 0, "double": 0,
        "echo": 0, "echoTime": 320, "echoRepeats": 30, "reverb": 0, "room": 1.6,
        "musicBass": 0, "musicTreble": 0, "pocket": 0,
    ]

    public static let off = VoiceFx()

    public static let ranges: [(id: String, name: String)] = [("female", "Female vocal"), ("mid", "Mid-range vocal"), ("low", "Low vocal")]
    public static let levels: [(id: String, name: String)] = [("high", "High"), ("medium", "Medium"), ("low", "Low")]

    /// The nine voices, as the website tunes them (voiceFx.ts says why each is shaped so).
    public static let voicePresets: [VoicePreset] = [
        VoicePreset(id: "female-high", range: "female", level: "high", name: "Female vocal, high",
                    values: ["lowCut": 180, "bass": -2, "presence": 2, "air": 4, "compress": 35, "double": 10, "reverb": 16, "room": 1.4, "pocket": 3]),
        VoicePreset(id: "female-medium", range: "female", level: "medium", name: "Female vocal, medium",
                    values: ["lowCut": 150, "bass": -1, "presence": 3, "air": 3, "compress": 40, "double": 10, "reverb": 14, "room": 1.3, "pocket": 3]),
        VoicePreset(id: "female-low", range: "female", level: "low", name: "Female vocal, low",
                    values: ["lowCut": 120, "bass": 1, "presence": 4, "air": 2, "compress": 45, "double": 8, "reverb": 12, "room": 1.2, "pocket": 3]),
        VoicePreset(id: "mid-high", range: "mid", level: "high", name: "Mid-range vocal, high",
                    values: ["lowCut": 120, "presence": 4, "air": 3, "compress": 45, "double": 8, "reverb": 14, "room": 1.3, "pocket": 4]),
        VoicePreset(id: "mid-medium", range: "mid", level: "medium", name: "Mid-range vocal, medium",
                    values: ["lowCut": 100, "bass": 1, "presence": 4, "air": 2, "compress": 50, "double": 6, "reverb": 12, "room": 1.2, "pocket": 4]),
        VoicePreset(id: "mid-low", range: "mid", level: "low", name: "Mid-range vocal, low",
                    values: ["lowCut": 90, "bass": 2, "presence": 5, "air": 1, "compress": 50, "double": 6, "reverb": 10, "room": 1.1, "pocket": 4]),
        VoicePreset(id: "low-high", range: "low", level: "high", name: "Low vocal, high",
                    values: ["lowCut": 90, "bass": 1, "presence": 5, "air": 2, "compress": 50, "double": 4, "reverb": 10, "room": 1.2, "pocket": 5]),
        VoicePreset(id: "low-medium", range: "low", level: "medium", name: "Low vocal, medium",
                    values: ["lowCut": 70, "bass": 2, "presence": 6, "air": 1, "compress": 55, "double": 4, "reverb": 8, "room": 1.1, "pocket": 5]),
        VoicePreset(id: "low-low", range: "low", level: "low", name: "Low vocal, low",
                    values: ["lowCut": 50, "bass": 3, "presence": 6, "compress": 60, "reverb": 8, "room": 1, "pocket": 6]),
    ]

    /// As recorded, then the nine voices.
    public static let presets: [VoicePreset] = [VoicePreset(id: "off", range: "", level: "", name: "As recorded", values: [:])] + voicePresets

    public static func preset(_ id: String) -> VoiceFx { VoiceFx(presets.first { $0.id == id }?.values ?? [:]) }

    public static func voicePreset(range: String, level: String) -> VoicePreset? {
        voicePresets.first { $0.range == range && $0.level == level }
    }

    /// The preset these settings are, or "" once something's been moved off one.
    public var presetId: String {
        for p in VoiceFx.presets where VoiceFx.preset(p.id) == self { return p.id }
        return ""
    }

    /// "Your own settings" once moved off a preset.
    public var presetName: String {
        let id = presetId
        return VoiceFx.presets.first { $0.id == id }?.name ?? "Your own settings"
    }

    public var isOff: Bool { self == VoiceFx.off }

    /// How a control's value reads: "Centre", "20% left", "Off", "+3 dB", "1.4 s", "35%", "320 ms".
    public static func words(_ control: FxControl, _ v: Double) -> String {
        if control.id == "pan" {
            if v == 0 { return "Centre" }
            return v < 0 ? "\(Int(abs(v).rounded()))% left" : "\(Int(v.rounded()))% right"
        }
        if control.id == "lowCut" && v <= 20 { return "Off" }
        switch control.unit {
        case "dB": return "\(v > 0 ? "+" : "")\(Int(v.rounded())) dB"
        case "s": return String(format: "%.1f s", v)
        case "%": return "\(Int(v.rounded()))%"
        case "": return "\(Int(v.rounded()))"
        default: return "\(Int(v.rounded())) \(control.unit)"
        }
    }

    /// One step of a control, for a remote's left and right or VoiceOver's swipe.
    public func stepped(_ id: String, by steps: Int) -> VoiceFx {
        guard let c = VoiceFx.controls.first(where: { $0.id == id }) else { return self }
        let next = ((self[id] + Double(steps) * c.step) / c.step).rounded() * c.step
        return with(id, next)
    }

    /// What the audio units are set to, as the website's `fxNodes` works them out.
    public var nodes: VoiceFxNodes {
        let c = self["compress"] / 100
        return VoiceFxNodes(
            lowCutHz: self["lowCut"], bassDb: self["bass"], presenceDb: self["presence"], airDb: self["air"],
            compression: c, thresholdDb: c > 0 ? -40 * c : 0, ratio: 1 + 7 * c, makeUpDb: 12 * c * 0.5,
            pan: self["pan"] / 100,
            double: self["double"] / 100 * 0.7,
            echo: self["echo"] / 100 * 0.8, echoTime: self["echoTime"] / 1000, echoFeedback: self["echoRepeats"] / 100,
            reverb: self["reverb"] / 100 * 0.9, room: self["room"],
            musicBassDb: self["musicBass"], musicTrebleDb: self["musicTreble"], pocketDb: self["pocket"] == 0 ? 0 : -self["pocket"])
    }
}

/// Voice settings as audio units take them. Sends (doubling, echo, reverb) are how loud the wet sound is added to the dry.
public struct VoiceFxNodes: Equatable, Sendable {
    public let lowCutHz, bassDb, presenceDb, airDb: Double
    public let compression, thresholdDb, ratio, makeUpDb: Double
    public let pan: Double
    public let double: Double
    public let echo, echoTime, echoFeedback: Double
    public let reverb, room: Double
    public let musicBassDb, musicTrebleDb, pocketDb: Double

    /// An `AVAudioUnitDelay`'s or `AVAudioUnitReverb`'s wet/dry mix, 0 to 100, for a send added at `send` to a dry
    /// voice kept at full: the same balance of wet to dry, at a little less loudness overall.
    public static func wetDry(_ send: Double) -> Double {
        guard send.isFinite, send > 0 else { return 0 }
        return min(100, send / (1 + send) * 100)
    }

    /// Room size in seconds to the nearest of the system's rooms: small room, medium room, large room, medium hall,
    /// large hall. Its index, 0 to 4.
    public static func roomIndex(_ seconds: Double) -> Int {
        switch seconds {
        case ..<0.8: return 0
        case ..<1.5: return 1
        case ..<2.5: return 2
        case ..<3.5: return 3
        default: return 4
        }
    }
}

/// Voice settings, kept on the device for each person on each server, as the Mix's levels are.
public struct VoiceFxStore {
    private let defaults: UserDefaults
    private let key: String

    public init(server: String, profile: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "wms.karaoke.fx|\(server)|\(profile)"
    }

    public func load() -> VoiceFx {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(VoiceFx.self, from: data) else { return .off }
        return saved
    }

    public func save(_ fx: VoiceFx) {
        if fx.isOff {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(fx) {
            defaults.set(data, forKey: key)
        }
    }
}
