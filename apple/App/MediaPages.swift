// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// What the server's "media extras" add to a title's page and to You (docs/CLIENT-API.md, "Media extras"):
//
// - Where to watch: this title in the library, next to the services that offer it, with the source's credit.
// - An administrator's tools: have a canvas cut from the video or remove it, see the skip markers the server
//   found and where each came from, and look for a show's intros by ear. Each is a task on the server: it's
//   followed here to its end, in the server's words, and the page then shows what changed.
// - You, On this device: which parts of a video are skipped by themselves, and whether canvases play.

// MARK: - Following a task

/// Something the server was asked to make, followed to its end: its progress in words while it runs, then what
/// came of it or what went wrong.
@MainActor
final class MediaJob: ObservableObject {
    @Published private(set) var words = ""
    @Published private(set) var problem = ""
    @Published private(set) var result = ""
    @Published private(set) var busy = false
    private var task: Task<Void, Never>?

    /// Asks for it, then follows its task. `start` answers nil when there's no task: the thing is already done.
    /// `stillGoing` asks the thing itself whether a task is still making it, for accounts that can't see tasks.
    func run(_ doing: String, client: WittyClient, start: @escaping () async throws -> MediaJobStart?,
             stillGoing: @escaping (String) async -> Bool? = { _ in nil }, finishedWords: String = "", done: @escaping () async -> Void) {
        guard !busy else { return }
        busy = true
        problem = ""
        result = ""
        words = "\(doing)…"
        task = Task { [weak self] in
            do {
                let started = try await start()
                guard let self, !Task.isCancelled else { return }
                if let id = started?.task, !id.isEmpty {
                    await self.watch(id, doing: doing, client: client, stillGoing: stillGoing, finishedWords: finishedWords, done: done)
                } else {
                    await done()
                    self.end(result: finishedWords)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.end(problem: plainWords(Problem.of(error)))
            }
        }
    }

    /// One that was already being made when the page opened.
    func follow(_ id: String, doing: String, client: WittyClient, stillGoing: @escaping (String) async -> Bool? = { _ in nil },
                finishedWords: String = "", done: @escaping () async -> Void) {
        guard !busy, !id.isEmpty else { return }
        busy = true
        words = "\(doing)…"
        task = Task { [weak self] in
            await self?.watch(id, doing: doing, client: client, stillGoing: stillGoing, finishedWords: finishedWords, done: done)
        }
    }

    private func watch(_ id: String, doing: String, client: WittyClient, stillGoing: (String) async -> Bool?, finishedWords: String,
                       done: () async -> Void) async {
        var unseen = 0
        while !Task.isCancelled {
            var state = MediaJobState.of(task: id, in: try? await client.activity())
            if state == .unknown {
                // Not in the lists: ask the thing itself, and don't wait for ever on something nobody can see.
                unseen += 1
                if let going = await stillGoing(id) {
                    if !going { state = .done(result: "") }
                } else if unseen > 40 {
                    state = .done(result: "")
                }
            }
            guard !Task.isCancelled else { return }
            switch state {
            case .done(let said):
                await done()
                end(result: said.isEmpty ? finishedWords : said)
                return
            case .failed(let why):
                await done()
                end(problem: why)
                return
            case .stopped:
                await done()
                end(result: "It was stopped.")
                return
            case .waiting, .running, .unknown:
                words = state.progressWords(doing)
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private func end(result: String = "", problem: String = "") {
        busy = false
        words = ""
        self.result = result
        self.problem = problem
        task = nil
        if !result.isEmpty { announce(result) } else if !problem.isEmpty { announce(problem) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        busy = false
        words = ""
    }
}

// MARK: - Parts

/// A heading inside a title's page: the website's 17 semibold on a phone and a tablet, a TV's section title there.
private struct MediaHeading: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let words: String

    var body: some View {
        if metrics.tv {
            SectionTitle(words)
        } else {
            Text(words)
                .font(.wm(size: 17, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

private struct MediaLine: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let words: String
    var hint = false

    var body: some View {
        Text(words)
            .font(metrics.tv ? .wmSecondary : .system(size: hint ? 12 : 14))
            .foregroundStyle(hint ? palette.textHint : palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    /// A page's quiet button: the website's Secondary on a phone and a tablet, Apple TV's own there.
    @ViewBuilder func mediaButton(tv: Bool) -> some View {
        if tv { action() } else { pageButton(.secondary) }
    }
}

/// What a job is doing, what came of it, or what went wrong.
private struct MediaJobLines: View {
    @ObservedObject var job: MediaJob

    var body: some View {
        if job.busy {
            HStack(spacing: Tokens.Space.s2) {
                ProgressView()
                MediaLine(words: job.words)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("media-job-progress")
        }
        if !job.problem.isEmpty { ProblemLine(job.problem).accessibilityIdentifier("media-job-problem") }
        if !job.result.isEmpty { MediaLine(words: job.result).accessibilityIdentifier("media-job-result") }
    }
}

// MARK: - Where to watch

/// One service: its logo where the source has one, and its name.
private struct ProviderTile: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let provider: WhereToWatch.Provider

    var body: some View {
        let side: CGFloat = metrics.tv ? 56 : 36
        HStack(spacing: Tokens.Space.s2) {
            if let logo = WhereToWatchLook.logo(provider) {
                AsyncImage(url: logo) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    palette.border
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
                .accessibilityHidden(true)
            }
            Text(provider.name)
                .font(metrics.tv ? .body : .system(size: 14, weight: .medium))
                .foregroundStyle(palette.text)
                .lineLimit(1)
        }
        .padding(.leading, WhereToWatchLook.logo(provider) == nil ? Tokens.Space.s3 : Tokens.Space.s1)
        .padding(.trailing, Tokens.Space.s3)
        .frame(minHeight: side + Tokens.Space.s2)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
    }
}

/// "Where to watch": what the library has, then the services by how they offer it. Shown only when the source
/// knows of any; with no key on the server or nothing known, the page stays as it was.
struct WhereToWatchSection: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.openURL) private var openURL
    let answer: WhereToWatch

    var body: some View {
        let rows = WhereToWatchLook.rows(answer)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                MediaHeading(words: "Where to watch")
                let here = WhereToWatchLook.libraryLine(answer)
                if !here.isEmpty {
                    Label(here, systemImage: "checkmark.circle.fill")
                        .font(metrics.tv ? .body : .system(size: 14, weight: .medium))
                        .foregroundStyle(palette.text)
                        .accessibilityIdentifier("watch-in-library")
                    ForEach(WhereToWatchLook.versionLines(answer), id: \.self) { MediaLine(words: $0) }
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        MediaLine(words: row.heading)
                        TitleWrapRow(spacing: Tokens.Space.s2, rowSpacing: Tokens.Space.s2) {
                            ForEach(row.providers, id: \.name) { ProviderTile(provider: $0) }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.heading): \(row.providers.map(\.name).joined(separator: ", "))")
                    .accessibilityIdentifier("watch-\(row.id)")
                }
                #if os(iOS) || os(visionOS)
                // Apple TV has no browser to open the offers in: the names are what it shows.
                if let link = WhereToWatchLook.link(answer) {
                    Button { openURL(link) } label: { Label("See the offers", systemImage: "arrow.up.right.square") }
                        .pageButton(.secondary)
                        .accessibilityHint("Opens the offers page in the browser")
                        .accessibilityIdentifier("watch-link")
                }
                #endif
                let credit = [WhereToWatchLook.regionWords(answer), answer.attribution.map { PlainWords.clean($0, limit: 200) } ?? ""].filter { !$0.isEmpty }
                if !credit.isEmpty { MediaLine(words: credit.joined(separator: ". "), hint: true).accessibilityIdentifier("watch-credit") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - On a title's page

/// Under an item's facts: where to watch it, and for an administrator its canvas and skip markers.
struct MediaItemExtras: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics
    let item: Item
    @State private var watch: WhereToWatch?
    @State private var canvas: CanvasInfo?
    @State private var markers: SkipMarkers?
    @StateObject private var job = MediaJob()

    private var isAdmin: Bool { model.user?.isAdmin == true }
    private var isVideo: Bool { item.kind == "video" }
    private var hasPicture: Bool { isVideo || TitleLook.isDisc(item) }

    private func load() async {
        let id = item.id
        if model.has(MediaFeature.whereToWatch), hasPicture { watch = try? await client.whereToWatch(item: id) }
        guard isAdmin else { return }
        if model.has(MediaFeature.canvas), hasPicture { canvas = try? await client.canvas(item: id) }
        if model.has(MediaFeature.markers), isVideo { markers = try? await client.markers(item: id) }
        // One was being made when the page opened: its progress belongs here too.
        if let going = canvas?.task, !going.isEmpty { followCanvas(going) }
    }

    private func refreshCanvas() async {
        canvas = try? await client.canvas(item: item.id)
        CanvasWatch.shared.changes += 1
    }

    private func stillMaking(_ task: String) async -> Bool? {
        guard let now = try? await client.canvas(item: item.id) else { return nil }
        return now.task == task
    }

    private func followCanvas(_ task: String) {
        let client = client
        job.follow(task, doing: "Making a canvas", client: client, stillGoing: { await stillMaking($0) },
                   finishedWords: "The canvas is ready.", done: { await refreshCanvas() })
    }

    private func makeCanvas() {
        let client = client, id = item.id
        job.run("Making a canvas", client: client, start: { try await client.generateCanvas(item: id) },
                stillGoing: { await stillMaking($0) }, finishedWords: "The canvas is ready.", done: { await refreshCanvas() })
    }

    private func removeCanvas() {
        let client = client, id = item.id
        job.run("Removing the canvas", client: client, start: { try await client.removeCanvas(item: id); return nil },
                finishedWords: "The canvas was removed.", done: { await refreshCanvas() })
    }

    @ViewBuilder private var tools: some View {
        let canMake = canvas?.canGenerate == true && model.has(MediaFeature.canvasGenerate)
        let lines = SkipRules.summary(markers)
        if canvas != nil || !lines.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                if let canvas {
                    MediaHeading(words: "Canvas")
                    MediaLine(words: canvas.available == true ? "\(canvas.sourceWords). It loops behind this page."
                                : (canvas.refusalWords.isEmpty ? "This title has no canvas: a short silent video to loop behind its page." : canvas.refusalWords))
                        .accessibilityIdentifier("canvas-status")
                    if canMake || canvas.removable {
                        HStack(spacing: Tokens.Space.s2) {
                            if canMake {
                                Button { makeCanvas() } label: {
                                    Label(canvas.available == true ? "Make another from the video" : "Make one from the video", systemImage: "film")
                                }
                                .mediaButton(tv: metrics.tv)
                                .accessibilityIdentifier("canvas-make")
                            }
                            if canvas.removable {
                                Button { removeCanvas() } label: { Label("Remove canvas", systemImage: "trash") }
                                    .mediaButton(tv: metrics.tv)
                                    .accessibilityIdentifier("canvas-remove")
                            }
                        }
                        .disabled(job.busy)
                        .remoteSection()
                    }
                    MediaJobLines(job: job)
                }
                if !lines.isEmpty {
                    MediaHeading(words: "Skip markers")
                    ForEach(lines, id: \.self) { MediaLine(words: $0) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s5) {
            if let watch { WhereToWatchSection(answer: watch) }
            if isAdmin { tools }
        }
        .task(id: item.id) { await load() }
        .onDisappear { job.cancel() }
    }
}

/// On a show's page: where to watch it, and for an administrator "Find intros and credits".
struct MediaShowExtras: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics
    let show: Int64
    /// Any episode of it: the server answers for the show an episode belongs to.
    let episode: Int64?
    @State private var watch: WhereToWatch?
    @StateObject private var job = MediaJob()

    private var isAdmin: Bool { model.user?.isAdmin == true }

    private func findIntros() {
        let client = client, show = show
        job.run("Finding intros and credits", client: client, start: { try await client.detectIntros(show: show) },
                finishedWords: "Finished looking for intros and credits.", done: {})
    }

    var body: some View {
        let detects = isAdmin && model.has(MediaFeature.introDetection)
        VStack(alignment: .leading, spacing: Tokens.Space.s5) {
            if let watch { WhereToWatchSection(answer: watch) }
            if detects {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    MediaHeading(words: "Intros and credits")
                    MediaLine(words: "The server can find them by ear: it compares the sound of a season's episodes and marks what they share, for Skip intro and Skip credits.")
                    Button { findIntros() } label: { Label("Find intros and credits", systemImage: "waveform.badge.magnifyingglass") }
                        .mediaButton(tv: metrics.tv)
                        .disabled(job.busy)
                        .accessibilityIdentifier("intros-find")
                    MediaJobLines(job: job)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: "\(show)|\(episode ?? 0)") {
            guard model.has(MediaFeature.whereToWatch), let episode else { return }
            watch = try? await client.whereToWatch(item: episode)
        }
        .onDisappear { job.cancel() }
    }
}

// MARK: - You

/// You, On this device: which parts of a video are skipped by themselves, and whether canvases play.
struct MediaSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @ObservedObject private var canvases = CanvasWatch.shared
    @State private var prefs = SkipPrefs.load()
    @State private var moving = CanvasWatch.shared.wanted
    @Namespace private var scope

    private func toggle(_ title: String, _ on: Binding<Bool>, id: String, first: Bool = false) -> some View {
        Toggle(isOn: on) {
            Text(title).font(.subheadline).foregroundStyle(palette.text)
        }
        .tint(palette.accent)
        .padding(.horizontal, Tokens.Space.s4)
        .frame(minHeight: 52)
        .firstFocus(in: scope, when: first)
        .accessibilityIdentifier(id)
    }

    private func skip(_ kind: SkipKind) -> Binding<Bool> {
        Binding(get: { prefs.skips(kind) }, set: { on in
            prefs.set(kind, on)
            SkipPrefs.save(prefs)
        })
    }

    var body: some View {
        let standing = CanvasRules.words(CanvasRules.standing(canvases.conditions(server: model.client.base)))
        SettingsScreen(title: "Skipping and moving pictures", detail: "Kept on this device, for every profile that uses it.") {
            ListGroup(title: "Skip by itself",
                      footer: "A part is skipped once, as the video plays into it, and for a moment there's a way back. Going back into a part plays it. Where nothing is switched on, the Skip button is still there.") {
                ForEach(Array(SkipKind.allCases.enumerated()), id: \.element) { index, kind in
                    toggle(kind.settingName, skip(kind), id: "auto-skip-\(kind.rawValue)", first: index == 0)
                }
            }
            if model.has(MediaFeature.canvas) {
                ListGroup(title: "Moving pictures",
                          footer: standing.isEmpty
                              ? "A canvas is a short silent video that loops behind the music player and on some pages. It stays still in Low Power Mode, with Reduce Motion, on mobile data and away from the server's own network."
                              : standing) {
                    toggle("Play canvases", Binding(get: { moving }, set: { on in
                        moving = on
                        canvases.wanted = on
                    }), id: "canvas-wanted")
                }
            }
        }
        .focusRoot(scope)
        .onAppear { canvases.watch() }
        .onDisappear { canvases.stop() }
    }
}

// MARK: - For the UI tests

#if DEBUG
extension AppModel {
    /// In debug builds, with `-WMCServer`: `-WMCOpen item:5`, `show:1`, `player:5`, `album:3:Album:Artist`,
    /// `settings`, or `song:9` (plays the song and opens the music player) goes straight to that screen, so a UI
    /// test doesn't depend on what Home happens to show.
    func openForMediaTests() {
        guard let wanted = UserDefaults.standard.string(forKey: "WMCOpen") else { return }
        let parts = wanted.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let number = parts.count > 1 ? Int64(parts[1]) : nil
        switch (parts.first ?? "", number) {
        case ("item", let id?): path.append(.item(id))
        case ("show", let id?): path.append(.show(id))
        case ("player", let id?): path.append(.player(id, startOver: true))
        case ("album", let library?) where parts.count >= 4:
            path.append(.listeningAlbum(library: library, album: parts[2], artist: parts[3]))
        case ("settings", _): path.append(.mediaExtras)
        case ("song", let id?):
            let client = client
            Task {
                guard let song = try? await client.item(id) else { return }
                listening.play([song], start: ListeningStart(0), keepsPlace: false, client: client)
                listening.screenShown = true
            }
        default: break
        }
    }
}
#endif
