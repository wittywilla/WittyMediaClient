// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation
import WittyKit

// This app as a device of the server's Remote Protocol: it announces itself, holds one channel open, answers
// every command it is sent and says what it is playing. docs/REMOTE-PROTOCOL.md, "Being a device"; what to
// announce, what a command means, when to report and what to do when the channel ends are WittyKit's
// (RemoteProtocol.swift). Doing what a command asks is the players' business: see RemotePlayers.swift.

/// Why a command can't be done, in words for the person holding the controller.
struct RemoteRefusal: Error {
    let words: String
    init(_ words: String) { self.words = words }
}

/// The app's players, as the device sees them.
@MainActor
protocol RemoteDevicePlayers: AnyObject {
    /// What this device is doing now, for controllers to show.
    func remoteState(_ abilities: RemoteCapabilities) -> RemoteState
    /// Does it, or throws a `RemoteRefusal`. It returns when the command has been accepted, not when it has finished.
    func remoteDo(_ action: RemoteAction) async throws
}

@MainActor
final class RemoteDeviceHost: ObservableObject {
    /// The id the server gave this device. Kept while the app runs, so coming back is the same device.
    @Published private(set) var deviceId = ""
    /// The channel is open: controllers can see this device and reach it.
    @Published private(set) var online = false
    weak var players: RemoteDevicePlayers?

    private var client: WittyClient?
    private var loop: Task<Void, Never>?
    private var beat: Task<Void, Never>?
    private var obeying: Task<Void, Never>?
    private var reporter = RemoteReporter()
    private var abilities = RemoteCapabilities()
    private var reporting = false
    private var owed = false
    private var started: (name: String, platform: RemotePlatform, limits: RemoteLimits)?

    var running: Bool { loop != nil }

    private static func nowMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }

    /// Announces and holds the channel until told to stop. Calling it again while it runs changes nothing.
    func start(client: WittyClient, name: String, platform: RemotePlatform, limits: RemoteLimits) {
        if loop != nil, self.client === client { return }
        halt()
        self.client = client
        started = (name, platform, limits)
        reporter = RemoteReporter(limits: limits)
        abilities = RemoteAbility.capabilities(platform)
        loop = Task { [weak self] in await self?.run(client: client, name: name, platform: platform) }
        // The heartbeat, and while something plays, where it has got to. Whether one is due is the reporter's rule.
        beat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.reportIfDue()
            }
        }
    }

    private func halt() {
        loop?.cancel()
        loop = nil
        beat?.cancel()
        beat = nil
        obeying?.cancel()
        obeying = nil
        online = false
    }

    /// Closes the channel. With `forget` the server is told this device has gone (the app is signing out, or
    /// the person turned this off); without, it stays listed as not connected for half a minute, and opening
    /// the channel again in that time is the same device.
    func stop(forget: Bool) async {
        let was = client
        let id = deviceId
        halt()
        guard forget else { return }
        client = nil
        deviceId = ""
        if let was, !id.isEmpty { try? await was.remoteForget(id) }
    }

    private func run(client: WittyClient, name: String, platform: RemotePlatform) async {
        var backoff = Backoff()
        while !Task.isCancelled {
            var next = DeviceLife.Next.again(afterSec: 1)
            do {
                let agreed = try await client.remoteAnnounce(RemoteAbility.announcement(name: name, platform: platform, deviceId: deviceId))
                guard !Task.isCancelled else { return }
                deviceId = agreed.deviceId
                // Never more than was announced, and never what the server didn't take.
                if let taken = agreed.capabilities {
                    let mine = RemoteAbility.capabilities(platform)
                    abilities = RemoteCapabilities(mediaKinds: mine.mediaKinds.filter(taken.plays), features: mine.features.filter(taken.has))
                }
                var bye: String?
                for try await event in client.events(client.remoteChannelPath(agreed.deviceId)) {
                    switch event.name {
                    case "hello":
                        online = true
                        backoff.reset()
                        reporter.reset()
                        reportIfDue()
                    case "command":
                        if let command = event.decoded(RemoteCommand.self) { take(command) }
                    case "bye":
                        struct Bye: Decodable { let reason: String? }
                        bye = event.decoded(Bye.self)?.reason ?? ""
                    default:
                        // An event this app has never heard of: skipped, as the protocol asks.
                        break
                    }
                }
                online = false
                next = DeviceLife.after(bye: bye, backoff: &backoff)
            } catch let refusal as APIError {
                online = false
                next = DeviceLife.after(refusal: refusal, backoff: &backoff)
                if refusal.code == "version" { ClientLog.shared.warn("remote", "This app speaks an older Remote Protocol than the server accepts.") }
            } catch {
                // Nothing heard for a minute, or the network went: the channel is dead.
                online = false
                next = DeviceLife.after(bye: nil, backoff: &backoff)
            }
            guard !Task.isCancelled else { return }
            switch next {
            case .stop:
                loop = nil
                beat?.cancel()
                beat = nil
                return
            case .again(let wait):
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            }
        }
    }

    // MARK: Commands

    /// One at a time, in the order they came: a seek sent after a play is done after it.
    private func take(_ command: RemoteCommand) {
        let before = obeying
        obeying = Task { [weak self] in
            await before?.value
            guard !Task.isCancelled else { return }
            await self?.obey(command)
        }
    }

    /// Every command gets an answer, whatever it was.
    private func obey(_ command: RemoteCommand) async {
        var ok = true
        var words = ""
        let action = RemoteAction.read(command, abilities: abilities)
        if case .refuse(let why) = action {
            ok = false
            words = why
        } else if let players {
            do {
                try await players.remoteDo(action)
            } catch let refusal as RemoteRefusal {
                ok = false
                words = refusal.words
            } catch {
                ok = false
                words = "That didn't work on this device."
            }
        } else {
            ok = false
            words = RemoteAction.cantDoThat
        }
        if let client, let id = command.id, !id.isEmpty, !deviceId.isEmpty {
            // A 404 `no-command` means it's no longer waiting (it timed out, or the channel reopened): carry on.
            try? await client.remoteAck(deviceId, command: id, ok: ok, error: words)
        }
        reportSoon()
    }

    // MARK: State

    /// Something changed that a controller would show. It goes as soon as the server's limit allows.
    func reportSoon() {
        guard online else { return }
        Task { [weak self] in
            // A moment for the player to have taken the change in.
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.reportIfDue()
        }
    }

    private func reportIfDue() {
        guard online, let client, let players, !deviceId.isEmpty else { return }
        let state = players.remoteState(abilities)
        let now = Self.nowMs()
        guard reporter.due(state, nowMs: now) else { return }
        guard !reporting else { owed = true; return }
        reporting = true
        reporter.sent(state, nowMs: now)
        let id = deviceId
        Task { [weak self] in
            var refusal: APIError?
            do {
                try await client.remoteReport(id, state)
            } catch let refused as APIError {
                refusal = refused
            } catch {
                // The next one says it.
            }
            guard let self else { return }
            self.reporting = false
            if let refusal {
                if refusal.status == 429 {
                    // Nothing is lost: the latest state goes a moment later.
                    self.reporter.reset()
                    self.reporter.refused(nowMs: Self.nowMs(), retryAfterSec: refusal.retryAfter)
                } else if refusal.status == 404, self.loop != nil, let using = self.client {
                    // The server has forgotten this device: announce again.
                    self.restart(using)
                }
            }
            if self.owed {
                self.owed = false
                self.reportIfDue()
            }
        }
    }

    private func restart(_ client: WittyClient) {
        guard let started else { return }
        halt()
        self.client = nil
        start(client: client, name: started.name, platform: started.platform, limits: started.limits)
    }
}
