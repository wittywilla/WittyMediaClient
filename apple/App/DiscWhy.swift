// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import UIKit
import WittyKit

// "Why this title" on a disc's page, as the website's DiscWhy.tsx: which title (DVD) or playlist (Blu-ray) is the
// film, why, and how sure the disc's engine is, with how it decided; a TV disc's episodes and the film's other
// versions; and for an administrator, another title as the film for everyone, the engine's pick again, and the
// ranking worked out again. Only with a server that has `disc-ranking`; an encrypted disc keeps the page's own
// notice and shows none of this. The words and the addresses are WittyKit's DiscRanking.

struct DiscWhy: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let item: Int64
    /// Episodes and versions open the server's disc player, which isn't on Apple TV.
    let playable: Bool
    /// How far below what comes before its heading is.
    var top: CGFloat = Tokens.Space.s6
    /// The film has changed: the page's own sections follow it.
    var changed: (Int) -> Void = { _ in }

    @State private var analysis: DiscAnalysis?
    @State private var gaveUp = false
    @State private var busy = ""
    @State private var said = ""
    @State private var problem = ""
    @State private var decided = false
    @State private var choosing = false
    @State private var confirmClear = false

    private var admin: Bool { model.user?.isAdmin == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.has(DiscRanking.feature), let analysis, !analysis.protected, analysis.rank?.protected != true {
                content(analysis)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: item) { await load() }
        .confirmationDialog(DiscRanking.clearTitle, isPresented: $confirmClear, titleVisibility: .visible) {
            Button(DiscRanking.clearButton) { clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let analysis { Text(DiscRanking.clearMessage(analysis)) }
        }
    }

    // MARK: Asking

    /// A ranking still being worked out is asked for again a few seconds later, a few times; a disc the server has
    /// no ranking for, or can't read, shows nothing here.
    private func load() async {
        guard model.has(DiscRanking.feature) else { return }
        gaveUp = false
        for attempt in 0..<DiscRanking.pendingTries {
            if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(DiscRanking.pendingWait * 1_000_000_000)) }
            if Task.isCancelled { return }
            guard let fresh = try? await client.discAnalysis(item) else { return }
            take(fresh)
            if !fresh.pending { return }
        }
        if !Task.isCancelled { gaveUp = true }
    }

    private func take(_ fresh: DiscAnalysis) {
        let before = analysis?.main
        analysis = fresh
        if let before, before != fresh.main { changed(fresh.main) }
    }

    /// An administrator's change: what the server answers takes the place of what's shown, and it's said aloud.
    private func run(_ what: String, done: String, _ work: @escaping () async throws -> DiscAnalysis) {
        busy = what
        said = ""
        problem = ""
        Task {
            do {
                take(try await work())
                choosing = false
                said = done
                UIAccessibility.post(notification: .announcement, argument: done)
            } catch {
                problem = model.handle(error)
            }
            busy = ""
        }
    }

    private func choose(_ ttn: Int, _ a: DiscAnalysis) {
        run("choose", done: DiscRanking.chosenToast(ttn, a)) { try await client.chooseDiscTitle(item, ttn: ttn) }
    }

    private func clear() {
        run("clear", done: DiscRanking.clearedToast) { try await client.clearDiscChoice(item) }
    }

    private func again(secondOpinion: Bool) {
        run(secondOpinion ? "second" : "again", done: secondOpinion ? DiscRanking.secondOpinionToast : DiscRanking.againToast) {
            try await client.rankDiscAgain(item, secondOpinion: secondOpinion)
        }
    }

    // MARK: Drawing

    private func face(_ size: CGFloat, _ weight: Font.Weight = .regular, tv: Font) -> Font {
        metrics.tv ? tv.weight(weight) : .system(size: size, weight: weight)
    }

    /// The disc page's `.section-title`: 20 semibold (17 inside a section), 12 above what it names.
    private func heading(_ words: String, top: CGFloat, size: CGFloat = 20) -> some View {
        Text(words)
            .font(face(size, .semibold, tv: size >= 20 ? .wmSection : .wmCard))
            .foregroundStyle(palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, top)
            .padding(.bottom, Tokens.Space.s3)
    }

    private func line(_ words: String, quiet: Bool = false) -> some View {
        Text(words)
            .font(face(14, tv: .wmSecondary))
            .lineSpacing(3)
            .foregroundStyle(quiet ? palette.textSecondary : palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ words: String) -> some View {
        Text(words)
            .font(face(11, .semibold, tv: .wmCardSub))
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, Tokens.Space.s2)
            .frame(minHeight: 20)
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).strokeBorder(palette.text.opacity(0.2), lineWidth: 1))
    }

    @ViewBuilder private func content(_ a: DiscAnalysis) -> some View {
        // Inside Feature Presentation on a phone and a tablet, as the website's `h3`; a section of its own on a TV.
        heading(DiscRanking.heading(a), top: top, size: metrics.tv ? 20 : 17)
        if a.pending && a.rank == nil {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Text(DiscRanking.pendingTitle).font(face(14, .semibold, tv: .wmLabel)).foregroundStyle(palette.text)
                line(gaveUp ? DiscRanking.pendingGaveUp : DiscRanking.pendingLine, quiet: true)
            }
            .discReadable()
            .accessibilityElement(children: .combine)
        } else if let rank = a.rank, a.ranked {
            summary(a, rank)
            howDecided(a)
            if a.canChoose && admin { adminActions(a) }
            episodes(a, rank)
            versions(a, rank)
        } else {
            line(DiscRanking.unrankedLine(a), quiet: true).discReadable()
            if a.chosen != nil { chosen(a).padding(.top, Tokens.Space.s2) }
        }
        if !said.isEmpty { line(said, quiet: true).padding(.top, Tokens.Space.s3).accessibilityHidden(true) }
        if !problem.isEmpty { ProblemLine(problem).padding(.top, Tokens.Space.s3) }
    }

    /// The pill and the engine's sentence, or who chose what plays.
    @ViewBuilder private func summary(_ a: DiscAnalysis, _ rank: DiscRank) -> some View {
        if a.chosen != nil {
            chosen(a)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
                pill(DiscRanking.confidence(rank))
                line(DiscRanking.why(a) + " (\(DiscRanking.sure(rank.confidence)))")
            }
            .discReadable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DiscRanking.summaryLabel(a))
        }
    }

    @ViewBuilder private func chosen(_ a: DiscAnalysis) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
                pill("Chosen")
                line(DiscRanking.chosenLine(a) ?? "")
            }
            .discReadable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DiscRanking.summaryLabel(a))
            if a.canChoose && admin {
                Button(DiscRanking.clearButton) { confirmClear = true }
                    .discButton(.ghost)
                    .disabled(!busy.isEmpty)
                    .accessibilityHint(DiscRanking.clearMessage(a))
            }
        }
    }

    /// "How the engine decided", which opens what's under it, as the website's `<details>`.
    @ViewBuilder private func howDecided(_ a: DiscAnalysis) -> some View {
        let parts = DiscRanking.details(a)
        if !parts.isEmpty {
            Button { decided.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: metrics.tv ? 14 : 8))
                        .rotationEffect(.degrees(decided ? 90 : 0))
                        .accessibilityHidden(true)
                    Text("How the engine decided")
                }
                .font(face(14, .semibold, tv: .wmLabel))
                .foregroundStyle(palette.textSecondary)
                .padding(.vertical, Tokens.Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(decided ? "Expanded" : "Collapsed")
            .padding(.top, Tokens.Space.s2)
            if decided {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                            if !part.heading.isEmpty {
                                Text(part.heading)
                                    .font(face(14, .semibold, tv: .wmLabel))
                                    .foregroundStyle(palette.text)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(Array(part.lines.enumerated()), id: \.offset) { _, words in
                                line((part.heading.isEmpty ? "" : "• ") + words, quiet: part.heading.isEmpty)
                                    .accessibilityLabel(words)
                            }
                        }
                        .discReadable()
                    }
                }
                .padding(.leading, Tokens.Space.s4)
            }
        }
    }

    /// An administrator's: another title as the film, and the ranking again.
    @ViewBuilder private func adminActions(_ a: DiscAnalysis) -> some View {
        let others = DiscRanking.others(a)
        let unit = DiscRanking.unit(a).lowercased()
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            TitleWrapRow(spacing: Tokens.Space.s2, rowSpacing: Tokens.Space.s2) {
                if !others.isEmpty {
                    Button { choosing.toggle() } label: { Label("Another \(unit)", systemImage: choosing ? "chevron.up" : "chevron.down") }
                        .discButton(.secondary)
                        .disabled(!busy.isEmpty)
                        .accessibilityLabel("Another \(unit) to play as the film")
                        .accessibilityValue(choosing ? "Expanded" : "Collapsed")
                }
                Button(DiscRanking.againButton) { again(secondOpinion: false) }
                    .discButton(.ghost)
                    .disabled(!busy.isEmpty)
                    .accessibilityHint("Works out again which \(unit) is the film")
                if DiscRanking.offersSecondOpinion(a) {
                    Button(DiscRanking.secondOpinionButton) { again(secondOpinion: true) }
                        .discButton(.ghost)
                        .disabled(!busy.isEmpty)
                        .accessibilityHint("Asks libbluray on the server how it reads this disc")
                }
                if !busy.isEmpty { ProgressView().accessibilityLabel("Working") }
            }
            .remoteSection()
            if choosing && !others.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    ForEach(others, id: \.ttn) { candidate in
                        Button { choose(candidate.ttn, a) } label: {
                            HStack(spacing: Tokens.Space.s3) {
                                Text(DiscRanking.candidateLabel(candidate, a))
                                    .font(face(14, tv: .wmLabel).monospacedDigit())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Make it the film").font(face(13, .semibold, tv: .wmLabel))
                            }
                        }
                        .discButton(.secondary, wide: true)
                        .disabled(!busy.isEmpty)
                        .accessibilityLabel(DiscRanking.chooseLabel(candidate, a))
                    }
                }
                .remoteSection()
            }
        }
        .padding(.top, Tokens.Space.s3)
    }

    /// A TV disc's episodes, each to play.
    @ViewBuilder private func episodes(_ a: DiscAnalysis, _ rank: DiscRank) -> some View {
        if !rank.episodes.isEmpty {
            heading("Episodes", top: Tokens.Space.s6, size: 17)
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                ForEach(rank.episodes, id: \.index) { episode in
                    playRow(DiscRanking.episodeLabel(episode), detail: DiscRanking.episodeDetail(episode, a),
                            path: DiscRanking.episodePath(item, episode))
                }
            }
            .remoteSection()
        }
    }

    /// The film's other versions, each to play.
    @ViewBuilder private func versions(_ a: DiscAnalysis, _ rank: DiscRank) -> some View {
        let others = DiscRanking.otherVersions(rank)
        if !others.isEmpty {
            heading("Other versions", top: Tokens.Space.s6, size: 17)
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                ForEach(Array(others.enumerated()), id: \.offset) { _, version in
                    playRow(DiscRanking.versionLabel(version, a), detail: TitleLook.clock(version.durationSec),
                            path: DiscRanking.versionPath(item, version))
                }
            }
            .remoteSection()
        }
    }

    /// Play and its words where the disc player is; the words alone elsewhere.
    @ViewBuilder private func playRow(_ name: String, detail: String, path: String) -> some View {
        HStack(spacing: Tokens.Space.s3) {
            if playable {
                Button { model.path.append(.page(path)) } label: { Label(name, systemImage: "play.fill") }
                    .discButton(.secondary)
                    .fixedSize()
                    .accessibilityLabel("Play \(name)")
                    .accessibilityHint(detail)
                line(detail, quiet: true).accessibilityHidden(true)
            } else {
                Text(name).font(face(14, .semibold, tv: .wmLabel)).foregroundStyle(palette.text)
                line(detail, quiet: true)
            }
        }
        .modifier(DiscReadableRow(active: !playable, label: "\(name), \(detail)"))
    }
}

/// The page's small buttons on a phone and a tablet; the TV's own on Apple TV, which show where focus is.
private struct DiscWhyButton: ViewModifier {
    @Environment(\.metrics) private var metrics
    let kind: PageButtonKind
    var wide = false

    @ViewBuilder func body(content: Content) -> some View {
        if metrics.tv {
            content.buttonStyle(ActionStyle(kind: kind == .primary ? .primary : .secondary, wide: wide))
        } else {
            content.buttonStyle(TitleSmallButtonStyle(kind: kind)).frame(maxWidth: wide ? .infinity : nil, alignment: .leading)
        }
    }
}

/// A row of words alone, which Apple TV's focus can reach so the page scrolls to it, read as one.
private struct DiscReadableRow: ViewModifier {
    let active: Bool
    let label: String

    @ViewBuilder func body(content: Content) -> some View {
        if active {
            content.discReadable().accessibilityElement(children: .ignore).accessibilityLabel(label)
        } else {
            content
        }
    }
}

private extension View {
    func discButton(_ kind: PageButtonKind, wide: Bool = false) -> some View { modifier(DiscWhyButton(kind: kind, wide: wide)) }

    /// Words Apple TV's focus can land on, so a remote scrolls the page to them; as they are elsewhere.
    @ViewBuilder func discReadable() -> some View {
        #if os(tvOS)
        self.focusable()
        #else
        self
        #endif
    }
}
