// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// A server whose pages are written for another catalogue revision than this app draws (the server's docs/SDUI.md:
/// a client built for another revision refuses the document). There are no other screens to fall back to, so this
/// says what to do: update whichever of the two is older. The person can still try again, change server or reach
/// Settings from the menu.
struct SDUIRevisionMismatch: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    /// The server's catalogue revision, when it said.
    let server: Int?

    private var detail: String {
        guard let server else {
            return "This server's pages are written for another version of WittyMediaClient. Update the app, or the server, so they match."
        }
        return server > SDUI.catalog
            ? "This server is newer than this app (pages revision \(server), the app draws \(SDUI.catalog)). Update WittyMediaClient."
            : "This app is newer than the server (pages revision \(server), the app draws \(SDUI.catalog)). Update WittyMediaServer."
    }

    var body: some View {
        VStack(spacing: Tokens.Space.s5) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: metrics.tv ? 72 : 44, weight: .medium))
                .foregroundStyle(palette.accentText)
                .accessibilityHidden(true)
            EmptyMessage(title: "Update the app or the server", detail: detail)
            HStack(spacing: Tokens.Space.s3) {
                Button("Try again") { Task { await center.loadMenu(); center.changed() } }
                    .action(primary: true)
                    .accessibilityIdentifier("sdui.revision.retry")
                Button(say("changeServer")) { model.changeServer() }
                    .action()
            }
            .remoteSection()
        }
        .padding(Tokens.Space.s6)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sdui.revision")
    }
}
