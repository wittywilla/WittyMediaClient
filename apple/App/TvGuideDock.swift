// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(tvOS)
import SwiftUI
import WittyKit

// What the guide's Dock opens (docs/plans/DESIGN-2.md section 4, WittyTV): Channels (the set and how many channels a page) and
// Filter and favourites. Like the other sheets over the guide they are in the app's own colours, whichever look the guide has.

/// The key legend at the end of the Dock, in the look's own words and colours, for the input in use.
struct GuideLegend: View {
    @ObservedObject private var input = InputInUse.shared
    let dress: TvDress

    var body: some View {
        let hints = KeyLegend.hints(.guide, device: input.device ?? .remote)
        HStack(spacing: 18) {
            ForEach(hints) { hint in
                HStack(spacing: 6) {
                    Text(hint.glyph).font(dress.font(15, .bold)).foregroundStyle(dress.paint.text)
                        .padding(.horizontal, 8).frame(minWidth: 26, minHeight: 26)
                        .overlay { Capsule().strokeBorder(dress.paint.soft, lineWidth: 1.5) }
                    Text(hint.label).font(dress.font(CGFloat(DesignTokens.Tv.Dock.hintSize) * 0.7)).foregroundStyle(dress.paint.soft).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keys")
        .accessibilityIdentifier("tv.legend")
    }
}

/// The set on screen, and how many channels a page: from the Dock's Channels.
struct GuideChannelsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var device = GuideDevice.shared
    /// The set's name on a server with sets; nil without.
    let setName: String?
    let canFind: Bool
    let isAdmin: Bool
    let total: Int
    let pageStart: Int
    let pageSize: Int
    /// What was chosen; the guide closes the sheet and then does it.
    let choose: (GuideChannelsAction) -> Void
    @Namespace private var scope

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                Text("Channels").font(.wmPage).accessibilityAddTraits(.isHeader)
                if total > 0 {
                    Text(pageSize > 0 && total > pageSize ? GuidePaging.words(start: pageStart, size: pageSize, total: total) : "\(total) channels")
                        .foregroundStyle(palette.textSecondary)
                }
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    if let setName {
                        Button { choose(.sets) } label: {
                            Label("Set: \(setName)", systemImage: "list.bullet").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .action(wide: true)
                        .firstFocus(in: scope)
                    }
                    if canFind {
                        Button { choose(.find) } label: {
                            Label("Find a channel", systemImage: "magnifyingglass").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .action(wide: true)
                    }
                    Button { choose(.go) } label: {
                        Label("Go to a channel number", systemImage: "number").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .action(wide: true)
                    .firstFocus(in: scope, when: setName == nil)
                    if isAdmin {
                        Button { choose(.edit) } label: {
                            Label("Edit channels", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .action(wide: true)
                    }
                }
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Text("Channels a page").font(.wmSection)
                    HStack(spacing: Tokens.Space.s3) {
                        ForEach(GuidePaging.sizes, id: \.self) { size in
                            Button(GuidePaging.sizeName(size)) { device.pageSize = size }
                                .action(selected: device.pageSize == size, pill: true)
                                .accessibilityAddTraits(device.pageSize == size ? [.isSelected] : [])
                        }
                    }
                    .remoteSection()
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .focusRoot(scope)
        .background(palette.background.ignoresSafeArea())
        .onExitCommand { dismiss() }
    }
}

/// Which channels the guide shows: favourites, a group, my library or live TV; the schedule's own search; words typed to
/// find channels, cleared here.
struct GuideFilterSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: GuideStore
    let setFilter: (GuideStore.Filter) -> Void
    let onSearch: () -> Void
    let onClearWords: () -> Void
    @Namespace private var scope

    private func pick(_ next: GuideStore.Filter) {
        // Sets keep their own channels: a filter narrows the set on screen.
        var filter = next
        filter.set = store.filter.set
        filter.q = store.filter.q
        setFilter(filter)
        dismiss()
    }

    var body: some View {
        let f = store.filter
        let anyFavourite = store.lineupAnyFavourite
        let hasBoth = store.lineupHasBoth
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                Text("Filter and favourites").font(.wmPage).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    chips {
                        Button("All channels") { pick(.init()) }
                            .action(selected: f.kind.isEmpty && f.group.isEmpty && !f.favourites, pill: true)
                            .firstFocus(in: scope)
                        if anyFavourite || f.favourites {
                            Button("★ Favourites") { pick(.init(favourites: !f.favourites)) }.action(selected: f.favourites, pill: true)
                        }
                        if hasBoth {
                            Button("My library") { pick(.init(kind: f.kind == "library" ? "" : "library")) }.action(selected: f.kind == "library", pill: true)
                            Button("Live TV") { pick(.init(kind: f.kind == "tuner" ? "" : "tuner")) }.action(selected: f.kind == "tuner", pill: true)
                        }
                    }
                    if !store.groups.isEmpty {
                        Text("Groups").font(.wmSection)
                        chips {
                            ForEach(store.groups, id: \.self) { g in
                                Button(g) { pick(.init(group: f.group == g ? "" : g)) }.action(selected: f.group == g, pill: true)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Button { onSearch() } label: {
                        Label("Search the schedule", systemImage: "magnifyingglass").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .action(wide: true)
                    if !f.q.isEmpty {
                        Button { onClearWords() } label: {
                            Label("Showing channels matching “\(f.q)”. Show every channel", systemImage: "xmark.circle").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .action(wide: true)
                    }
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
            .frame(maxWidth: 1300, alignment: .leading)
        }
        .focusRoot(scope)
        .background(palette.background.ignoresSafeArea())
        .onExitCommand { dismiss() }
    }

    private func chips<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s3) { content() }.padding(.vertical, Tokens.Space.s2)
        }
        .remoteSection()
    }
}

/// What the Channels sheet can ask the guide to open next.
enum GuideChannelsAction { case sets, find, go, edit }
#endif
