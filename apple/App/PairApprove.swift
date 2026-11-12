// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit
#if os(iOS)
import AVFoundation
#endif

// You → Sign in a TV: this device, already signed in, lets another one in (the server's docs/CLIENT-API.md,
// Signing in). The other device shows a QR code, a code to type and, with a newer server, a PIN that changes
// every 30 seconds. Here the QR code is scanned or the code typed, the server says which device is asking,
// and the PIN read off that device's screen approves it. An administrator signing a device in as themselves
// gives their password again. The rules are in WittyKit's Pairing.swift.
//
// A QR code is only ever taken apart here. Whatever address it names, the question goes to the server this
// app is signed in to and has already proved (AppModel.current), never to the address in the code.

extension AppModel {
    /// The ID of the server this app is signed in to: the one kept with its key, or what the server proves now
    /// when the sign-in is older than that. Empty when it can't be told, and then no scanned code is accepted.
    func signedInServerId() async -> String {
        if let id = current?.serverId, !id.isEmpty { return id }
        let proof = await WittyClient.identify(client.base, saved: [])
        return proof.state == .new ? proof.serverId : ""
    }
}

struct SignInTvView: View {
    /// How the waiting device was found: its typed code, or the session in a scanned code.
    private enum Found: Equatable {
        case code(String)
        case session(PairPayload)
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.client) private var client
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var found: Found?
    @State private var asked: PairRequest?
    @State private var chosen: Int64?
    @State private var names: [Int64: (name: String, picture: String?)] = [:]
    @State private var pin = ""
    @State private var password = ""
    @State private var otp = ""
    /// The server asked for the password, whether or not the profile said it would.
    @State private var passwordAsked = false
    @State private var wantPassword = false
    @State private var busy = false
    @State private var wrongTries = 0
    @State private var wrongPins = 0
    @State private var problem = ""
    @State private var outcome: String?
    @State private var invite: PairInvite?
    /// Six digits for a device to type were asked for, and the server wants the password first.
    @State private var inviteNeedsPassword = false
    @State private var scanning = false
    @State private var cameraNote = ""

    private var needsPin: Bool { asked?.needsPin == true }
    private var needsPassword: Bool {
        passwordAsked || (asked?.profiles ?? []).first { $0.id == chosen }?.needsPassword == true
    }
    private var needsOtp: Bool { needsPassword && (asked?.twoFactor == true || model.user?.twoFactor == true) }
    private var ready: Bool {
        chosen != nil && (!needsPin || pin.count == 6) && (!needsPassword || !password.isEmpty) && (!needsOtp || !otp.isEmpty)
    }

    // MARK: Finding the device

    private func show(_ request: PairRequest, _ how: Found) {
        asked = request
        found = how
        chosen = request.profiles?.first?.id ?? model.user?.id
        pin = ""
        password = ""
        otp = ""
        passwordAsked = false
        problem = ""
    }

    private func look(_ letters: String) {
        guard !busy else { return }
        busy = true
        problem = ""
        Task {
            do {
                show(try await client.pairRequest(code: letters), .code(letters))
            } catch {
                wrongTries += 1
                problem = model.handle(error)
                code = ""
            }
            busy = false
        }
    }

    /// What the camera read. A code for another server, or one that isn't a sign-in at all, is refused here
    /// and nothing is sent anywhere.
    private func scanned(_ text: String) {
        guard !busy else { return }
        busy = true
        problem = ""
        Task {
            switch PairScan.judge(text, signedInTo: await model.signedInServerId()) {
            case .failure(let why):
                problem = why.words
            case .success(.code(let letters)):
                busy = false
                look(letters)
                return
            case .success(.session(let payload)):
                do {
                    show(try await client.pairRequest(payload), .session(payload))
                } catch {
                    problem = model.handle(error)
                }
            }
            busy = false
        }
    }

    private func openScanner() {
        #if os(iOS)
        cameraNote = ""
        Task {
            if await CameraAccess.ask() {
                scanning = true
            } else {
                cameraNote = "This app isn’t allowed to use the camera. Allow it in Settings, or type the code the device shows."
            }
        }
        #endif
    }

    // MARK: Answering

    private func answer(approve: Bool) {
        guard !busy, let found, let chosen else { return }
        busy = true
        problem = ""
        let sentPassword = !password.isEmpty
        Task {
            do {
                switch (found, approve) {
                case (.code(let letters), true):
                    try await client.pairApprove(code: asked?.code ?? letters, userId: chosen, pin: needsPin ? pin : "", password: password, otp: otp)
                case (.session(let payload), true):
                    try await client.pairApprove(payload, userId: chosen, pin: pin, password: password, otp: otp)
                case (.code(let letters), false):
                    try await client.pairDeny(code: asked?.code ?? letters)
                case (.session(let payload), false):
                    try await client.pairDeny(payload)
                }
                outcome = say(approve ? "signInTvDone" : "signInTvDenied")
            } catch let error as APIError {
                refused(error, sentPassword: sentPassword)
            } catch {
                problem = model.handle(error)
            }
            busy = false
        }
    }

    /// The server's own words, and what they mean for this screen.
    private func refused(_ error: APIError, sentPassword: Bool) {
        if error.isExpiredSignIn {
            problem = model.handle(error)
            return
        }
        problem = error.message
        switch PairRefusal.of(error, sentPassword: sentPassword) {
        case .wrongPin(let left):
            pin = ""
            wrongPins += 1
            let tries = PairRefusal.triesWords(left)
            if !tries.isEmpty { problem += " " + tries }
        case .passwordRequired:
            passwordAsked = true
            wantPassword = true
        case .wrongPassword:
            password = ""
            otp = ""
            wantPassword = true
        case .ended:
            // Nothing more can be done with this request: back to the start, with the reason on screen.
            let why = problem
            reset()
            problem = why
        case .wait, .other:
            break
        }
    }

    private func makeInvite() {
        guard !busy, let me = model.user else { return }
        busy = true
        problem = ""
        let sentPassword = !password.isEmpty
        Task {
            do {
                invite = try await client.pairInvite(userId: me.id, password: password, otp: otp)
                inviteNeedsPassword = false
                password = ""
                otp = ""
            } catch let error as APIError where !error.isExpiredSignIn {
                problem = error.message
                switch PairRefusal.of(error, sentPassword: sentPassword) {
                case .passwordRequired:
                    // Said in the screen's own words below: the server's are about approving.
                    problem = ""
                    inviteNeedsPassword = true
                    wantPassword = true
                case .wrongPassword:
                    password = ""
                    otp = ""
                    wantPassword = true
                default:
                    break
                }
            } catch {
                problem = model.handle(error)
            }
            busy = false
        }
    }

    private func reset() {
        code = ""
        found = nil
        asked = nil
        outcome = nil
        invite = nil
        inviteNeedsPassword = false
        pin = ""
        password = ""
        otp = ""
        passwordAsked = false
        problem = ""
    }

    private func shownName(_ choice: PairProfile) -> String {
        if choice.id == model.user?.id { return model.user?.shownName ?? choice.name }
        return names[choice.id]?.name ?? choice.name
    }

    private func picture(_ choice: PairProfile) -> String? {
        choice.id == model.user?.id ? model.user?.avatar : names[choice.id]?.picture
    }

    // MARK: The screens

    @ViewBuilder private var passwordFields: some View {
        OutlinedField(label: "Your password", text: $password, kind: .password, icon: "lock", request: $wantPassword)
        if needsOtp || (inviteNeedsPassword && model.user?.twoFactor == true) {
            OutlinedField(label: "Code from your authenticator app", text: $otp, icon: "lock.shield")
        }
    }

    @ViewBuilder private func card(_ request: PairRequest) -> some View {
        HStack(spacing: Tokens.Space.s3) {
            IconTile(symbol: "tv", hex: "#bd2f85")
            VStack(alignment: .leading, spacing: 2) {
                Text(request.deviceName).font(.wmLabel.weight(.semibold)).foregroundStyle(palette.text)
                if !request.facts.isEmpty { Text(request.facts).font(.wmSecondary).foregroundStyle(palette.textSecondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s4)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pair-device")
        SectionTitle(say("signInTvAs"))
        FlowLayout(spacing: Tokens.Space.s4, rowSpacing: Tokens.Space.s3) {
            ForEach(request.profiles ?? []) { choice in
                let picked = chosen == choice.id
                Button {
                    chosen = choice.id
                    passwordAsked = false
                } label: {
                    VStack(spacing: Tokens.Space.s2) {
                        AvatarTile(name: shownName(choice), size: 72, picture: picture(choice))
                            .overlay {
                                if picked {
                                    RoundedRectangle(cornerRadius: 72 * 0.22 + 6, style: .continuous)
                                        .inset(by: -6)
                                        .strokeBorder(palette.accent, lineWidth: 3)
                                }
                            }
                        Text(shownName(choice)).font(.wmLabel).foregroundStyle(picked ? palette.text : palette.textSecondary).lineLimit(1)
                    }
                    .frame(width: 96)
                    .padding(.vertical, Tokens.Space.s2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shownName(choice))
                .accessibilityAddTraits(picked ? [.isSelected] : [])
                .accessibilityIdentifier("pair-as-\(choice.name)")
            }
        }
        if needsPin {
            SectionTitle("The PIN on its screen")
            Secondary("Six digits that change every 30 seconds. Type the ones showing now.")
            DigitsEntry(code: $pin, checking: busy, wrongTries: wrongPins, label: "The PIN on its screen") { _ in
                if ready { answer(approve: true) }
            }
        }
        if needsPassword {
            Secondary("Signing a device in as an administrator needs your password again.")
            passwordFields
        }
        if !problem.isEmpty { ProblemLine(problem) }
        Button { answer(approve: true) } label: { BusyText(say("signInTvApprove"), busy: busy) }
            .action(.primary, wide: true, tall: true)
            .disabled(!ready || busy)
        Button(say("signInTvDeny")) { answer(approve: false) }
            .action(.quiet)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func inviteCard(_ invite: PairInvite) -> some View {
        let minutes = max(1, (invite.expiresInSec ?? 600) / 60)
        Text(invite.code)
            .font(.system(size: 44, weight: .bold, design: .monospaced))
            .kerning(8)
            .foregroundStyle(palette.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Space.s6)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
            .accessibilityLabel(invite.code.map(String.init).joined(separator: " "))
            .accessibilityIdentifier("pair-invite")
        Secondary(say("signInTvInviteHint").replacingOccurrences(of: "{minutes}", with: "\(minutes)"))
        Button(say("back")) { reset() }.action(.secondary, wide: true, tall: true)
    }

    @ViewBuilder private var start: some View {
        #if os(iOS)
        if CameraAccess.exists {
            Button { openScanner() } label: { Label("Scan the code on its screen", systemImage: "qrcode.viewfinder") }
                .action(.primary, wide: true, tall: true)
                .accessibilityIdentifier("pair-scan")
            if !cameraNote.isEmpty { Secondary(cameraNote) }
            Secondary("Or type the code it shows:")
        }
        #endif
        LetterCodeEntry(code: $code, checking: busy, wrongTries: wrongTries, onComplete: look)
        if !problem.isEmpty { ProblemLine(problem) }
        if inviteNeedsPassword {
            Secondary("A code that signs a device in as an administrator needs your password again.")
            passwordFields
            Button { makeInvite() } label: { BusyText("Get a code", busy: busy) }
                .action(.secondary, wide: true, tall: true)
                .disabled(password.isEmpty || busy)
        } else {
            Button(say("signInTvInvite")) { makeInvite() }
                .action(.quiet)
                .frame(maxWidth: .infinity)
        }
    }

    var body: some View {
        SettingsScreen(title: say("rowSignInTv"), detail: asked == nil && invite == nil && outcome == nil ? say("signInTvHint") : "") {
            if model.user?.isAdult == false {
                Secondary(say("signInTvAdultOnly"))
            } else if let outcome {
                OutcomeLine(words: outcome, good: outcome == say("signInTvDone"))
                Button(say("signInTvAnother")) { reset() }.action(.secondary, wide: true, tall: true)
                Button(say("back")) { dismiss() }.action(.primary, wide: true, tall: true)
            } else if let invite {
                inviteCard(invite)
            } else if let asked {
                card(asked)
            } else {
                start
            }
        }
        .animation(.easeOut(duration: Tokens.Motion.appear), value: asked)
        #if os(iOS)
        .sheet(isPresented: $scanning) {
            ScannerSheet { text in
                scanning = false
                scanned(text)
            }
        }
        #endif
        .task {
            // The pairing answer has usernames only; these have the names and pictures people chose.
            if model.has("profile-switching"), let listed = try? await client.household(), !listed.isEmpty {
                names = Dictionary(listed.map { ($0.id, ($0.shownName, $0.avatar)) }, uniquingKeysWith: { first, _ in first })
            } else if let listed = try? await client.profiles().profiles {
                names = Dictionary(listed.map { ($0.id, ($0.shownName, $0.avatar)) }, uniquingKeysWith: { first, _ in first })
            }
            #if DEBUG
            // For checking this screen on a simulator, which has no camera: `-WMCScan <what a QR code says>`.
            if let text = UserDefaults.standard.string(forKey: "WMCScan"), asked == nil { scanned(text) }
            #endif
        }
    }
}

// MARK: - The camera

#if os(iOS)
/// Whether there is a camera, and whether this app may use it. A simulator has none; there the code is typed.
enum CameraAccess {
    static var exists: Bool { AVCaptureDevice.default(for: .video) != nil }

    /// Asks the first time. False when the person said no, now or before.
    static func ask() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

/// The camera, looking for a QR code. The first one it reads is handed over and it stops looking.
private struct ScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onFound: (String) -> Void
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            if failed {
                Text("The camera couldn’t be started. Type the code the device shows instead.")
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(Tokens.Space.s8)
                    .frame(maxHeight: .infinity)
            } else {
                CodeCamera(onFound: onFound, onFailed: { failed = true })
                    .ignoresSafeArea()
                    .accessibilityLabel("Camera, looking for a sign-in code")
            }
            VStack(spacing: Tokens.Space.s3) {
                Text("Point the camera at the code on the screen of the device you want to sign in.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button(say("cancel")) { dismiss() }.action(.secondary, wide: true, tall: true)
            }
            .padding(Tokens.Space.s6)
            .background(Color.black.opacity(0.6))
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct CodeCamera: UIViewRepresentable {
    let onFound: (String) -> Void
    let onFailed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound, onFailed: onFailed) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.videoGravity = .resizeAspectFill
        context.coordinator.start(showing: view.preview)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) { coordinator.stop() }

    /// A view whose layer is the camera's picture, turned the way the device is held.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var preview: AVCaptureVideoPreviewLayer {
            // The layer is the class named above, so this cannot fail.
            layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let connection = preview.connection, connection.isVideoOrientationSupported else { return }
            switch window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: connection.videoOrientation = .landscapeLeft
            case .landscapeRight: connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            default: connection.videoOrientation = .portrait
            }
        }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        /// Starting and stopping the camera blocks, so it has a queue of its own.
        private let queue = DispatchQueue(label: "com.wittywilla.wittymediaclient.scanner")
        private let onFound: (String) -> Void
        private let onFailed: () -> Void
        private var done = false

        init(onFound: @escaping (String) -> Void, onFailed: @escaping () -> Void) {
            self.onFound = onFound
            self.onFailed = onFailed
        }

        func start(showing preview: AVCaptureVideoPreviewLayer) {
            preview.session = session
            let session = session
            queue.async { [weak self] in
                guard let self, let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera),
                      session.canAddInput(input) else {
                    DispatchQueue.main.async { self?.onFailed() }
                    return
                }
                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else {
                    DispatchQueue.main.async { self.onFailed() }
                    return
                }
                session.beginConfiguration()
                session.addInput(input)
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
                session.commitConfiguration()
                session.startRunning()
            }
        }

        func stop() {
            let session = session
            queue.async { if session.isRunning { session.stopRunning() } }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let text = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
            done = true
            stop()
            onFound(text)
        }
    }
}
#endif
