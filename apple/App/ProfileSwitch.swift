// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Switching profile on a device that is already signed in: "Who's watching?" without signing out first
// (the server's docs/PROFILES.md, Switching profile). The server signs this device in as the profile
// chosen, asking for what signing in asks for, and ends the sign-in it came from. Where the server doesn't
// show its profiles to this device, switching is signing out, as it always was: see Household.startSwitch.

/// Every screen a `Route.family` opens.
struct FamilyScreen: View {
    @EnvironmentObject private var model: AppModel
    let place: FamilyRoute

    var body: some View {
        page.environmentObject(model.household.desk)
    }

    @ViewBuilder private var page: some View {
        switch place {
        case .switchProfile: SwitchProfileView()
        case .myPicture: MyPictureView()
        case .profiles: ProfilesView()
        case .addProfile: AddProfileView()
        case .parentPin: ParentPinView()
        case .profile(let id): ManagedProfileView(id: id)
        case .look(let id): ProfileLookView(id: id)
        case .secret(let id): ProfileSecretView(id: id)
        case .report(let id): ProfileReportView(id: id)
        case .limits(let id, let page): ProfileLimitsView(id: id, page: page)
        }
    }
}

struct SwitchProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: HouseholdProfile?
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var problem = ""
    @State private var busy = false
    @State private var wantPassword = false
    @State private var wantCode = false
    @State private var wrongTries = 0
    @Namespace private var scope

    private var people: [HouseholdProfile] { model.household.people }

    private func go(_ profile: HouseholdProfile) {
        guard !busy else { return }
        busy = true
        problem = ""
        Task {
            switch await model.switchProfile(name: profile.name, password: password, code: code) {
            case .signedIn:
                break // the whole app is drawn again for the new profile
            case .needsCode(let words):
                needsCode = true
                code = ""
                problem = words
                wantCode = true
            case .wrong:
                refused("That didn’t work.")
            case .failed(let words):
                refused(words.isEmpty ? "That didn’t work." : words)
            }
            busy = false
        }
    }

    /// The server's own words: a wrong password, or how long to wait after too many.
    private func refused(_ words: String) {
        problem = words
        password = ""
        code = ""
        needsCode = false
        wrongTries += 1
        if chosen != nil { wantPassword = true }
    }

    private func pick(_ profile: HouseholdProfile) {
        if profile.isCurrent {
            dismiss()
            return
        }
        problem = ""
        password = ""
        code = ""
        needsCode = false
        if profile.opensWithTap {
            go(profile)
        } else {
            chosen = profile
            wantPassword = true
        }
    }

    private func back() {
        if chosen != nil {
            chosen = nil
            problem = ""
        } else {
            dismiss()
        }
    }

    @ViewBuilder private var who: some View {
        let size: CGFloat = metrics.tv ? 200 : (metrics.cardWidth > 124 ? 140 : 104)
        VStack(spacing: metrics.tv ? Tokens.Space.s10 : Tokens.Space.s6) {
            SignInHeading(title: say("whoTitle"), display: true, centred: true)
            if !problem.isEmpty { ProblemLine(problem) }
            FlowLayout(spacing: metrics.tv ? 48 : 24, rowSpacing: 28, centred: true) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, profile in
                    VStack(spacing: 2) {
                        ProfileTile(profile: profile.asProfile, avatarSize: size) { pick(profile) }
                            .firstFocus(in: scope, when: index == 0)
                            .disabled(busy)
                            .accessibilityIdentifier("switch-\(profile.name)")
                        HStack(spacing: Tokens.Space.s1) {
                            if profile.isCurrent {
                                Text(profile.note)
                            } else if profile.hasPassword != false {
                                Image(systemName: "lock.fill").accessibilityLabel("Asks for a password or PIN")
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.textSecondary)
                        .frame(height: 18)
                    }
                }
            }
            .remoteSection()
            Button("Sign in with another account") { model.signOut() }
                .action(.quiet)
                .remoteSection()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.gutter)
        .padding(.top, metrics.tv ? Tokens.Space.s10 : Tokens.Space.s8)
        .padding(.bottom, barRoom(metrics))
    }

    @ViewBuilder private func secret(_ profile: HouseholdProfile) -> some View {
        VStack(spacing: Tokens.Space.s4) {
            AvatarTile(name: profile.shownName, size: metrics.tv ? 200 : 120, picture: profile.avatar)
            Text("Switch to \(profile.shownName)").font(.wmHero).foregroundStyle(palette.text).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Tokens.Space.s4) {
                if needsCode {
                    OutlinedField(label: "Code from the authenticator app", text: $code, icon: "lock.shield", request: $wantCode,
                                  invalid: !problem.isEmpty) { go(profile) }
                        .shake(wrongTries)
                } else {
                    OutlinedField(label: SwitchRules.secretLabel(profile), text: $password, kind: .password, icon: "lock",
                                  request: $wantPassword, invalid: !problem.isEmpty) { go(profile) }
                        .shake(wrongTries)
                }
                if !problem.isEmpty { ProblemLine(problem) }
                Button { go(profile) } label: { BusyText("Switch", busy: busy) }
                    .action(.primary, wide: true, tall: true)
                    .disabled(busy || (needsCode ? code.trimmingCharacters(in: .whitespaces).isEmpty : password.isEmpty))
                Button(say("back")) { back() }.action(.quiet)
            }
            .frame(maxWidth: metrics.tv ? 640 : 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.gutter)
        .padding(.top, metrics.tv ? Tokens.Space.s10 : Tokens.Space.s8)
        .padding(.bottom, barRoom(metrics))
    }

    var body: some View {
        ScrollView {
            if let chosen { secret(chosen) } else { who }
        }
        .scrollDismissesKeyboardIfAvailable()
        .focusRoot(scope)
        .pageBackground(palette)
        .onRemoteBack(chosen == nil ? nil : back)
    }
}

/// The person's own picture, where their limits let them choose it.
struct MyPictureView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @State private var value = ""
    @State private var lists: ParentalLists?
    @State private var problem = ""
    @State private var saved = false
    @State private var busy = false

    private func save() {
        guard let me = model.user, !busy else { return }
        busy = true
        problem = ""
        saved = false
        Task {
            do {
                model.user = try await client.setProfileLook(userId: me.id, avatar: value)
                saved = true
            } catch {
                problem = model.handle(error)
            }
            busy = false
        }
    }

    var body: some View {
        SettingsScreen(title: "Your picture", detail: "What stands for you on Who’s watching and around the app. It is drawn by each app: nothing is uploaded.") {
            PicturePicker(name: model.user?.shownName ?? "?", value: $value, lists: lists)
            if !problem.isEmpty { ProblemLine(problem) }
            if saved { OutcomeLine(words: "Your picture is changed.") }
            Button { save() } label: { BusyText(say("save"), busy: busy) }
                .action(.primary, wide: true, tall: true)
                .disabled(busy || value == (model.user?.avatar ?? ""))
        }
        .task {
            value = model.user?.avatar ?? ""
            lists = await model.household.lists()
        }
    }
}
