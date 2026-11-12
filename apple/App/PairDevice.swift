// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// This device asks to be signed in by one that already is, so nobody types a password with a remote
// (the server's docs/CLIENT-API.md, Signing in). Where the server offers it, that is secure pairing: a QR
// code, the device's code to type, and a PIN that changes every 30 seconds, which the person approving
// reads off this screen. Older servers show the code alone. The rules are in WittyKit's Pairing.swift.

/// One request to be signed in, from asking for a code to being answered.
@MainActor
final class DevicePairing: ObservableObject {
    @Published private(set) var shown: PairShown?
    @Published private(set) var problem = ""
    @Published private(set) var starting = true
    /// The server has handed this device all the codes it will for now: a password is the way in.
    @Published private(set) var limited = false

    private func start(_ client: WittyClient, model: AppModel) async throws -> PairShown {
        // What the server can do may not have been heard yet when this is the first screen.
        var features = model.features
        if features.isEmpty { features = Set((try? await client.capabilities())?.features ?? []) }
        func secure() async throws -> PairShown {
            PairShown(try await client.securePairStart(device: model.deviceName, platform: model.platformName),
                      base: client.base, now: Int64(Date().timeIntervalSince1970))
        }
        if PairRules.startsSecure(features: features) { return try await secure() }
        do {
            return PairShown(try await client.pairStart(device: model.deviceName, platform: model.platformName),
                             base: client.base, now: Int64(Date().timeIntervalSince1970))
        } catch let error as APIError where PairRules.mustBeSecure(error) {
            // The owner allows only pairing with a PIN.
            return try await secure()
        }
    }

    /// Runs until someone answers, the code ends, or the screen goes away.
    func run(model: AppModel) async {
        let client = model.client
        shown = nil
        problem = ""
        limited = false
        starting = true
        let started: PairShown
        do {
            started = try await start(client, model: model)
        } catch let error as APIError where error.status == 429 {
            limited = true
            problem = say("pairBusy")
            starting = false
            return
        } catch {
            if Problem.of(error) != .cancelled { problem = plainWords(Problem.of(error)) }
            starting = false
            return
        }
        guard !Task.isCancelled else { return }
        shown = started
        starting = false
        await withTaskGroup(of: Void.self) { group in
            if let session = started.sessionId {
                group.addTask { await self.keepPinFresh(client, session: session, secret: started.deviceSecret) }
            }
            group.addTask { await self.waitForAnswer(client, started, model: model) }
            // The answer ends it; the PIN is only kept fresh until then.
            for await _ in group {
                group.cancelAll()
            }
        }
    }

    /// A new PIN each time the one shown runs out. A session that is over is the other loop's to notice.
    private func keepPinFresh(_ client: WittyClient, session: String, secret: String) async {
        while !Task.isCancelled {
            let until = shown?.pinExpiresAt ?? 0
            let wait = max(0.3, Double(until) - Date().timeIntervalSince1970 + 0.3)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, shown?.sessionId == session else { return }
            if let next = try? await client.securePairPin(session: session, secret: secret), shown?.sessionId == session {
                shown?.pin = PairRules.digits(next.pin)
                shown?.pinExpiresAt = next.pinExpiresAt ?? Int64(Date().timeIntervalSince1970) + Int64(shown?.period ?? 30)
            } else {
                // Answered, gone, or the network blinked: look again in a moment.
                shown?.pinExpiresAt = Int64(Date().timeIntervalSince1970) + 3
            }
        }
    }

    private func waitForAnswer(_ client: WittyClient, _ started: PairShown, model: AppModel) async {
        var wait = started.intervalSec
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                let state: PairPollState
                if let session = started.sessionId {
                    state = try await client.securePairPoll(session: session, secret: started.deviceSecret)
                } else {
                    state = try await client.pairPollState(deviceSecret: started.deviceSecret)
                }
                guard !Task.isCancelled else { return }
                problem = ""
                switch state {
                case .pending:
                    break
                case .slowDown(let seconds):
                    wait = PairRules.nextWait(current: wait, slowDown: seconds)
                case .approved(let token):
                    // Kept with the key this server proved, as every sign-in is: see AppModel.signedIn.
                    model.signedIn(token: token)
                    return
                case .denied, .expired, .locked:
                    problem = PairRules.ending(state) ?? say("pairExpired")
                    shown = nil
                    return
                }
            } catch {
                let trouble = Problem.of(error)
                if trouble == .cancelled { return }
                // The code stays good through a lost connection, so this keeps trying until it expires.
                problem = plainWords(trouble)
            }
        }
    }
}

/// The screen: what to do on the left (or on top), the QR code and the other ways in beside it.
struct PairPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let onUsePassword: () -> Void
    var onBack: (() -> Void)?
    @StateObject private var pairing = DevicePairing()
    @State private var round = 0
    @Namespace private var scope
    /// The screen's main action, which takes the focus when an answer from the server changes it.
    @FocusState private var mainAction: Bool

    private func bigCode(_ text: String, size: CGFloat, id: String) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .kerning(size / 5)
            .foregroundStyle(palette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, Tokens.Space.s6)
            .padding(.vertical, Tokens.Space.s3)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
            .accessibilityLabel(text.filter { $0 != " " }.map(String.init).joined(separator: " "))
            .accessibilityIdentifier(id)
    }

    private func step(_ number: Int, _ words: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
            Text("\(number).").font(.body.weight(.semibold)).foregroundStyle(palette.textSecondary)
            Text(words).font(.body).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// With a PIN: the two steps, the code to type, and the PIN with how long it has left.
    @ViewBuilder private func secure(_ shown: PairShown) -> some View {
        step(1, "Scan the code with a phone’s camera, or open \(say("rowSignInTv")) on a device that’s already signed in and type:")
        bigCode(shown.code, size: metrics.tv ? 48 : 28, id: "pairCode")
        step(2, "Check it names this device, then type this PIN there:")
        bigCode(PairRules.grouped(shown.pin), size: metrics.tv ? 88 : 48, id: "pairPin")
        TimelineView(.periodic(from: .now, by: 0.5)) { moment in
            let now = moment.date.timeIntervalSince1970
            VStack(alignment: metrics.tv ? .leading : .center, spacing: Tokens.Space.s2) {
                GeometryReader { geo in
                    Capsule().fill(palette.border)
                        .overlay(alignment: .leading) {
                            Capsule().fill(palette.accent)
                                .frame(width: geo.size.width * PairRules.share(until: shown.pinExpiresAt, period: shown.period, now: now))
                        }
                }
                .frame(width: metrics.tv ? 420 : 240, height: 6)
                .accessibilityHidden(true)
                Text("A new PIN in \(PairRules.secondsLeft(until: shown.pinExpiresAt, now: now)) s. "
                     + "This code lasts another \(PairRules.clock(PairRules.secondsLeft(until: shown.expiresAt, now: now))).")
                    .font(.wmSecondary)
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    /// The older way: the address to open, and the code to type there.
    @ViewBuilder private func plain(_ shown: PairShown) -> some View {
        Text(shown.address)
            .font(.wmLabel)
            .foregroundStyle(palette.accentText)
            .multilineTextAlignment(metrics.tv ? .leading : .center)
            .textSelectionIfAvailable()
        bigCode(shown.code, size: metrics.tv ? 72 : 40, id: "pairCode")
    }

    var body: some View {
        let shown = pairing.shown
        SignInLayout(back: onBack) {
            BrandLockup()
            SignInHeading(title: shown?.isSecure == true ? "Sign in with your phone" : say("pairTitle"),
                          detail: shown.map { $0.isSecure ? "" : say("pairHint") } ?? "")
            if let shown {
                if shown.isSecure { secure(shown) } else { plain(shown) }
                HStack(spacing: Tokens.Space.s2) {
                    ProgressView()
                    Secondary(say("pairWaiting"))
                }
            } else if pairing.starting && pairing.problem.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
            if !pairing.problem.isEmpty { ProblemLine(pairing.problem) }
        } actions: {
            if let shown, let qr = QRImage.make(for: shown.address) {
                QRCard(image: qr, caption: shown.isSecure ? "Scan this with your phone" : say("pairScan"))
                    .frame(maxWidth: .infinity, alignment: metrics.tv ? .leading : .center)
            }
            if shown == nil && !pairing.problem.isEmpty {
                if pairing.limited {
                    Button(say("usePassword"), action: onUsePassword).action(.primary, wide: true, tall: true).focused($mainAction)
                } else {
                    Button(say("pairNew")) { round += 1 }.action(.primary, wide: true, tall: true).focused($mainAction)
                }
            }
            FlowLayout(spacing: Tokens.Space.s2, centred: !metrics.tv) {
                if model.canTypeCode { Button(say("codeTitle")) { model.askForCode() }.action(.quiet) }
                if !pairing.limited {
                    Button(say("usePassword"), action: onUsePassword).action(.quiet).firstFocus(in: scope, when: shown != nil)
                }
                Button(say("changeServer")) { model.changeServer() }.action(.quiet)
            }
            .remoteSection()
        }
        .focusRoot(scope)
        .task(id: round) { await pairing.run(model: model) }
        // When the server says no, the remote's focus goes to what to do about it, once it's on screen.
        .whenChanged(pairing.problem.isEmpty) { empty in
            guard !empty, pairing.shown == nil else { return }
            DispatchQueue.main.async { mainAction = true }
        }
    }
}
