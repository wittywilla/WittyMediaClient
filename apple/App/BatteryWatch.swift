// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import GameController
import SwiftUI
import WittyKit

/// The controllers' batteries and this device's, read from the system, for WittyPlay's status bar, the game menu and
/// WittyPlay's own pages (which ask the page's battery and its pads'). A battery running low is said once, politely,
/// wherever it is first seen.
@MainActor
final class BatteryWatch: ObservableObject {
    static let shared = BatteryWatch()

    @Published private(set) var readings: [BatteryReading] = []
    private let notes = LowBatteryNotes()
    private var users = 0
    private var announcers = 0
    private var timer: Timer?
    private var watching: [NSObjectProtocol] = []

    /// A screen showing batteries came up; `stop` when it goes. `announce`: it says when one runs low (a WittyPlay page
    /// says that itself).
    func start(announce: Bool = true) {
        if announce { announcers += 1 }
        users += 1
        guard users == 1 else { return }
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            watching.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.read() }
            })
        }
        #endif
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            watching.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.read() }
            })
        }
        // A controller's level changes without a word: read again now and then, as the website does.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.read() }
        }
        read()
    }

    func stop(announce: Bool = true) {
        if announce { announcers = max(0, announcers - 1) }
        users = max(0, users - 1)
        guard users == 0 else { return }
        timer?.invalidate()
        timer = nil
        watching.forEach(NotificationCenter.default.removeObserver)
        watching = []
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = false
        #endif
    }

    /// Each connected controller in player order, P1 first, with the battery the system gives (none where it gives none).
    static func connected() -> [BatteryReading?] {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil || $0.microGamepad != nil }
        return pads.enumerated().map { index, pad in
            guard let battery = pad.battery, battery.batteryState != .unknown else { return nil }
            return BatteryReading(id: "pad-\(index)", kind: .controller, name: "P\(index + 1)", detail: pad.vendorName ?? "Controller",
                                  level: Double(battery.batteryLevel), charging: battery.batteryState == .charging)
        }
    }

    /// The controllers that have a battery to show.
    static func pads() -> [BatteryReading] { connected().compactMap { $0 } }

    /// The batteries as a WittyPlay page asks for them (`navigator.getBattery`, a pad's `battery`), for the script
    /// `WebPlayerPage.batteries` puts there: numbers only.
    static func pageScript() -> String {
        func number(_ value: Double) -> String { String(format: "%.3f", min(1, max(0, value))) }
        let device = Self.device().map { "{level:\(number($0.level)),charging:\($0.charging),chargingTime:Infinity,dischargingTime:Infinity}" } ?? "null"
        let pads = connected().map { reading in reading.map { "{level:\(number($0.level)),charging:\($0.charging)}" } ?? "null" }
        return "window.__wmcBattery&&window.__wmcBattery(\(device),[\(pads.joined(separator: ","))])"
    }

    static func device() -> BatteryReading? {
        #if os(iOS)
        let device = UIDevice.current
        guard device.isBatteryMonitoringEnabled, device.batteryState != .unknown else { return nil }
        return BatteryReading.device(level: Double(device.batteryLevel), charging: device.batteryState == .charging, full: device.batteryState == .full)
        #else
        return nil
        #endif
    }

    func read() {
        let next = Self.pads() + (Self.device().map { [$0] } ?? [])
        if next != readings { readings = next }
        guard announcers > 0 else { return }
        let said = notes.check(next)
        if !said.isEmpty { announcePolitely(said.joined(separator: " ")) }
    }
}

/// Each battery as an icon and its level in words, the low ones marked "Low" in words too.
struct BatteryChips: View {
    @Environment(\.palette) private var palette
    let readings: [BatteryReading]
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.6) {
            ForEach(readings) { reading in
                HStack(spacing: size * 0.25) {
                    Image(systemName: Self.symbol(reading)).accessibilityHidden(true)
                    Text(reading.text + (reading.isLow ? " · Low" : ""))
                }
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(reading.isLow ? palette.danger : palette.text.opacity(0.85))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(reading.label)
            }
        }
        .lineLimit(1)
    }

    static func symbol(_ reading: BatteryReading) -> String {
        if reading.charging { return "battery.100percent.bolt" }
        switch reading.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
