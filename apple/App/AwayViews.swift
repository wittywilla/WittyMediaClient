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
    @Environment(\.client) private var client
    @Environment(\.dismiss) private var dismiss
    @State private var confirmStop = false
    @State private var busy = false
    /// An invite made here: its link, and whether its QR code is showing.
    @State private var invite: PeerInviteLink?
    @State private var showQR = false
    @State private var inviting = false
    @State private var inviteProblem = ""
    /// The server wants an administrator's password (and code) again before it makes an invite that signs in as one.
    @State private var needsPassword = false
    @State private var needsCode = false
    @State private var password = ""
    @State private var otp = ""
    @State private var wantPassword = false

    private var problem: String {
        if case .away(let state) = model.way, !state.connected { return PlainWords.clean(state.error ?? "", limit: 300) }
        return ""
    }

    private var peerValue: String { model.awayReady ? say("on") : model.awayOff ? say("off") : say("awayNotSetUp") }

    /// Asks the server for an invite that signs a device in as this profile. The link is shown, never kept or logged.
    private func makeInvite(qr: Bool) {
        guard !inviting, let me = model.user else { return }
        inviting = true
        inviteProblem = ""
        let sentPassword = !password.isEmpty
        Task {
            do {
                invite = try await client.peerInvite(userId: me.id, password: password, otp: otp)
                showQR = qr
                needsPassword = false
                password = ""
                otp = ""
                announce("Invite made. It works once, for \(invite?.minutes ?? 15) minutes.")
            } catch let error as APIError where !error.isExpiredSignIn {
                switch PairRefusal.of(error, sentPassword: sentPassword) {
                case .passwordRequired(let twoFactor):
                    needsPassword = true
                    needsCode = twoFactor
                    wantPassword = true
                case .wrongPassword:
                    inviteProblem = error.message
                    password = ""
                    otp = ""
                    wantPassword = true
                default:
                    inviteProblem = error.message
                }
            } catch {
                inviteProblem = model.handle(error)
            }
            inviting = false
        }
    }

    var body: some View {
        DesignPage(eyebrow: "You · From away", title: "Reach your server from anywhere",
                   lead: "A private, peer-to-peer connection between your devices. Nothing is opened on your router.",
                   identifier: "away") {
            DesignSection(title: "Connection") {
                DesignRows {
                    DesignRow(title: "Peer to peer", value: peerValue, on: model.awayReady,
                              detail: "Between your devices, end to end encrypted")
                    // A row to press: it looks again at how the server can be reached. It also gives a remote
                    // somewhere to land on a screen that may have nothing else to press.
                    DesignRow(title: "Connected to", value: model.wayWords.isEmpty ? say("awayNoWay") : model.wayWords,
                              on: model.way.isAway, detail: problem.isEmpty ? model.brandName : problem) {
                        Task { await model.peers.settle() }
                    }
                    .accessibilityIdentifier("away.now")
                    if model.awayReady, !model.awayDeviceID.isEmpty {
                        // The end of the name the server's own list shows for this device.
                        DesignRow(title: say("awayDevice"), value: "…" + model.awayDeviceID.suffix(8))
                    }
                }
                DesignNote(text: model.awayReady ? say("awayReadyHint") : model.awayOff ? say("awayOffHint") : say("awaySetUpHint"))
            }
            if model.awayReady, model.user?.isAdult != false {
                DesignSection(title: "Invite someone") {
                    DesignChips {
                        DesignChip(title: "Create an invite link", on: true, symbol: "link") { makeInvite(qr: false) }
                            .accessibilityIdentifier("away.invite")
                        DesignChip(title: "Show a QR code", symbol: "qrcode") {
                            if invite != nil { showQR = true } else { makeInvite(qr: true) }
                        }
                        .accessibilityIdentifier("away.inviteQR")
                    }
                    if needsPassword {
                        DesignNote(text: "An invite that signs a device in as an administrator needs your password again.")
                        OutlinedField(label: "Your password", text: $password, kind: .password, icon: "lock", request: $wantPassword) {
                            makeInvite(qr: showQR)
                        }
                        if needsCode { OutlinedField(label: "Code from your authenticator app", text: $otp, icon: "lock.shield") }
                        Button { makeInvite(qr: showQR) } label: { BusyText("Create the invite", busy: inviting) }
                            .action(primary: true)
                            .disabled(password.isEmpty || inviting)
                    }
                    if !inviteProblem.isEmpty { ProblemLine(inviteProblem) }
                    if let invite {
                        DesignRows {
                            DesignRow(title: "Invite link", value: "\(invite.minutes) min", on: true,
                                      detail: "Works once. Send it the way you’d send a password.")
                        }
                        Text(invite.link)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelectionIfAvailable()
                            .accessibilityIdentifier("away.inviteLink")
                        #if os(iOS)
                        ShareLink(item: invite.link) { Label("Share the invite", systemImage: "square.and.arrow.up") }
                            .action()
                        #endif
                        if showQR, let image = QRImage.make(for: invite.link) {
                            QRCard(image: image, caption: "Scan it with the WittyMediaClient camera, under Connect to a remote server.")
                        }
                    }
                }
            }
            DesignSection(title: "Join") {
                DesignChips {
                    DesignChip(title: "Join another server", symbol: "arrow.right.circle") { model.changeServer() }
                }
            }
            DesignSection(title: "") {
                DesignNote(text: "Only people you invite can join. You can end an invite or remove a device at any time.", tone: true)
            }
        } actions: {
            Button("Done") { dismiss() }.action(primary: true)
            if model.awayReady {
                Button { confirmStop = true } label: { BusyText(say("awayStop"), busy: busy) }
                    .action(.destructive)
            } else if model.awayOff {
                Button {
                    guard !busy else { return }
                    busy = true
                    Task {
                        await model.startAway()
                        busy = false
                    }
                } label: { BusyText(say("awayStart"), busy: busy) }
                    .action()
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
        DesignPage(eyebrow: "Connect to a remote server", title: "Join with a code",
                   lead: code.isEmpty ? "" : say("joinAwayHint"), identifier: "joinAway") {
            if !code.isEmpty {
                DesignSection(title: "") {
                    Text(code)
                        .accessibilityIdentifier("joinCode")
                        .font(.system(size: metrics.tv ? 72 : 40, weight: .bold, design: .monospaced))
                        .kerning(metrics.tv ? 8 : 4)
                        .foregroundStyle(palette.text)
                        .padding(.horizontal, Tokens.Space.s6)
                        .padding(.vertical, Tokens.Space.s3)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
                        .accessibilityLabel(code.map(String.init).joined(separator: " "))
                    HStack(spacing: Tokens.Space.s2) {
                        ProgressView()
                        DesignNote(text: finding ? say("joinAwayFinding") : say("joinAwayWaiting"))
                    }
                }
            }
            if !problem.isEmpty { DesignSection(title: "") { ProblemLine(problem) } }
            DesignSection(title: "") {
                DesignNote(text: "Peer to peer connects this device straight to your server from anywhere, end to end encrypted. Nothing is opened on your router.", tone: true)
                LegalNote()
            }
        } actions: {
            if code.isEmpty && !problem.isEmpty {
                Button(say("pairNew")) { round += 1 }.action(primary: true).focused($mainAction)
            }
            Button(say("back"), action: back).action()
                .firstFocus(in: scope, when: problem.isEmpty)
        }
        .onRemoteBack(back)
        .focusRoot(scope)
        .task(id: round) { await run() }
        .onChange(of: problem) { if !$0.isEmpty { mainAction = true } }
    }
}
