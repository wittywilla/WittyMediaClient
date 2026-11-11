// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// A canvas: a short, silent video the server has for a song, an album or a title, looped behind the player and on
// its page (docs/MUSIC.md, "Canvas", and docs/CLIENT-API.md, "Media extras"). It is decoration, so it gives way to
// anything that costs the person something: battery, mobile data, a slow link from away, or their wish for a still
// screen. This is the rule for when it plays; MediaCanvas.swift in the app plays it.

/// What `GET /media/{id}/canvas` answers.
public struct CanvasInfo: Decodable, Equatable {
    public let available: Bool?
    public let url: String?
    public let mime: String?
    public let width: Int?
    public let height: Int?
    public let durationMs: Double?
    /// upload, generated (cut from the video by the server), sidecar or metadata-folder.
    public let source: String?
    /// Why a file that was found isn't used: too-big or too-long.
    public let reason: String?
    /// The task making one now, when one is.
    public let task: String?
    /// An administrator can have one cut from the video.
    public let canGenerate: Bool?

    public init(available: Bool? = nil, url: String? = nil, mime: String? = nil, width: Int? = nil, height: Int? = nil,
                durationMs: Double? = nil, source: String? = nil, reason: String? = nil, task: String? = nil, canGenerate: Bool? = nil) {
        self.available = available
        self.url = url
        self.mime = mime
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.source = source
        self.reason = reason
        self.task = task
        self.canGenerate = canGenerate
    }

    /// An uploaded or generated canvas can be removed from here; one beside the media is the folder's own.
    public var removable: Bool { available == true && (source == "upload" || source == "generated") }

    /// Where it came from, for an administrator.
    public var sourceWords: String {
        switch source {
        case "upload": return "Uploaded"
        case "generated": return "Cut from the video by the server"
        case "sidecar": return "A file beside the media"
        case "metadata-folder": return "From the metadata folder"
        default: return ""
        }
    }

    /// Why a file that was found isn't shown.
    public var refusalWords: String {
        switch reason {
        case "too-big": return "There is a canvas file beside this, but it is over 64 MB, so it isn't used."
        case "too-long": return "There is a canvas file beside this, but it is longer than a minute, so it isn't used."
        default: return ""
        }
    }
}

/// What this device and its surroundings are like right now, as far as a canvas cares.
public struct CanvasConditions: Equatable {
    /// The person's own switch, on this device.
    public var wanted = true
    public var lowPower = false
    public var reduceMotion = false
    /// Mobile data or a personal hotspot.
    public var expensiveNetwork = false
    /// Low Data Mode.
    public var constrainedNetwork = false
    /// The server isn't on the network at home: every byte comes the long way.
    public var awayFromHome = false
    /// An Apple TV HD or as small: one small canvas is all it should decode beside everything else.
    public var smallDevice = false

    public init(wanted: Bool = true, lowPower: Bool = false, reduceMotion: Bool = false, expensiveNetwork: Bool = false,
                constrainedNetwork: Bool = false, awayFromHome: Bool = false, smallDevice: Bool = false) {
        self.wanted = wanted
        self.lowPower = lowPower
        self.reduceMotion = reduceMotion
        self.expensiveNetwork = expensiveNetwork
        self.constrainedNetwork = constrainedNetwork
        self.awayFromHome = awayFromHome
        self.smallDevice = smallDevice
    }
}

public enum CanvasChoice: Equatable {
    /// Play the server's address (a path: the stream token is added where it's played).
    case play(path: String)
    /// Show the still artwork. `why` is for the settings screen and tests, not for nagging anyone.
    case still(why: CanvasRules.Why)
}

public enum CanvasRules {
    public enum Why: String, Equatable {
        case none, switchedOff, reduceMotion, lowPower, lowData, mobileData, away, cannotPlay, tooLarge
    }

    /// The most a small device plays: 720p.
    static let smallDevicePixels = 1280 * 720
    /// Nothing over 1080p is decoded for decoration anywhere.
    static let anyDevicePixels = 1920 * 1080

    /// What Apple's player can show as it comes: MP4 (H.264 or HEVC) and QuickTime. WebM is for browsers and Android.
    public static func playable(mime: String?) -> Bool {
        guard let mime = mime?.lowercased() else { return false }
        return mime.hasPrefix("video/mp4") || mime.hasPrefix("video/quicktime") || mime.hasPrefix("video/x-m4v")
    }

    /// Whether the canvas plays here and now. The order is the order the reasons are said in: the person's own
    /// choices first, then the device's state, then the network.
    public static func decide(_ info: CanvasInfo?, _ now: CanvasConditions) -> CanvasChoice {
        guard let info, info.available == true, let path = info.url, !path.isEmpty else { return .still(why: .none) }
        if !now.wanted { return .still(why: .switchedOff) }
        if now.reduceMotion { return .still(why: .reduceMotion) }
        if now.lowPower { return .still(why: .lowPower) }
        if now.constrainedNetwork { return .still(why: .lowData) }
        if now.expensiveNetwork { return .still(why: .mobileData) }
        if now.awayFromHome { return .still(why: .away) }
        guard playable(mime: info.mime) else { return .still(why: .cannotPlay) }
        let pixels = (info.width ?? 0) * (info.height ?? 0)
        if pixels > (now.smallDevice ? smallDevicePixels : anyDevicePixels) { return .still(why: .tooLarge) }
        return .play(path: path)
    }

    /// The line under the switch, when something other than the switch is keeping canvases still.
    public static func words(_ why: Why) -> String {
        switch why {
        case .none, .switchedOff, .cannotPlay, .tooLarge: return ""
        case .reduceMotion: return "Reduce Motion is on, so pictures stay still."
        case .lowPower: return "Low Power Mode is on, so pictures stay still."
        case .lowData: return "Low Data Mode is on, so pictures stay still."
        case .mobileData: return "On mobile data, pictures stay still."
        case .away: return "Away from the server's own network, pictures stay still."
        }
    }

    /// What keeps every canvas still right now, whatever the canvas: for the settings screen.
    public static func standing(_ now: CanvasConditions) -> Why {
        if case .still(let why) = decide(CanvasInfo(available: true, url: "/x", mime: "video/mp4"), now) { return why }
        return .none
    }

    /// The server's address with the item's stream token on it: the file route takes `st`, as every media route does.
    public static func address(path: String, token: String) -> String {
        guard !token.isEmpty else { return path }
        let escaped = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "_-"))) ?? token
        return path + (path.contains("?") ? "&" : "?") + "st=" + escaped
    }

    /// An Apple TV HD by its model name ("AppleTV5,3"), the one Apple TV without a 4K-class chip.
    public static func isSmallTV(model: String) -> Bool { model == "AppleTV5,3" }
}

/// What `POST /items/{id}/stream-token` answers.
public struct StreamToken: Decodable, Equatable {
    public let token: String
    public let expiresInSec: Double?
}
