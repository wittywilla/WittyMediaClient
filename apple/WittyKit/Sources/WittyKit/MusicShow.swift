// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Design 2, songs, karaoke and visualizers (docs/design-2, DESIGN-2.md sections 10 and 13): the choices every music
// view shares. Album art, the looping silent Canvas video or the visualizer (one three-way choice, remembered on
// this device); lyrics as Follow along or Read; the visualizer's effects, colours and changes.

/// What fills the place behind (or instead of) the album art. The same on Now playing, Lyrics, Karaoke, the
/// visualizer and the mini player.
public enum MusicShow: String, CaseIterable, Codable, Equatable {
    case art, canvas, viz

    public var words: String {
        switch self {
        case .art: return "Album art"
        case .canvas: return "Canvas video"
        case .viz: return "Visualizer"
        }
    }

    static let key = "wms.music.show"

    /// The device's choice; Album art until one is made.
    public static func load(_ defaults: UserDefaults = .standard) -> MusicShow {
        MusicShow(rawValue: defaults.string(forKey: key) ?? "") ?? .art
    }

    public func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.key) }

    /// Why the Canvas choice is dimmed, in words (never hidden): nil when it can be chosen.
    public static func canvasNote(info: CanvasInfo?, conditions: CanvasConditions) -> String? {
        switch CanvasRules.decide(info, conditions) {
        case .play: return nil
        case .still(let why):
            switch why {
            case .none, .cannotPlay: return "This song and its album have no Canvas video."
            case .tooLarge: return "This Canvas video is too large for this device."
            case .switchedOff: return "Canvas video is switched off in You."
            case .reduceMotion: return "Canvas video is paused: Reduce Motion is on."
            case .lowPower: return "Canvas video is paused: Low Power Mode is on."
            case .lowData: return "Canvas video is paused: Low Data Mode is on."
            case .mobileData: return "Canvas video is paused on mobile data."
            case .away: return "Canvas video is paused while you are away from home."
            }
        }
    }

    /// What is really drawn: a choice that can't be had falls back to the album art, and the visualizer needs the
    /// server not to have turned it off.
    public func shown(canvasPlays: Bool, visualizerAllowed: Bool) -> MusicShow {
        switch self {
        case .art: return .art
        case .canvas: return canvasPlays ? .canvas : .art
        case .viz: return visualizerAllowed ? .viz : .art
        }
    }
}

/// Words with times follow the music; the same words as plain text are read at your own pace.
public enum LyricsMode: String, CaseIterable, Codable, Equatable {
    case follow, read

    public var words: String { self == .follow ? "Follow along" : "Read" }

    static let key = "wms.lyrics.mode"

    public static func load(_ defaults: UserDefaults = .standard) -> LyricsMode {
        LyricsMode(rawValue: defaults.string(forKey: key) ?? "") ?? .follow
    }

    public func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.key) }

    /// Follow along needs times. Without them it is dimmed, with this note.
    public static func followNote(timed: Bool) -> String? {
        timed ? nil : "These words have no times, so Follow along is off. Read shows them."
    }

    /// The mode in force: Follow along falls back to Read when the words have no times.
    public func effective(timed: Bool) -> LyricsMode { self == .follow && !timed ? .read : self }

    /// How long a hand-scroll holds the followed line still, in seconds.
    public static let holdSeconds = 4.0
}

/// One visualizer effect: the seventeen classics and Aurora Rings. `id` is what is saved in `musicPlayer`.
public struct VisualizerEffect: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let about: String
    /// Drawn by this app's own Canvas code (Bars, Waves, Drift) rather than by the effects renderer.
    public let native: Bool
}

public enum VisualizerEffects {
    /// WittyVisualizer's effects (effects/*.glsl), in the order its picker shows them, then the new one.
    public static let all: [VisualizerEffect] = [
        .init(id: "skyline", name: "Skyline", about: "The classic spectrum, stacks of lights rising with each note.", native: false),
        .init(id: "phosphor", name: "Phosphor Trace", about: "An oscilloscope: the sound's own shape in a glowing line.", native: false),
        .init(id: "lissajous", name: "Lantern Knots", about: "Left against right: the stereo image as a looping line.", native: false),
        .init(id: "molten", name: "Molten Glass", about: "Sine plasma with a glassy sheen.", native: false),
        .init(id: "wormhole", name: "Wormhole", about: "Falling down a twisting tunnel whose walls carry the music.", native: false),
        .init(id: "warpstars", name: "Warp Field", about: "A starfield that stretches into streaks with the beat.", native: false),
        .init(id: "inkdrift", name: "Ink Drift", about: "Each picture pulled inward and stirred from the last.", native: false),
        .init(id: "prism", name: "Prism Wheel", about: "A kaleidoscope of colour shards folded into a wheel.", native: false),
        .init(id: "embers", name: "Ember Fountain", about: "Thousands of sparks rising in a steady fountain.", native: false),
        .init(id: "sundial", name: "Sun Dial", about: "The spectrum wrapped around a disc of light.", native: false),
        .init(id: "lavalamp", name: "Lava Lamp", about: "Soft blobs that swell, merge and split as they drift.", native: false),
        .init(id: "hearth", name: "Hearth", about: "A pixel fire in the old demo style.", native: false),
        .init(id: "horizon", name: "Horizon Run", about: "A wireframe landscape made of the last second of sound.", native: false),
        .init(id: "cascade", name: "Cascade", about: "A waterfall of sound: a second of music in light.", native: false),
        .init(id: "juliabloom", name: "Fractal Bloom", about: "A Julia fractal steered by the music.", native: false),
        .init(id: "aurora", name: "Northern Veil", about: "Curtains of light over a starry sky. The gentlest of the set.", native: false),
        .init(id: "ripple", name: "Ripple Tank", about: "A pool seen from above; each beat is a drop.", native: false),
        .init(id: "auroraRings", name: "Aurora Rings", about: "Glowing rings that open and close with the music.", native: false),
        // The app's own three, kept: they are cheap and run on any device.
        .init(id: "bars", name: "Bars", about: "Mirrored bars, drawn by the app.", native: true),
        .init(id: "waves", name: "Waves", about: "Layered waves, drawn by the app.", native: true),
        .init(id: "drift", name: "Drift", about: "Soft lights drifting with the sound, drawn by the app.", native: true),
    ]

    /// The seventeen classics and Aurora Rings, as the board draws them (18 effects).
    public static var picker: [VisualizerEffect] { all.filter { !$0.native } }

    public static func named(_ id: String) -> VisualizerEffect? { all.first { $0.id == id } }

    /// The eight colour families the effects move between, and the theme's own colour first.
    public static let colours: [(id: String, name: String)] = [
        ("theme", "Theme colours"), ("ember", "Ember"), ("lagoon", "Lagoon"), ("orchid", "Orchid"), ("citrus", "Citrus"),
        ("ice", "Ice"), ("neon", "Neon"), ("forest", "Forest"), ("rainbow", "Rainbow"),
    ]

    /// How one effect gives way to the next.
    public static let changes: [(id: String, name: String)] = [("fade", "Fade"), ("dissolve", "Dissolve"), ("iris", "Iris"), ("sweep", "Sweep")]

    /// Seconds between automatic changes the picker offers; 0 stays on one effect.
    public static let autoChange = VisualizerPrefs.shuffleChoices
}
