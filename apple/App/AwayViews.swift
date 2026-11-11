// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// You, This device, From away: how the server is being reached, and taking this device off the
// server's list. One of You's own screens, made of the same parts as the others.

extension AppModel {
    /// The way in use, in a few words, for the row and for the server's card.
    var wayWords: String {
        switch way {
        case .away: return way.words
        case .home: return say("awayAtHomeNow")
        case .none: return ""
        }
    }

    /// What You's row says: the way from away while it's in use, otherwise whether there is one.
    var awayRowValue: String {
        if way.isAway { return way.words }
        return awayReady ? say("awayReady") : awayOff ? say("off") : say("awayNotSetUp")
    }
}

struct AwayView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmStop = false
    @State private var busy = false

    private var problem: String {
        if case .away(let state) = model.way, !state.connected { return PlainWords.clean(state.error ?? "", limit: 300) }
        return ""
    }

    var body: some View {
        SettingsScreen(title: say("rowAway"), detail: say("awayHint")) {
            ListGroup(title: "", footer: model.awayReady ? say("awayReadyHint") : model.awayOff ? say("awayOffHint") : say("awaySetUpHint")) {
                // A row to press: it looks again at how the server can be reached. It also gives a remote
                // somewhere to land on a screen that may have nothing else to press.
                Button {
                    Task { await model.peers.settle() }
                } label: {
                    RowLabel(icon: model.way.isAway ? "dot.radiowaves.left.and.right" : "house", tint: "#0e7c6f", title: say("awayNow"),
                             value: model.wayWords.isEmpty ? say("awayNoWay") : model.wayWords, detail: problem, chevron: false)
                }
                .rowStyle()
                RowLabel(icon: "arrow.triangle.branch", tint: "#3e5bd0", title: say("rowAway"),
                         value: model.awayReady ? say("awayReady") : model.awayOff ? say("off") : say("awayNotSetUp"), chevron: false)
                if model.awayReady, !model.awayDeviceID.isEmpty {
                    // The end of the name the server's own list shows for this device.
                    RowLabel(icon: "key", tint: "#5d6474", title: say("awayDevice"), value: "…" + model.awayDeviceID.suffix(8), chevron: false)
                }
            }
            if model.awayReady {
                Button { confirmStop = true } label: {
                    BusyText(say("awayStop"), busy: busy)
                }
                .action(.destructive, wide: true, tall: true)
                .padding(.top, Tokens.Space.s2)
            } else if model.awayOff {
                Button {
                    guard !busy else { return }
                    busy = true
                    Task {
                        await model.startAway()
                        busy = false
                    }
                } label: {
                    BusyText(say("awayStart"), busy: busy)
                }
                .action(.secondary, wide: true, tall: true)
                .padding(.top, Tokens.Space.s2)
            }
        }
        .confirmationDialog(say("awayStop"), isPresented: $confirmStop, titleVisibility: .visible) {
            Button(say("awayStop"), role: .destructive) {
                guard !busy else { return }
                busy = true
                Task {
                    await model.stopAway()
                    busy = false
                }
            }
        } message: {
            Text(say("awayStopConfirm"))
        }
    }
}

/// The connect screen's "Join from away": for a device that has never been at home with its
/// server and can't take an invite link in, which is an Apple TV. It shows a code; someone
/// signed in types it into the server's Remote Access page; the server and this device find each
/// other by it. The same shape as signing in with a code shown on the TV at home.
struct JoinAwayPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let back: () -> Void
    @State private var code = ""
    @State private var problem = ""
    @State private var finding = false
    @State private var round = 0
    @FocusState private var mainAction: Bool
    @Namespace private var scope

    private func run() async {
        problem = ""
        finding = false
        guard let fresh = PeerLibrary.newJoinCode(), let joining = model.waitToJoin(code: fresh) else {
            code = ""
            problem = PeerLibrary.available ? say("notKept") : say("awayNotHere")
            return
        }
        code = fresh
        let answer = await withTaskCancellationHandler {
            await joining.answer()
        } onCancel: {
            joining.cancel()
        }
        if Task.isCancelled { return }
        guard let answer else {
            code = ""
            problem = say("joinAwayExpired")
            return
        }
        finding = true
        if let words = await model.joined(answer) {
            finding = false
            code = ""
            problem = words
        }
    }

    var body: some View {
        SignInLayout(back: back) {
            BrandLockup(app: true)
            SignInHeading(title: say("joinAwayTitle"), detail: code.isEmpty ? "" : say("joinAwayHint"))
            if !code.isEmpty {
                Text(code)
                    .accessibilityIdentifier("joinCode")
                    .font(.system(size: metrics.tv ? 72 : 40, weight: .bold, design: .monospaced))
                    .kerning(metrics.tv ? 8 : 4)
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, Tokens.Space.s6)
                    .padding(.vertical, Tokens.Space.s3)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
                    .accessibilityLabel(code.map(String.init).joined(separator: " "))
                HStack(spacing: Tokens.Space.s2) {
                    ProgressView()
                    Secondary(finding ? say("joinAwayFinding") : say("joinAwayWaiting"))
                }
            }
            if !problem.isEmpty { ProblemLine(problem) }
        } actions: {
            if code.isEmpty && !problem.isEmpty {
                Button(say("pairNew")) { round += 1 }.action(.primary, wide: true, tall: true).focused($mainAction)
            }
            Button(say("back"), action: back).action(code.isEmpty && !problem.isEmpty ? .quiet : .secondary, wide: true, tall: true)
                .firstFocus(in: scope, when: problem.isEmpty)
            LegalNote()
        }
        .focusRoot(scope)
        .task(id: round) { await run() }
        .onChange(of: problem) { if !$0.isEmpty { mainAction = true } }
    }
}
