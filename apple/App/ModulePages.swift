// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

#if os(tvOS)
// A module's page that Apple TV has no screen for (a book, a PDF, comics, statistics, the folder browser, an audio
// CD, the visualizer's stage): drawn as a Design 2 page in the look in use, never as a frame of its own. It names
// the module, says what the page does, and gives the code for a phone's camera and the address to type.

/// What each module's page is for, in the words the design's module board uses.
enum ModulePageWords {
    static func lead(for label: String, path: String) -> String {
        let key = (label + " " + path).lowercased()
        let table: [(String, String)] = [
            ("stat", "Hours watched, the most played genre, this week and who is watching."),
            ("file", "Browse the server's folders, with sizes and dates, and open a file."),
            ("photo", "Your timeline, map and albums."),
            ("comic", "Comics and manga, a page or a spread at a time."),
            ("manga", "Comics and manga, a page or a spread at a time."),
            ("pdf", "Pages with thumbnails and your notes."),
            ("book", "Chapters, highlights and notes, and the page you were on."),
            ("read", "Chapters, highlights and notes, and the page you were on."),
            ("visual", "The visualizer's stage, with its effects and colours."),
            ("cd", "An audio CD in the server's drive: play it or import it to the library."),
        ]
        return table.first { key.contains($0.0) }?.1 ?? "This page is made for a phone, tablet or computer."
    }
}

struct ModuleOnPhonePage: View {
    @EnvironmentObject private var model: AppModel
    let path: String
    let url: URL

    private var label: String { model.stripPlaces.first { $0.path == path }?.label ?? "" }

    var body: some View {
        OnAComputerCard(title: label.isEmpty ? "Open this on a phone or computer" : label,
                        line: ModulePageWords.lead(for: label, path: path),
                        address: url.absoluteString, summary: [],
                        footer: "Apple TV shows the library, the guide, games and music. This page needs a keyboard or a touch screen.",
                        symbol: "iphone", identifier: "design.module")
    }
}

/// An editor the server keeps for a computer (its TV levels, WittyMediaServer 0.8.1, TvLevels.swift): what is set now,
/// and the page's code and address, on the server's home address when this TV reached it some other way, with the
/// server's own words ("To change this, use the WittyMediaClient app on a Windows or Mac computer, or a web browser.").
struct EditorOnComputerPage: View {
    @EnvironmentObject private var model: AppModel
    let path: String
    let screen: TvScreenLevel
    let note: String
    @State private var summary = TvSummary()

    private var address: String { TvLevels.cardAddress(base: model.client.base, path: path, home: summary.addresses) }

    private var footer: String {
        let words = note.isEmpty ? "To change this, use the WittyMediaClient app on a Windows or Mac computer, or a web browser." : note
        return words + " " + say("tvCardApplies")
    }

    var body: some View {
        OnAComputerCard(title: screen.title.isEmpty ? "On a computer" : screen.title,
                        line: say("tvCardLine"),
                        address: address, summary: summary.lines,
                        footer: footer,
                        symbol: OnAComputerCard.symbol(for: path), identifier: "design.tv-level")
            .task(id: path) {
                if let found = try? await model.client.tvSummary(screen.summary) { summary = found }
            }
    }
}

/// The card for something Apple TV doesn't change itself, the twin of Android TV's OnAComputerCard: the same centred
/// column as the sign-in screens ("Who's watching?"), for across the room. The server's lockup small at the top under
/// the soft glow, the setting's symbol and name as the heading, one short line, the QR code as the centrepiece on a
/// white tile with "or open" and the address under it, what is set now in a card, Back focused, and a quiet line at the
/// foot. Menu on the remote leaves, as Back does. No keys of a keyboard are drawn.
struct OnAComputerCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Namespace private var scope
    let title: String
    let line: String
    let address: String
    let summary: [String]
    let footer: String
    let symbol: String
    let identifier: String

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            SignInGlow()
            GeometryReader { geo in
                ScrollView {
                    column(qr: min(360, geo.size.height * 0.34))
                        .padding(.vertical, 48)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .unclippedScroll()
            }
        }
        .focusRoot(scope)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func column(qr: CGFloat) -> some View {
        VStack(spacing: 22) {
            BrandLockup().scaleEffect(0.7).frame(height: 56)
            HStack(spacing: 20) {
                Image(systemName: symbol).font(.system(size: 56, weight: .semibold)).foregroundStyle(palette.accentText)
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 64, weight: .heavy)).foregroundStyle(palette.text)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if !line.isEmpty {
                Text(line).font(.system(size: 32)).foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 1300)
            }
            if !address.isEmpty {
                if let image = QRImage.make(for: address) {
                    Image(image, scale: 1, label: Text(say("tvCardOrOpen") + " " + address))
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(width: qr, height: qr)
                        .padding(28)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white))
                }
                VStack(spacing: 4) {
                    Text(say("tvCardOrOpen")).font(.system(size: 26)).foregroundStyle(palette.textSecondary)
                    Text(address).font(.system(size: 34, weight: .bold)).foregroundStyle(palette.accentText)
                        .multilineTextAlignment(.center).frame(maxWidth: 1400)
                }
            }
            if !summary.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(summary.enumerated()), id: \.offset) { item in
                        Text(item.element).font(.system(size: item.offset == 0 ? 32 : 28, weight: item.offset == 0 ? .bold : .regular))
                            .foregroundStyle(item.offset == 0 ? palette.text : palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 40).padding(.vertical, 20)
                .frame(maxWidth: 1000)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.panel))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Set now: " + summary.joined(separator: ", "))
            }
            Button(say("back")) { dismiss() }
                .mainAction()
                .firstFocus(in: scope)
                .accessibilityIdentifier(identifier + ".back")
            if !footer.isEmpty {
                Text(footer).font(.system(size: 24)).foregroundStyle(palette.textSecondary.opacity(0.8))
                    .multilineTextAlignment(.center).frame(maxWidth: 1300)
            }
        }
    }

    /// The symbol for a setting's address, as You's rows have them.
    static func symbol(for path: String) -> String {
        let bare = path.split(separator: "?").first.map(String.init) ?? path
        let p = bare.split(separator: "#").first.map(String.init) ?? bare
        let table: [(String, String)] = [
            ("/settings/libraries", "books.vertical"), ("/manage", "books.vertical"), ("/settings/pages", "sidebar.left"),
            ("/settings/metadata", "photo.on.rectangle"), ("/settings/game-metadata", "photo.on.rectangle"), ("/fix-matches", "wand.and.stars"),
            ("/settings/channels", "antenna.radiowaves.left.and.right"), ("/settings/tuners", "antenna.radiowaves.left.and.right"),
            ("/tv/channels", "antenna.radiowaves.left.and.right"), ("/settings/transcoding", "bolt"),
            ("/settings/library-transcoding", "arrow.triangle.2.circlepath"), ("/settings/network", "network"), ("/settings/remote", "globe"),
            ("/settings/logs", "doc.text.magnifyingglass"), ("/settings/diagnoser", "stethoscope"), ("/settings/modules", "puzzlepiece.extension"),
            ("/settings/backup", "externaldrive"), ("/settings/data-folder", "folder"), ("/settings/repair", "wrench.and.screwdriver"),
            ("/settings/reset", "arrow.counterclockwise"), ("/settings/appearance", "paintbrush"), ("/markers", "film"), ("/canvas", "film"),
        ]
        return table.first { p.hasPrefix($0.0) }?.1 ?? "desktopcomputer"
    }
}
#endif
