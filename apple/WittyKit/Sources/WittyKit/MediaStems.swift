// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// A song's separated parts ("stems"), for karaoke with the real voice track turned down instead of a guess at it:
// docs/LYRICS-KARAOKE.md, "Stems", and docs/CLIENT-API.md, "Media extras". These are the rules: which parts are
// played, how loud each is for a given voice level, and how the parts are kept with the song. MediaStems.swift in
// the app plays them.

/// One part of a song, as `GET /media/{id}/stems` lists it.
public struct Stem: Decodable, Equatable {
    /// vocals, instrumental, drums, bass, other, or multitrack (a Native Instruments file holding them all).
    public let name: String
    public let url: String
    public let mime: String?
    public let size: Double?
    public let multitrack: Bool?
    /// upload, sidecar, separated (the owner's separator made it) or approximate.
    public let source: String?
    /// Made by cancelling what the two channels share: the voice is quieter, not gone, and the music is mono.
    public let approximate: Bool?

    public init(name: String, url: String, mime: String? = nil, size: Double? = nil, multitrack: Bool? = nil, source: String? = nil,
                approximate: Bool? = nil) {
        self.name = name
        self.url = url
        self.mime = mime
        self.size = size
        self.multitrack = multitrack
        self.source = source
        self.approximate = approximate
    }
}

/// The whole answer: the parts, and what the server could make for a song that has none.
public struct StemList: Decodable, Equatable {
    public struct Way: Decodable, Equatable {
        public let available: Bool?
        /// not-a-song, not-a-file, no-ffmpeg, not-configured, admin-only.
        public let reason: String?
        /// The task making it now.
        public let task: String?
        public let note: String?
    }
    public struct Separation: Decodable, Equatable {
        public let approximate: Way?
        public let external: Way?
    }
    public let stems: [Stem]?
    public let separation: Separation?

    public init(stems: [Stem]?, separation: Separation? = nil) {
        self.stems = stems
        self.separation = separation
    }
}

/// How the parts a song has are put together.
public struct StemPlan: Equatable {
    public enum Mode: Equatable {
        /// The voice is its own part: it's turned down by itself, over the music's parts.
        case parts
        /// There's the music without the voice, and no voice alone: the song itself is faded against it.
        case blend
        /// One file with every part in it (a `.stem.mp4`): its tracks are the parts.
        case multitrack
    }

    public let mode: Mode
    /// The voice alone, in `parts`.
    public let vocals: Stem?
    /// The music: the instrumental, or drums, bass and the rest.
    public let backing: [Stem]
    /// The one file, in `multitrack`.
    public let file: Stem?
    /// The music is an approximation, and people are told so.
    public let approximate: Bool
    /// Parts this device can't play (Ogg and WebM), by name.
    public let unplayable: [String]

    /// What Apple's players decode as it arrives: FLAC, WAV, MP3, AAC and MP4 audio. Not Ogg, Opus in Ogg or WebM.
    public static func playable(mime: String?) -> Bool {
        switch (mime ?? "").lowercased() {
        case "audio/flac", "audio/x-flac", "audio/wav", "audio/x-wav", "audio/wave", "audio/mpeg", "audio/mp3", "audio/mp4",
             "audio/x-m4a", "audio/m4a", "audio/aac", "audio/aacp":
            return true
        default:
            return false
        }
    }

    /// The best way to play what the song has, or nil when it's not enough to turn the voice down with:
    ///
    /// 1. A voice part with the music beside it (an instrumental, or drums, bass and other): the real thing.
    /// 2. A file with every part in it.
    /// 3. The music alone (often the approximate instrumental): faded against the song.
    ///
    /// A voice part with no music to put under it is no use for karaoke, and neither is anything this device can't
    /// decode.
    public static func plan(_ stems: [Stem]) -> StemPlan? {
        let unplayable = stems.filter { !playable(mime: $0.mime) }.map(\.name)
        let good = stems.filter { playable(mime: $0.mime) }
        func part(_ name: String) -> Stem? { good.first { $0.name == name && $0.multitrack != true } }
        let instrumental = part("instrumental")
        let pieces = ["drums", "bass", "other"].compactMap(part)
        if let vocals = part("vocals") {
            // A real instrumental is one file to fetch instead of three; an approximate one loses to real pieces.
            if let instrumental, instrumental.approximate != true || pieces.isEmpty {
                return StemPlan(mode: .parts, vocals: vocals, backing: [instrumental], file: nil, approximate: instrumental.approximate == true, unplayable: unplayable)
            }
            if !pieces.isEmpty {
                return StemPlan(mode: .parts, vocals: vocals, backing: pieces, file: nil, approximate: false, unplayable: unplayable)
            }
        }
        if let file = good.first(where: { $0.multitrack == true || $0.name == "multitrack" }) {
            return StemPlan(mode: .multitrack, vocals: nil, backing: [], file: file, approximate: false, unplayable: unplayable)
        }
        if let instrumental {
            return StemPlan(mode: .blend, vocals: nil, backing: [instrumental], file: nil, approximate: instrumental.approximate == true, unplayable: unplayable)
        }
        return nil
    }

    /// Every address this plan fetches, in the order the mixer lays them down.
    public var parts: [Stem] {
        switch mode {
        case .parts: return (vocals.map { [$0] } ?? []) + backing
        case .blend: return backing
        case .multitrack: return file.map { [$0] } ?? []
        }
    }

    /// The line under the controls: what this is, in the app's voice.
    public var note: String {
        if approximate {
            return "This karaoke version is approximate: the voice is quieter, not gone, and the music is mono."
        }
        switch mode {
        case .parts: return "The voice is its own track here, so it can be turned all the way down."
        case .multitrack: return "The voice is its own track in this song's stems file, so it can be turned all the way down."
        case .blend: return "The music plays without its voice track; the slider brings the song's own sound back in."
        }
    }
}

/// How loud each thing is for a voice level from 0 (karaoke) to 1 (as recorded).
public enum StemMix {
    public struct Levels: Equatable {
        /// The voice's own part.
        public var vocals: Float
        /// Each of the music's parts.
        public var backing: Float
        /// The song itself, inside the mix (only in `blend`).
        public var song: Float

        public init(vocals: Float, backing: Float, song: Float) {
            self.vocals = vocals
            self.backing = backing
            self.song = song
        }
    }

    public static func clamp(_ voice: Double) -> Double { voice.isFinite ? min(1, max(0, voice)) : 1 }

    /// The voice follows the slider as the ear hears it: half way sounds half as loud, which is about a
    /// quarter of the signal. The ends are exact: 0 is silence and 1 is the recording.
    static func curve(_ voice: Double) -> Float {
        let v = clamp(voice)
        return Float(v * v)
    }

    /// In `parts` and `multitrack` the music stays whole and only the voice moves. In `blend` the song is faded
    /// against its instrumental so that the music (which both carry) stays level and only what the instrumental
    /// lacks, the voice, comes and goes: song × v + instrumental × (1 − v).
    public static func levels(_ mode: StemPlan.Mode, voice: Double) -> Levels {
        let v = curve(voice)
        switch mode {
        case .parts, .multitrack: return Levels(vocals: v, backing: 1, song: 0)
        case .blend: return Levels(vocals: 0, backing: 1 - v, song: v)
        }
    }

    /// "Voice off", "Voice 40%", "Voice as recorded".
    public static func words(_ voice: Double) -> String {
        let v = clamp(voice)
        if v <= 0.005 { return "Voice off" }
        if v >= 0.995 { return "Voice as recorded" }
        return "Voice \(Int((v * 100).rounded()))%"
    }
}

/// Keeping the mixed parts with the song. The song's own player stays in charge of everything a listener can do
/// (play, pause, seek, speed, the queue, the lock screen); the parts' player is slaved to it and only ever follows.
public enum StemFollow {
    public struct Clock: Equatable {
        /// The song's time, in seconds.
        public var time: Double
        /// 0 when not moving.
        public var rate: Double

        public init(time: Double, rate: Double) {
            self.time = time
            self.rate = rate
        }
    }

    public enum Order: Equatable {
        case nothing
        /// Stop, and wait at this place.
        case hold(at: Double)
        /// Start (or correct) so that the parts are at `time` at the moment the song is, moving at `rate`.
        case lock(time: Double, rate: Double)
    }

    /// Further apart than this while playing and the parts are locked to the song again. The song's own sound is
    /// silent while the parts play, so this is about the words on screen and what a seek feels like, and the parts
    /// stay sample-exact among themselves whatever it is: 40 ms is under a frame of video.
    public static let tolerance = 0.04
    /// Paused, a looser hold: nothing is heard, and seeking a paused player costs a request.
    public static let pausedTolerance = 0.25

    public static func order(song: Clock, parts: Clock, partsReady: Bool) -> Order {
        guard partsReady, song.time.isFinite, parts.time.isFinite else { return .nothing }
        let apart = abs(song.time - parts.time)
        if song.rate == 0 {
            if parts.rate != 0 || apart > pausedTolerance { return .hold(at: song.time) }
            return .nothing
        }
        if parts.rate != song.rate || apart > tolerance { return .lock(time: song.time, rate: song.rate) }
        return .nothing
    }
}

/// What a song without stems can be offered, and what happened when it was asked for.
public enum StemOffer: Equatable {
    /// Nothing to offer: the server can't, or this isn't a song in a library.
    case none
    /// "Make a karaoke version".
    case make
    /// One is being made: the task to follow.
    case making(task: String)

    /// For a song with no usable parts: the approximate instrumental, when the server lists the feature and says it
    /// can make one for this song.
    public static func of(_ list: StemList?, plan: StemPlan?, featured: Bool) -> StemOffer {
        guard featured, plan == nil, let way = list?.separation?.approximate else { return .none }
        if let task = way.task, !task.isEmpty { return .making(task: task) }
        return way.available == true ? .make : .none
    }

    /// Why the owner's separator can't be asked for, for an administrator.
    public static func separatorWords(_ way: StemList.Way?) -> String {
        switch way?.reason {
        case "not-configured":
            return "No stem separator is set up on this server. Its owner names one where the server starts: see “Making stems” in the lyrics and karaoke guide."
        case "admin-only": return "Only an administrator can run the separator."
        case "not-a-song": return "Only songs have stems."
        case "not-a-file": return "This song isn't a file in a library, so there is nothing to make stems from."
        case "no-ffmpeg": return "FFmpeg isn't available on the server."
        default: return ""
        }
    }
}
