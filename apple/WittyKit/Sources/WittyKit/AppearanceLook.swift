// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Settings > Appearance (Design 2, the canvas's `settingsLook`, `policy` and `chooselook` pages): the Look (one of the
// fourteen experiences, chosen for this device or for all of them), the Theme (colour, separate from the look) and
// Import a theme. An administrator can require either part for a profile or for everyone: the server sends that
// finished (`requiredExperience`, `requiredTheme` with who set it) and the page shows it locked, "Required by Willow".
// The pages are `DesignPageSpec` data built here, so the words and the rules can be tested without a screen.

/// `GET /sdui/experiences`: every look, to draw a chooser.
public struct ExperienceCatalogue: Decodable, Equatable, Sendable {
    public struct Info: Decodable, Equatable, Identifiable, Sendable {
        public var id: String
        public var order: Int
        public var name: String
        public var tagline: String
        public var description: String
        /// The theme it wears unless one is required or chosen.
        public var theme: String
        public var tvTheme: String

        enum CodingKeys: String, CodingKey { case id, order, name, tagline, description, theme, tvTheme }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? 0
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? id
            tagline = (try? c.decodeIfPresent(String.self, forKey: .tagline)) ?? ""
            description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
            theme = (try? c.decodeIfPresent(String.self, forKey: .theme)) ?? "default"
            tvTheme = (try? c.decodeIfPresent(String.self, forKey: .tvTheme)) ?? ""
        }

        public init(id: String, name: String, tagline: String = "", theme: String = "default", order: Int = 0) {
            self.id = id
            self.name = name
            self.tagline = tagline
            self.theme = theme
            self.order = order
            description = ""
            tvTheme = ""
        }
    }

    public var experiences: [Info]
    public var `default`: String

    enum CodingKeys: String, CodingKey { case experiences, `default` }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        experiences = ((try? c.decodeIfPresent([Info].self, forKey: .experiences)) ?? []).sorted { ($0.order, $0.id) < ($1.order, $1.id) }
        self.default = (try? c.decodeIfPresent(String.self, forKey: .default)) ?? "lumen"
    }

    public init(experiences: [Info], default: String = "lumen") {
        self.experiences = experiences
        self.default = `default`
    }
}

/// One required part as the server tells it: the value, who required it and for whom.
public struct RequiredPart: Decodable, Equatable, Sendable {
    public var value: String
    public var by: String
    /// `profile`, `kids` or `everyone`.
    public var scope: String

    enum CodingKeys: String, CodingKey { case value, by, scope }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = (try? c.decodeIfPresent(String.self, forKey: .value)) ?? ""
        by = PlainWords.clean((try? c.decodeIfPresent(String.self, forKey: .by)) ?? "", limit: 60)
        scope = (try? c.decodeIfPresent(String.self, forKey: .scope)) ?? ""
    }

    public init(value: String, by: String = "", scope: String = "profile") {
        self.value = value
        self.by = by
        self.scope = scope
    }

    /// "Required by Willow", or "Required by your administrator" when the server named nobody.
    public var words: String { by.isEmpty ? "Required by your administrator" : "Required by \(by)" }
}

/// `GET /sdui/experience`: the look in force on a device and what this profile may choose.
public struct ExperienceState: Decodable, Equatable, Sendable {
    public struct Option: Decodable, Equatable, Sendable {
        public var value: String
        public var label: String
    }

    public struct Choice: Decodable, Equatable, Sendable {
        public var current: String
        /// This device's own choice, empty when it follows the server.
        public var chosen: String
        public var options: [Option]
        public var required: RequiredPart?

        enum CodingKeys: String, CodingKey { case current, chosen, options, required }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            current = (try? c.decodeIfPresent(String.self, forKey: .current)) ?? ""
            chosen = (try? c.decodeIfPresent(String.self, forKey: .chosen)) ?? ""
            options = (try? c.decodeIfPresent([Option].self, forKey: .options)) ?? []
            required = try? c.decodeIfPresent(RequiredPart.self, forKey: .required)
        }

        public init(current: String, chosen: String = "", options: [Option] = [], required: RequiredPart? = nil) {
            self.current = current
            self.chosen = chosen
            self.options = options
            self.required = required
        }
    }

    public var experience: String
    /// Nil for a profile an administrator keeps from rearranging: it may choose nothing.
    public var choice: Choice?
    public var editable: Bool

    enum CodingKeys: String, CodingKey { case experience, choice, editable }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        experience = (try? c.decodeIfPresent(String.self, forKey: .experience)) ?? ""
        choice = try? c.decodeIfPresent(Choice.self, forKey: .choice)
        editable = (try? c.decodeIfPresent(Bool.self, forKey: .editable)) ?? false
    }

    public init(experience: String, choice: Choice?, editable: Bool) {
        self.experience = experience
        self.choice = choice
        self.editable = editable
    }
}

/// The look as `GET /theme` finishes it: the experience and theme in force and who required which.
public struct LookState: Decodable, Equatable, Sendable {
    public var experience: String
    public var theme: String
    public var requiredExperience: RequiredPart?
    public var requiredTheme: RequiredPart?
    /// This profile may import themes of its own.
    public var profileThemes: Bool

    enum CodingKeys: String, CodingKey { case experience, theme, requiredExperience, requiredTheme, profileThemes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        experience = (try? c.decodeIfPresent(String.self, forKey: .experience)) ?? ""
        theme = (try? c.decodeIfPresent(String.self, forKey: .theme)) ?? ""
        requiredExperience = try? c.decodeIfPresent(RequiredPart.self, forKey: .requiredExperience)
        requiredTheme = try? c.decodeIfPresent(RequiredPart.self, forKey: .requiredTheme)
        profileThemes = (try? c.decodeIfPresent(Bool.self, forKey: .profileThemes)) ?? false
    }

    public init(experience: String = "", theme: String = "", requiredExperience: RequiredPart? = nil,
                requiredTheme: RequiredPart? = nil, profileThemes: Bool = false) {
        self.experience = experience
        self.theme = theme
        self.requiredExperience = requiredExperience
        self.requiredTheme = requiredTheme
        self.profileThemes = profileThemes
    }
}

public extension WittyClient {
    /// `GET /sdui/experiences`.
    func experienceCatalogue() async throws -> ExperienceCatalogue { try await get("/sdui/experiences") }

    /// `GET /sdui/experience` for a device: `device` is this installation's own name (`SDUIDevice.query`).
    func experienceState(_ device: SDUIDevice) async throws -> ExperienceState {
        try await get("/sdui/experience" + AppearanceQuery.string(device))
    }

    /// Chooses a look for this device, or for every kind of device the profile uses when `everywhere`. A refusal
    /// (403 when an administrator requires a look or doesn't offer it) carries the server's own reason.
    func chooseExperience(_ id: String, device: SDUIDevice, everywhere: Bool) async throws {
        let body = try JSONEncoder().encode(["experience": id])
        for query in AppearanceQuery.targets(device, everywhere: everywhere) {
            _ = try await call("PUT", "/sdui/experience" + query, body: body)
        }
        // This device's own choice would still win over the one for all: forget it, so it follows them.
        if everywhere { _ = try? await call("DELETE", "/sdui/experience" + AppearanceQuery.string(device)) }
    }

    /// This device follows the server's look again.
    func followServerExperience(device: SDUIDevice) async throws {
        _ = try await call("DELETE", "/sdui/experience" + AppearanceQuery.string(device))
    }

    /// The look in force, with who required which part, from `GET /theme`.
    func lookState() async throws -> LookState {
        struct Whole: Decodable { let look: LookState? }
        let whole: Whole = try await get("/theme")
        return whole.look ?? LookState()
    }

    /// Imports a theme ZIP for this profile (`POST /themes/mine`), or for the server when an administrator
    /// `forServer`. A refusal names the rule: the answer's own words are the error's message.
    @discardableResult
    func importTheme(_ zip: Data, name: String, forServer: Bool) async throws -> ThemeList.ThemeSummary {
        let path = (forServer ? "/themes" : "/themes/mine") + "?name=" + WittyClient.pathPart(name)
        let answer = try await send("POST", path, body: zip, headers: ["Content-Type": "application/zip"])
        return try JSONDecoder().decode(ThemeList.ThemeSummary.self, from: answer.data)
    }
}

enum AppearanceQuery {
    /// `?formFactor=…&device=…` for a device, as the experience routes read them.
    static func string(_ device: SDUIDevice) -> String {
        let pairs = device.query.filter { ["platform", "formFactor", "device"].contains($0.0) }
        return pairs.isEmpty ? "" : "?" + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    /// This device's own key, or, for every device, the form factor each kind of device falls back to.
    static func targets(_ device: SDUIDevice, everywhere: Bool) -> [String] {
        guard everywhere else { return [string(device)] }
        // Only the form-factor keys (`form:phone` ...), which every device without a choice of its own follows: five of the
        // server's 32 entries per profile, and none for this device itself.
        return ["phone", "tablet", "tv", "desktop", "headset"].map { "?platform=\(device.platform)&formFactor=\($0)" }
    }
}

/// The Appearance page and the first-connect chooser, as `DesignPageSpec` data.
public enum AppearancePage {
    /// One theme on offer.
    public struct ThemeChoice: Equatable, Sendable {
        public var id: String
        public var name: String
        public var dark: Bool
        /// Background, second background and accent.
        public var swatches: [String]
        /// Imported by the person, shown "Imported · by <name>".
        public var imported: Bool

        public init(id: String, name: String, dark: Bool = true, swatches: [String] = [], imported: Bool = false) {
            self.id = id
            self.name = name
            self.dark = dark
            self.swatches = swatches
            self.imported = imported
        }
    }

    public struct Inputs: Sendable {
        public var catalogue: ExperienceCatalogue
        public var state: ExperienceState?
        public var look: LookState
        public var themes: [ThemeChoice]
        /// This device's theme choice: empty follows the server.
        public var chosenTheme: String
        /// The look picked on screen but not yet saved.
        public var pendingExperience: String
        public var pendingTheme: String
        /// A device that can pick a file (not an Apple TV) may import a theme.
        public var canPickFile: Bool
        public var server: String
        public var profile: String
        /// A problem to show under the page, the server's words.
        public var problem: String

        public init(catalogue: ExperienceCatalogue, state: ExperienceState? = nil, look: LookState = LookState(),
                    themes: [ThemeChoice] = [], chosenTheme: String = "", pendingExperience: String = "", pendingTheme: String = "",
                    canPickFile: Bool = true, server: String = "", profile: String = "", problem: String = "") {
            self.catalogue = catalogue
            self.state = state
            self.look = look
            self.themes = themes
            self.chosenTheme = chosenTheme
            self.pendingExperience = pendingExperience
            self.pendingTheme = pendingTheme
            self.canPickFile = canPickFile
            self.server = server
            self.profile = profile
            self.problem = problem
        }

        /// The look required of this profile, from the choice or the finished look.
        public var requiredExperience: RequiredPart? { state?.choice?.required ?? look.requiredExperience }
        public var requiredTheme: RequiredPart? { look.requiredTheme }
        public var lookInForce: String { state?.experience.isEmpty == false ? state!.experience : (look.experience.isEmpty ? catalogue.default : look.experience) }

        /// The look drawn as chosen now.
        public var shownExperience: String {
            if let r = requiredExperience { return r.value }
            if !pendingExperience.isEmpty { return pendingExperience }
            if let chosen = state?.choice?.chosen, !chosen.isEmpty { return chosen }
            return lookInForce
        }

        public var shownTheme: String {
            if let r = requiredTheme { return r.value }
            if !pendingTheme.isEmpty { return pendingTheme }
            if !chosenTheme.isEmpty { return chosenTheme }
            return look.theme
        }

        /// Looks this profile may pick: the server's own list for it, never more than it offers.
        public var offered: [ExperienceCatalogue.Info] {
            guard let options = state?.choice?.options, !options.isEmpty else { return catalogue.experiences }
            let ids = Set(options.map(\.value))
            return catalogue.experiences.filter { ids.contains($0.id) }
        }

        /// Whether the look can be changed here: not when required, not when the profile may not rearrange.
        public var lookEditable: Bool { requiredExperience == nil && (state?.editable ?? true) }
    }

    static let fallbackSwatches = ["#0f1115", "#1f232c", "#7955ff"]

    public static func swatches(for theme: String, in themes: [ThemeChoice]) -> [String] {
        themes.first { $0.id == theme }?.swatches ?? fallbackSwatches
    }

    public static func lookCards(_ i: Inputs) -> [DesignPageSpec.Card] {
        let shown = i.shownExperience
        return i.offered.map { info in
            let themeName = i.themes.first { $0.id == info.theme }?.name ?? info.theme.capitalized
            return DesignPageSpec.Card(id: "look-" + info.id, title: info.name,
                                       subtitle: [info.tagline, themeName].filter { !$0.isEmpty }.joined(separator: " · "),
                                       on: info.id == shown, swatches: swatches(for: info.theme, in: i.themes))
        }
    }

    public static func themeCards(_ i: Inputs) -> [DesignPageSpec.Card] {
        let shown = i.shownTheme
        var cards = i.themes.map { t in
            DesignPageSpec.Card(id: "theme-" + t.id, title: t.name,
                                subtitle: t.imported ? "Imported · yours" : (t.dark ? "Dark" : "Light"), on: t.id == shown,
                                swatches: t.swatches.isEmpty ? fallbackSwatches : t.swatches)
        }
        if i.canPickFile, i.requiredTheme == nil {
            cards.append(DesignPageSpec.Card(id: "import-theme", title: "Import a theme…", subtitle: "ZIP of a theme"))
        }
        return cards
    }

    /// Settings > Appearance: Look, Theme, and the one place to the colours of your own.
    public static func settings(_ i: Inputs) -> DesignPageSpec {
        var sections: [DesignPageSpec.Section] = []
        if let r = i.requiredExperience {
            sections.append(.secC("Look · \(r.words)", lookCards(i).filter { $0.id == "look-" + r.value }, 2))
        } else {
            sections.append(.secC("Look", lookCards(i), 5))
        }
        if let r = i.requiredTheme {
            sections.append(.secC("Theme · \(r.words)", themeCards(i).filter { $0.id == "theme-" + r.value }, 6))
        } else {
            sections.append(.secC("Theme", themeCards(i), 6))
        }
        var locked: [String] = []
        if let r = i.requiredExperience { locked.append("the \(i.catalogue.experiences.first { $0.id == r.value }?.name ?? r.value) look") }
        if let r = i.requiredTheme { locked.append("the \(i.themes.first { $0.id == r.value }?.name ?? r.value) theme") }
        if !locked.isEmpty {
            sections.append(.secN("", "Your administrator requires \(locked.joined(separator: " and ")) on this profile, so \(locked.count == 1 ? "it can’t" : "they can’t") be changed here.", true))
        }
        sections.append(.secR("More", [.R("Colours of your own", "", false, "Adjust single colours of the theme")]))
        if !i.problem.isEmpty { sections.append(.secN("", i.problem, true)) }
        var actions: [DesignPageSpec.Action] = []
        if i.lookEditable || i.requiredTheme == nil {
            actions = [.A1("Use on this device"), .A2("Use on all my devices")]
        }
        var foot = ""
        if let r = i.requiredExperience ?? i.requiredTheme { foot = r.words }
        return DesignPageSpec(eyebrow: "Settings · Appearance", title: "Look and theme",
                              lead: "A look is layout and feel. A theme is colour. Choose each separately. Your choice is for this device unless you use it everywhere.",
                              sections: sections, actions: actions, foot: foot)
    }

    /// First connect, in the app: look and theme chosen once. Locked when an administrator requires them.
    public static func chooser(_ i: Inputs) -> DesignPageSpec {
        let required = i.requiredExperience != nil || i.requiredTheme != nil
        var sections: [DesignPageSpec.Section] = []
        if required {
            var cards: [DesignPageSpec.Card] = []
            if let r = i.requiredExperience { cards += lookCards(i).filter { $0.id == "look-" + r.value } }
            if let r = i.requiredTheme { cards += themeCards(i).filter { $0.id == "theme-" + r.value } }
            sections.append(.secC("Required", cards, 2))
            if i.requiredExperience == nil { sections.insert(.secC("Look", lookCards(i), 2), at: 0) }
            if i.requiredTheme == nil { sections.append(.secC("Theme", Array(themeCards(i).prefix(8)), 2)) }
        } else {
            sections = [.secC("Look", lookCards(i), 2), .secC("Theme", themeCards(i).filter { $0.id != "import-theme" }, 2)]
            if i.canPickFile { sections.append(.secP("", [.Cc("Import a theme…")])) }
        }
        if !i.problem.isEmpty { sections.append(.secN("", i.problem, true)) }
        let by = (i.requiredExperience ?? i.requiredTheme)?.by ?? ""
        return DesignPageSpec(eyebrow: i.profile.isEmpty ? "Welcome" : "Welcome, \(i.profile)",
                              title: required && i.requiredExperience != nil && i.requiredTheme != nil ? "Your look is set" : (required ? "Part of your look is set" : "Choose how it looks"),
                              lead: required ? (by.isEmpty ? "Your administrator set this for your profile." : "\(by) set this for your profile.") + " It looks the same on every device."
                                  : "Pick a look and a theme. You can change them any time in Settings.",
                              sections: sections, actions: [required && i.requiredExperience != nil && i.requiredTheme != nil ? .A1("Continue") : .A1("Use this")])
    }

    /// The look and theme as a pressed card id: `look-lumen` or `theme-cinema`.
    public static func pick(_ id: String) -> (look: String?, theme: String?) {
        if id.hasPrefix("look-") { return (String(id.dropFirst(5)), nil) }
        if id.hasPrefix("theme-") { return (nil, String(id.dropFirst(6))) }
        return (nil, nil)
    }
}

/// "This server isn't set up yet": the 503 `setup_required` answer's address, drawn as a spec by the app.
public struct SetupRequired: Equatable, Sendable {
    public var url: String
    public init(url: String) { self.url = url }

    /// The address as shown, without its scheme: `192.168.1.20:9797/setup`.
    public var shown: String {
        url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }

    /// Reads a failed request's body; nil unless it is the `setup_required` answer.
    public static func from(status: Int, body: Data) -> SetupRequired? {
        guard status == 503 else { return nil }
        struct Body: Decodable { let error: String?; let setupURL: String? }
        guard let b = try? JSONDecoder().decode(Body.self, from: body), b.error == "setup_required" else { return nil }
        return SetupRequired(url: b.setupURL ?? "")
    }
}


public extension Notification.Name {
    /// A signed-in request was answered 503 `setup_required`: `userInfo` has `url` (the setup address) and `base`.
    static let wittySetupRequired = Notification.Name("WittySetupRequired")
}

// MARK: - Who must use what

/// What an administrator requires of whom (`GET`/`PUT /sdui/config/experience`): a look, a theme or both, for everyone, for
/// every kids profile or for one profile. Everything else in the policy (defaults, allowed looks, placements) is kept as
/// the server sent it and sent back unchanged.
public struct LookPolicy: Equatable, Sendable {
    public struct Requirement: Equatable, Sendable {
        public var experience: String
        public var theme: String
        public var by: String

        public init(experience: String = "", theme: String = "", by: String = "") {
            self.experience = experience
            self.theme = theme
            self.by = by
        }

        public var isEmpty: Bool { experience.isEmpty && theme.isEmpty }
    }

    public var everyone: Requirement?
    public var kids: Requirement?
    public var profiles: [String: Requirement]
    public var profileThemes: Bool
    /// The rest of the policy as the server sent it, a JSON object.
    var rest: Data

    public init(everyone: Requirement? = nil, kids: Requirement? = nil, profiles: [String: Requirement] = [:],
                profileThemes: Bool = false) {
        self.everyone = everyone
        self.kids = kids
        self.profiles = profiles
        self.profileThemes = profileThemes
        rest = Data("{}".utf8)
    }

    /// Reads the `experiences` object of the answer.
    public init(json: Data) {
        let object = (try? JSONSerialization.jsonObject(with: json) as? [String: Any]) ?? [:]
        func part(_ any: Any?) -> Requirement? {
            guard let d = any as? [String: Any] else { return nil }
            let r = Requirement(experience: d["experience"] as? String ?? "", theme: d["theme"] as? String ?? "", by: d["by"] as? String ?? "")
            return r.isEmpty ? nil : r
        }
        let required = object["required"] as? [String: Any] ?? [:]
        everyone = part(required["everyone"])
        kids = part(required["kids"])
        var people: [String: Requirement] = [:]
        for (id, value) in required["profiles"] as? [String: Any] ?? [:] { if let r = part(value) { people[id] = r } }
        profiles = people
        profileThemes = object["profileThemes"] as? Bool ?? false
        var others = object
        others.removeValue(forKey: "required")
        others.removeValue(forKey: "profileThemes")
        rest = (try? JSONSerialization.data(withJSONObject: others)) ?? Data("{}".utf8)
    }

    /// The body of the `PUT`: what the server sent, with the requirements and the import switch as they are now.
    public func body() throws -> Data {
        var object = (try? JSONSerialization.jsonObject(with: rest) as? [String: Any]) ?? [:]
        func part(_ r: Requirement) -> [String: String] {
            var d: [String: String] = [:]
            if !r.experience.isEmpty { d["experience"] = r.experience }
            if !r.theme.isEmpty { d["theme"] = r.theme }
            return d
        }
        var required: [String: Any] = [:]
        if let everyone, !everyone.isEmpty { required["everyone"] = part(everyone) }
        if let kids, !kids.isEmpty { required["kids"] = part(kids) }
        let named = profiles.filter { !$0.value.isEmpty }.mapValues(part)
        if !named.isEmpty { required["profiles"] = named }
        if required.isEmpty { object.removeValue(forKey: "required") } else { object["required"] = required }
        if profileThemes { object["profileThemes"] = true } else { object.removeValue(forKey: "profileThemes") }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

public extension WittyClient {
    /// The policy and the configuration's `ETag` (administrators).
    func lookPolicy() async throws -> (policy: LookPolicy, etag: String) {
        let data = try await call("GET", "/sdui/config/experience")
        let object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let inner = try JSONSerialization.data(withJSONObject: object["experiences"] ?? [String: Any]())
        return (LookPolicy(json: inner), object["etag"] as? String ?? "")
    }

    /// Saves it, answering the new `ETag`. A refusal's own words (a theme that isn't installed, a change made
    /// elsewhere first) are the error's message.
    func saveLookPolicy(_ policy: LookPolicy, etag: String) async throws -> String {
        let answer = try await send("PUT", "/sdui/config/experience", body: try policy.body(), headers: ["If-Match": etag])
        return answer.header("ETag")?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? etag
    }
}
