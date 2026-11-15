// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// A battery on screen: a controller's or this device's, as WittyPlay's status bar and the game menu show them, with the
/// same words as the website (WittyPlay web/battery.ts): "P1 72%", "Battery 64%", and "Low" in words.
public struct BatteryReading: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case device, controller }

    /// "device", or the controller's place: "pad-0".
    public let id: String
    public let kind: Kind
    /// "P1" for a controller, "This device" for the device.
    public let name: String
    /// The controller's own name, for a screen reader.
    public let detail: String
    /// 0 to 1.
    public let level: Double
    public let charging: Bool

    public init(id: String, kind: Kind, name: String, detail: String = "", level: Double, charging: Bool) {
        self.id = id
        self.kind = kind
        self.name = name
        self.detail = detail
        self.level = min(1, max(0, level))
        self.charging = charging
    }

    /// Low: a fifth or under, and not charging.
    public static let low = 0.2
    /// It counts as low again only once it has been back over this, or on charge.
    public static let lowClear = 0.25

    public var percent: Int { Int((level * 100).rounded()) }
    public var isLow: Bool { !charging && level <= Self.low + 1e-9 }

    /// What a chip shows: short, the same everywhere.
    public var text: String { "\(kind == .device ? "Battery" : name) \(percent)%" }

    /// What a screen reader says: "Controller P1, DualSense: battery 72%, charging".
    public var label: String {
        let who = kind == .device ? "This device" : "Controller \(name)" + (detail.isEmpty ? "" : ", \(detail)")
        return "\(who): battery \(percent)%" + (charging ? ", charging" : isLow ? ", low" : "")
    }

    /// The notice for a battery that ran low, said once.
    public var lowNotice: String {
        kind == .device
            ? "This device’s battery is low: \(percent)%. Plug it in soon."
            : "Controller \(name)’s battery is low: \(percent)%. Charge it or change its batteries soon."
    }

    /// This device's battery, or none for one with none to speak of: an unknown level, or full on its charger.
    public static func device(level: Double, charging: Bool, full: Bool) -> BatteryReading? {
        guard level >= 0, level.isFinite else { return nil }
        if full || (charging && level >= 1) { return nil }
        return BatteryReading(id: "device", kind: .device, name: "This device", level: level, charging: charging)
    }
}

/// Which batteries just ran low: each once, until it has been charged again.
public final class LowBatteryNotes {
    private var said: Set<String> = []

    public init() {}

    /// Every reading now; answers the notices to give, if any.
    public func check(_ readings: [BatteryReading]) -> [String] {
        let now = Set(readings.map(\.id))
        // Gone: one that comes back starts afresh.
        said.formIntersection(now)
        var out: [String] = []
        for reading in readings {
            if reading.isLow {
                if said.insert(reading.id).inserted { out.append(reading.lowNotice) }
            } else if reading.charging || reading.level >= BatteryReading.lowClear {
                said.remove(reading.id)
            }
        }
        return out
    }
}
