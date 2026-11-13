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
        DesignPage(eyebrow: label.isEmpty ? "On your phone" : label,
                   title: "Open this on a phone or computer",
                   lead: ModulePageWords.lead(for: label, path: path),
                   foot: "Apple TV shows the library, the guide, games and music. This page needs a keyboard or a touch screen.",
                   identifier: "design.module") {
            ModuleCode(url: url)
        }
    }
}

private struct ModuleCode: View {
    @Environment(\.palette) private var palette
    @Environment(\.designSizes) private var sizes
    let url: URL

    var body: some View {
        HStack(alignment: .center, spacing: sizes.gap2) {
            if let image = QRImage.make(for: url.absoluteString) {
                QRCard(image: image, caption: "Scan with a phone's camera")
            }
            Text(url.absoluteString)
                .font(.system(size: sizes.body, weight: .semibold))
                .foregroundStyle(palette.accentText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, sizes.gap2)
    }
}
#endif
