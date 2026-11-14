// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// How a show's episodes are laid out on its page, as the website's (web/src/sdui/extras/episodeView.ts): as cards with
/// a still and synopsis, or as a playlist, one line each. The choice made here, else the show's own (which an
/// administrator keeps for everyone), else the server's default (Settings, Playback), else what the page sent.
@MainActor
final class SDUIEpisodeViews: ObservableObject {
    static let shared = SDUIEpisodeViews()
    /// By show id: "cards" or "list". Someone else's choice lasts while the app runs; an administrator's is also saved.
    @Published var chosen: [Int64: String] = [:]

    /// The show a page is about, from its header's item ("show-5").
    static func show(on screen: SDUIScreen?) -> Int64? {
        func find(_ e: SDUIElement) -> SDUIElement? {
            if e.type == "DetailHeader" { return e }
            for c in e.children { if let hit = find(c) { return hit } }
            return nil
        }
        guard let root = screen?.root, let header = find(root) else { return nil }
        let id = header.props.text("itemId")
        guard id.hasPrefix("show-") else { return nil }
        return Int64(id.dropFirst(5))
    }

    /// Asks the show and the server for their choice, the first time the show's page needs it.
    func settle(_ show: Int64, client: WittyClient) async {
        guard chosen[show] == nil else { return }
        let own = (try? await client.showPage(show))?.1.view ?? ""
        let server = own.isEmpty ? ((try? await client.prefs())?.episodeView ?? "") : ""
        guard !own.isEmpty || !server.isEmpty, chosen[show] == nil else { return }
        chosen[show] = TitleLook.episodeView(chosen: nil, show: own, server: server)
    }

    /// Someone pressed Cards or Playlist. An administrator's choice is kept for the show, for everyone.
    func choose(_ view: String, for show: Int64, admin: Bool, client: WittyClient) {
        guard chosen[show] != view else { return }
        chosen[show] = view
        if admin { Task { try? await client.setShowView(show, view) } }
    }
}

/// "Layout", then Cards and Playlist together, as the website's switch above a show's episodes.
struct SDUIEpisodeLayoutSwitch: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var views = SDUIEpisodeViews.shared
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let show: Int64
    let playlist: Bool

    var body: some View {
        HStack(spacing: layout.sp("s")) {
            Text("Layout").sduiFont("caption").foregroundStyle(palette.textSecondary).accessibilityAddTraits(.isHeader)
            #if os(tvOS)
            ForEach([("cards", "Cards"), ("list", "Playlist")], id: \.0) { view, words in
                let on = (view == "list") == playlist
                Button(words) { choose(view) }
                    .action(selected: on, pill: true)
                    .accessibilityLabel("\(words) layout")
                    .accessibilityAddTraits(on ? [.isSelected] : [])
            }
            #else
            Picker("Layout", selection: Binding(get: { playlist ? "list" : "cards" }, set: { choose($0) })) {
                Text("Cards").tag("cards")
                Text("Playlist").tag("list")
            }
            .pickerStyle(.segmented)
            .fixedSize()
            #endif
            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.margin)
        #if os(tvOS)
        .remoteSection()
        #endif
    }

    private func choose(_ view: String) {
        views.choose(view, for: show, admin: model.user?.isAdmin == true, client: model.client)
    }
}

/// An episode in the playlist: its number and name, then its length (and "watched"), and its synopsis where the page
/// shows them; no still. Pressing it does what the card does.
struct SDUIEpisodeLine: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let card: SDUIElement
    let synopsis: Bool

    private var actor: SDUIActor { SDUIActor(model: model, center: center, store: store) }

    var body: some View {
        Button { actor.perform(card.action) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.shown("title")).sduiFont("body", weight: .medium).foregroundStyle(palette.text).lineLimit(1)
                let sub = [card.shown("subtitle"), card.shows.contains("watched") ? "watched" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).sduiFont("caption").foregroundStyle(palette.textSecondary).lineLimit(1) }
                if synopsis, !card.shown("synopsis").isEmpty {
                    Text(card.shown("synopsis")).sduiFont("caption").foregroundStyle(palette.textSecondary)
                        .sduiLines(card.lineLimit("synopsis")).multilineTextAlignment(.leading)
                }
                if card.shows.contains("progress"), let percent = card.progress, percent > 0, percent < 100 {
                    ProgressStrip(fraction: Double(percent) / 100).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, layout.sp("xs"))
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .disabled(card.action == nil)
        .padding(.horizontal, layout.margin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.label)
        .accessibilityAddTraits(.isButton)
    }
}
