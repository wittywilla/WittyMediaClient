// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import UniformTypeIdentifiers
import WittyKit

// Settings > Appearance, the first-connect chooser and "this server isn't set up yet" (the design canvas's
// `settingsLook`, `chooselook`, `policy` and `setupblock` pages). The look (one of the fourteen experiences) and the
// theme are chosen separately; the page is `DesignPageSpec` data built in WittyKit (`AppearancePage`). When an
// administrator requires either part the server says who, and the page shows it locked: "Required by Willow".

/// What the Appearance page and the chooser both need: the catalogue, the look in force, the themes on offer, and the
/// saving of a choice. The server's own words are shown when it refuses.
@MainActor
final class AppearanceModel: ObservableObject {
    @Published private(set) var catalogue = ExperienceCatalogue(experiences: [])
    @Published private(set) var state: ExperienceState?
    @Published private(set) var look = LookState()
    @Published var pendingExperience = ""
    @Published var pendingTheme = ""
    @Published var message = ""
    @Published private(set) var busy = false
    @Published private(set) var loaded = false

    func load(_ model: AppModel) async {
        let asking = model.client
        let device = SDUICenter.deviceNow(window: nil)
        async let cat = try? asking.experienceCatalogue()
        async let st = try? asking.experienceState(device)
        async let lk = try? asking.lookState()
        await model.loadThemes()
        let (c, s, l) = await (cat, st, lk)
        guard model.client.base == asking.base else { return }
        if let c { catalogue = c }
        state = s
        if let l { look = l }
        loaded = true
    }

    /// The themes on offer, with the colours to draw a swatch: the server's list, or the built-in ones before it answers.
    static func themes(_ list: ThemeList?) -> [AppearancePage.ThemeChoice] {
        if let themes = list?.themes, !themes.isEmpty {
            return themes.map { t in
                .init(id: t.id, name: t.shownName, dark: t.scheme != "light",
                      swatches: [t.preview?.bg ?? "#0f1115", t.preview?.surface ?? "#1f232c", t.preview?.accent ?? "#7955ff"],
                      imported: t.builtin == false)
            }
        }
        return SharedData.themes.map { t in
            .init(id: t.id, name: t.name ?? t.id, dark: t.scheme != "light", swatches: [t.colours.background, t.colours.card, t.colours.accent])
        }
    }

    func inputs(_ model: AppModel) -> AppearancePage.Inputs {
        var pick = false
        #if !os(tvOS)
        pick = true
        #endif
        // Only a profile the administrator lets import may; an administrator always may.
        let mayImport = pick && (model.user?.isAdmin == true || look.profileThemes)
        return AppearancePage.Inputs(catalogue: catalogue, state: state, look: model.requiredLook.map { merged($0) } ?? look,
                                     themes: Self.themes(model.themeList), chosenTheme: model.themeChoice,
                                     pendingExperience: pendingExperience, pendingTheme: pendingTheme, canPickFile: mayImport,
                                     server: model.client.base, profile: model.user?.shownName ?? "", problem: message)
    }

    private func merged(_ fresh: LookState) -> LookState {
        var out = look
        out.requiredExperience = fresh.requiredExperience
        out.requiredTheme = fresh.requiredTheme
        out.profileThemes = fresh.profileThemes
        return out
    }

    /// Saves the pending look and theme: for this device, or for all of this profile's.
    func save(_ model: AppModel, everywhere: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        message = ""
        let asking = model.client
        let device = SDUICenter.deviceNow(window: nil)
        do {
            if !pendingExperience.isEmpty, state?.editable ?? true {
                try await asking.chooseExperience(pendingExperience, device: device, everywhere: everywhere)
            }
            if !pendingTheme.isEmpty, model.requiredLook?.requiredTheme == nil {
                if everywhere {
                    try await asking.setInterfaceChoice("theme", pendingTheme)
                    model.chooseTheme("")
                } else {
                    model.chooseTheme(pendingTheme)
                }
            }
            pendingExperience = ""
            pendingTheme = ""
            message = everywhere ? "Saved for all your devices." : "Saved for this device."
            announce(message)
            await load(model)
        } catch let error as APIError {
            message = error.message
            announce(error.message)
        } catch {
            message = plainWords(Problem.of(error))
        }
    }

    func importTheme(_ url: URL, _ model: AppModel) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        message = ""
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let made = try await model.client.importTheme(data, name: url.deletingPathExtension().lastPathComponent, forServer: false)
            await model.loadThemes()
            pendingTheme = made.id
            message = "Imported \(made.shownName). Choose it, then Use on this device."
            announce(message)
        } catch let error as APIError {
            // The server names the rule or the limit that refused it.
            message = error.message
            announce(error.message)
        } catch {
            message = "That file couldn’t be read."
        }
    }

    func pressedCard(_ id: String, _ model: AppModel) {
        let picked = AppearancePage.pick(id)
        if let look = picked.look, model.requiredLook?.requiredExperience == nil, state?.editable ?? true { pendingExperience = look }
        if let theme = picked.theme, model.requiredLook?.requiredTheme == nil { pendingTheme = theme }
    }
}

// MARK: - Settings > Appearance

struct ThemeView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var appearance = AppearanceModel()
    @State private var importing = false
    @State private var showPolicy = false

    /// The theme's name for a row of You.
    static func name(of choice: String, server: String?, list: ThemeList? = nil) -> String {
        let themes = AppearanceModel.themes(list)
        func named(_ id: String?) -> String? { themes.first { $0.id == id }?.name }
        return named(choice.isEmpty ? server : choice) ?? (choice.isEmpty ? say("themeServer") : choice)
    }

    private var spec: DesignPageSpec {
        var page = AppearancePage.settings(appearance.inputs(model))
        if model.user?.isAdmin == true {
            page.sections.insert(.secR("People", [.R("Who must use what", "", false, "Require a look or a theme for a profile or everyone")]), at: page.sections.count - (appearance.message.isEmpty ? 0 : 1))
        }
        return page
    }

    private func pressed(_ id: String) {
        switch id {
        case "use-on-this-device": Task { await appearance.save(model, everywhere: false) }
        case "use-on-all-my-devices": Task { await appearance.save(model, everywhere: true) }
        case "import-theme": importing = true
        case "colours-of-your-own": model.path.append(.personalColours)
        case "who-must-use-what": showPolicy = true
        default: appearance.pressedCard(id, model)
        }
    }

    var body: some View {
        DesignSpecPage(spec: spec, onPress: pressed)
            .accessibilityIdentifier("appearance")
            .task { await appearance.load(model) }
            #if !os(tvOS)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .data]) { result in
                if case .success(let url) = result { Task { await appearance.importTheme(url, model) } }
            }
            #endif
            .navigationDestination(isPresented: $showPolicy) { LookPolicyView() }
    }
}

// MARK: - First connect

/// The look and theme chosen once, the first time this profile connects to a server (canvas `chooselook`). Locked when an
/// administrator requires them: "Your look is set".
struct LookChooserView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var appearance = AppearanceModel()
    @State private var importing = false
    let done: () -> Void

    private var spec: DesignPageSpec { AppearancePage.chooser(appearance.inputs(model)) }

    private func pressed(_ id: String) {
        switch id {
        case "continue": done()
        case "use-this":
            Task {
                await appearance.save(model, everywhere: false)
                if appearance.message.hasPrefix("Saved") || (appearance.pendingExperience.isEmpty && appearance.pendingTheme.isEmpty) { done() }
            }
        case "import-a-theme": importing = true
        default: appearance.pressedCard(id, model)
        }
    }

    var body: some View {
        ZStack {
            model.palette.background.ignoresSafeArea()
            DesignSpecPage(spec: spec, onPress: pressed)
        }
        .accessibilityIdentifier("chooselook")
        .task { await appearance.load(model) }
        #if !os(tvOS)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .data]) { result in
            if case .success(let url) = result { Task { await appearance.importTheme(url, model) } }
        }
        #endif
    }
}

/// The first-connect chooser and the "setup required" screen, over the whole app.
struct FirstRunLayers: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @State private var setup: SetupRequired?
    @State private var seenTick = 0

    private var seenKey: String { "lookSeen|\(model.client.base)|\(model.user?.id ?? 0)" }

    private var needsChooser: Bool {
        guard model.stage == .browsing, model.user != nil, !model.client.base.isEmpty else { return false }
        _ = seenTick
        return !UserDefaults.standard.bool(forKey: seenKey)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let setup {
                    SetupRequiredView(address: setup.url.isEmpty ? model.client.base + "/setup" : setup.url,
                                      retry: { Task { await recheck() } }, back: { self.setup = nil; model.stage = .connect(message: "") },
                                      backTitle: "Choose another server")
                        .transition(.opacity)
                } else if needsChooser {
                    LookChooserView {
                        UserDefaults.standard.set(true, forKey: seenKey)
                        seenTick += 1
                    }
                    .transition(.opacity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .wittySetupRequired)) { note in
                guard (note.userInfo?["base"] as? String) == model.client.base else { return }
                setup = SetupRequired(url: (note.userInfo?["url"] as? String) ?? "")
            }
    }

    private func recheck() async {
        if let caps = try? await model.client.capabilities(), caps.setupRequired != true { setup = nil }
    }
}

// MARK: - Who must use what (administrators)

/// The canvas's `policy` page: require a look, a theme or both, for everyone or one profile; whether profiles may import
/// themes. Saved with the configuration's own `ETag`, so a change made elsewhere is never overwritten.
struct LookPolicyView: View {
    @EnvironmentObject private var model: AppModel
    @State private var users: [ManagedUser] = []
    @State private var catalogue = ExperienceCatalogue(experiences: [])
    @State private var themes: [AppearancePage.ThemeChoice] = []
    @State private var policy = LookPolicy()
    @State private var etag = ""
    @State private var message = ""
    /// Who is being chosen for: "everyone" or a profile's id; the requirement being edited.
    @State private var choosing: Choosing?

    struct Choosing: Identifiable {
        let who: String
        let key: String
        var draft: LookPolicy.Requirement
        var id: String { key }
    }

    private func name(look id: String) -> String { catalogue.experiences.first { $0.id == id }?.name ?? id }
    private func name(theme id: String) -> String { themes.first { $0.id == id }?.name ?? id }

    private func words(_ r: LookPolicy.Requirement?) -> String {
        guard let r, !r.isEmpty else { return "Free to choose" }
        var parts: [String] = []
        if !r.experience.isEmpty { parts.append(name(look: r.experience)) }
        if !r.theme.isEmpty { parts.append(name(theme: r.theme)) }
        return parts.joined(separator: " · ") + " (required)"
    }

    private var spec: DesignPageSpec {
        var sections: [DesignPageSpec.Section] = []
        let everyone = policy.everyone
        sections.append(.secR("Everyone", [
            .R("Require a look", everyone?.experience.isEmpty == false ? name(look: everyone!.experience) : "Off", everyone?.experience.isEmpty == false, "People pick their own look"),
            .R("Require a theme", everyone?.theme.isEmpty == false ? name(theme: everyone!.theme) : "Off", everyone?.theme.isEmpty == false, "People pick their own theme"),
            .R("Let people import themes", policy.profileThemes ? "Everyone" : "Administrators only", policy.profileThemes),
        ]))
        sections.append(.secR("Profiles", users.map { u in
            let r = policy.profiles[String(u.id)]
            return .R(u.displayName ?? u.name, words(r), r?.isEmpty == false, r?.isEmpty == false ? "Required by \(r?.by.isEmpty == false ? r!.by : "an administrator")" : (u.kind ?? ""))
        }))
        if !message.isEmpty { sections.append(.secN("", message, true)) }
        return DesignPageSpec(eyebrow: "Settings · People · Looks and themes", title: "Who must use what",
                              lead: "Require a look, a theme, or both, for a profile or for everyone. A required choice is locked, with your name beside it. A profile with nothing required can choose freely.",
                              sections: sections, actions: [.A1("Save"), .A2("Undo")], foot: "Changes apply the next time each person opens an app.")
    }

    private func pressed(_ id: String) {
        switch id {
        case "require-a-look", "require-a-theme":
            choosing = Choosing(who: "everyone", key: "everyone", draft: policy.everyone ?? .init())
        case "let-people-import-themes": policy.profileThemes.toggle()
        case "save": Task { await save() }
        case "undo": Task { await load() }
        default:
            guard let user = users.first(where: { DesignPageSpec.slug($0.displayName ?? $0.name) == id }) else { return }
            choosing = Choosing(who: user.displayName ?? user.name, key: String(user.id), draft: policy.profiles[String(user.id)] ?? .init())
        }
    }

    private func keep(_ done: Choosing) {
        if done.key == "everyone" { policy.everyone = done.draft.isEmpty ? nil : done.draft }
        else { policy.profiles[done.key] = done.draft.isEmpty ? nil : done.draft }
        choosing = nil
    }

    private func load() async {
        message = ""
        let asking = model.client
        async let cat = try? asking.experienceCatalogue()
        async let list = try? asking.themeList()
        async let people = try? asking.managedUsers()
        async let current = try? asking.lookPolicy()
        let (c, l, p, cur) = await (cat, list, people, current)
        if let c { catalogue = c }
        themes = AppearanceModel.themes(l)
        users = p ?? []
        if let cur { policy = cur.policy; etag = cur.etag } else { message = "The policy couldn’t be read." }
    }

    private func save() async {
        do {
            etag = try await model.client.saveLookPolicy(policy, etag: etag)
            message = "Saved."
            announce(message)
            await load()
            message = "Saved."
        } catch let error as APIError {
            message = error.message
            announce(error.message)
        } catch {
            message = plainWords(Problem.of(error))
        }
    }

    var body: some View {
        DesignSpecPage(spec: spec, onPress: pressed)
            .accessibilityIdentifier("look-policy")
            .task { await load() }
            .sheet(item: $choosing) { pick in
                DesignSpecPage(spec: LookPolicy.picker(who: pick.who, current: choosing?.draft ?? pick.draft, looks: catalogue.experiences, themes: themes),
                               onPress: { id in
                                   switch id {
                                   case "done": keep(choosing ?? pick)
                                   case "cancel": choosing = nil
                                   default: choosing?.draft = LookPolicy.applying(id, to: choosing?.draft ?? pick.draft)
                                   }
                               }, onBack: { choosing = nil })
            }
    }
}
