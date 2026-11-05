#if os(iOS) || os(visionOS)
import SwiftUI
import WittyKit

// The rest of the website's phone shell: the activity button at the right of the strip and its panel
// (components/ActivitySlot.tsx, ActivityPanel.tsx, activity.ts), and the line at the foot of every page (App.tsx,
// LegalNote, VersionTag).

// MARK: - Activity

/// What the server is busy with, asked for while a button shows it: every 3 seconds while something runs, every 20
/// when nothing does. The website keeps a stream open for this; asking now and then costs the server less here.
@MainActor
final class ActivityWatch: ObservableObject {
    static let shared = ActivityWatch()
    @Published private(set) var tasks: ActivityTasks?
    @Published private(set) var hidden = false
    @Published private(set) var connected = true
    private var watchers = 0
    private var loop: Task<Void, Never>?

    func watch(_ client: WittyClient) {
        watchers += 1
        guard loop == nil else { return }
        loop = Task { [weak self] in
            if let ui = try? await client.interfaceChoice("activityHidden", as: Bool.self) { self?.hidden = ui }
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let found = try await client.activity()
                    self.tasks = found
                    self.connected = true
                    if !found.shown { return }
                } catch {
                    if (error as? APIError)?.status == 403 { self.tasks = nil; return }
                    self.connected = false
                }
                let busy = (self.tasks?.busy ?? 0) > 0
                try? await Task.sleep(nanoseconds: busy ? 3_000_000_000 : 20_000_000_000)
            }
        }
    }

    func stop() {
        watchers = max(0, watchers - 1)
        if watchers == 0 {
            loop?.cancel()
            loop = nil
        }
    }

    /// Asked again at once, after a task was paused or the like.
    func refresh(_ client: WittyClient) async {
        if let found = try? await client.activity() { tasks = found }
    }

    func forget() {
        loop?.cancel()
        loop = nil
        watchers = 0
        tasks = nil
    }
}

/// A 40 circle of `background` at 70% at the right of the strip: an icon, a ring round it for how far along
/// everything is, and how many are running or waiting. Nothing for an account the owner hasn't given it to.
struct ActivityButton: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @ObservedObject private var watch = ActivityWatch.shared
    @State private var open = false

    var body: some View {
        Group {
            if let tasks = watch.tasks, tasks.shown, !watch.hidden {
                let busy = tasks.busy
                let percent = tasks.summary?.percent ?? -1
                Button { open = true } label: {
                    ZStack {
                        Circle().fill(palette.background.opacity(0.7))
                        if busy > 0 {
                            if percent >= 0 {
                                Circle().stroke(palette.border, lineWidth: 2.5).frame(width: 34, height: 34)
                                Circle().trim(from: 0, to: min(1, percent / 100)).stroke(palette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                    .rotationEffect(.degrees(-90)).frame(width: 34, height: 34)
                            } else {
                                ProgressView().scaleEffect(1.2)
                            }
                        }
                        Image(systemName: "waveform.path.ecg").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(busy > 0 ? palette.text : palette.textHint)
                    }
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) {
                        if busy > 0 {
                            Text("\(busy)").font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(palette.onAccent)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 17, minHeight: 17)
                                .background(Capsule().fill(palette.accent))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tasks.label())
                .sheet(isPresented: $open) { ActivitySheet().presentationDetents([.medium, .large]) }
            }
        }
        .onAppear { watch.watch(client) }
        .onDisappear { watch.stop() }
    }
}

/// The panel behind the button: what's going on, library by library, and what happened lately.
private struct ActivitySheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var watch = ActivityWatch.shared
    @State private var tab = "now"
    @State private var history: [ActivityTasks.Task]?
    @State private var failedOnly = false
    @State private var said = ""

    private var readOnly: Bool { watch.tasks?.access?.readOnly != false }

    private func act(_ task: ActivityTasks.Task, _ action: String) {
        Task {
            do {
                try await client.taskAction(task.id, action)
                await watch.refresh(client)
            } catch { said = model.handle(error) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    SegmentRow(choices: [("now", "Now\((watch.tasks?.tasks?.count ?? 0) > 0 ? " \(watch.tasks?.tasks?.count ?? 0)" : "")"), ("history", "History")],
                               chosen: tab, label: "Activity") { tab = $0 }
                    if !watch.connected { note("Reconnecting to the server. This may be out of date.") }
                    if readOnly { note("You can see what the server is doing here. Only an administrator can change it.") }
                    if !said.isEmpty { note(said) }
                    if tab == "now" { now } else { past }
                }
                .padding(Tokens.Space.s4)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if !readOnly {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Activity settings") {
                            dismiss()
                            model.path.append(.page("/settings/activity"))
                        }
                    }
                }
            }
        }
        .task(id: "\(tab)|\(failedOnly)|\(watch.tasks?.recent?.first?.id ?? "")") {
            guard tab == "history" else { return }
            history = try? await client.taskHistory(failed: failedOnly)
        }
    }

    private func note(_ words: String) -> some View {
        Text(words).font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            .padding(Tokens.Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
    }

    @ViewBuilder private var now: some View {
        let tasks = watch.tasks?.tasks ?? []
        if tasks.isEmpty {
            EmptyState(icon: "checkmark", title: "Nothing going on", detail: "Library scans and other background work show up here while they run.")
        } else {
            ForEach(ActivityTasks.grouped(tasks), id: \.name) { group in
                let known = group.tasks.compactMap { ($0.percent ?? -1) >= 0 ? $0.percent : nil }
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    HStack {
                        Text(group.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.text)
                        Spacer()
                        if !known.isEmpty { Text("\(Int((known.reduce(0, +) / Double(known.count)).rounded()))%").font(.system(size: 13).monospacedDigit()).foregroundStyle(palette.textSecondary) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(group.tasks) { task in live(task) }
                }
            }
        }
    }

    private func live(_ task: ActivityTasks.Task) -> some View {
        let percent = task.percent ?? -1
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title ?? "").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                    Text([task.by.map { "started by \($0)" }].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Text(task.stateWords).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
            if percent >= 0 {
                ProgressView(value: min(1, percent / 100)).tint(palette.accent)
            } else if task.state == "running" {
                ProgressView().progressViewStyle(.linear).tint(palette.accent)
            }
            if let phase = task.phase, !phase.isEmpty { Text(phase).font(.system(size: 12)).foregroundStyle(palette.textSecondary) }
            if !task.countWords.isEmpty { Text(task.countWords).font(.system(size: 12)).foregroundStyle(palette.textSecondary) }
            if let item = task.item, !item.isEmpty { Text(item).font(.system(size: 12)).foregroundStyle(palette.textHint).lineLimit(1) }
            if !readOnly, task.canPause == true || task.canResume == true || task.canCancel == true {
                HStack(spacing: Tokens.Space.s2) {
                    if task.canPause == true { Button { act(task, "pause") } label: { Label("Pause", systemImage: "pause.fill") }.pageButton(.secondary) }
                    if task.canResume == true { Button { act(task, "resume") } label: { Label("Resume", systemImage: "play.fill") }.pageButton(.secondary) }
                    if task.canCancel == true { Button { act(task, "cancel") } label: { Label("Cancel", systemImage: "stop.fill") }.pageButton(.ghost) }
                }
            }
        }
        .padding(Tokens.Space.s3)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
    }

    @ViewBuilder private var past: some View {
        HStack(spacing: Tokens.Space.s2) {
            Button("All") { failedOnly = false }.chip(chosen: !failedOnly)
            Button("Failed") { failedOnly = true }.chip(chosen: failedOnly)
        }
        if let history {
            if history.isEmpty {
                EmptyState(icon: "checkmark", title: failedOnly ? "Nothing has failed" : "No history yet",
                           detail: failedOnly ? "Anything that fails is listed here with what to do about it." : "Finished work is listed here.")
            } else {
                ForEach(history) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(task.title ?? "").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                            Spacer(minLength: 0)
                            Text(task.stateWords).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(task.state == "failed" ? palette.danger : palette.textSecondary)
                        }
                        if let result = task.result, !result.isEmpty { Text(result).font(.system(size: 12)).foregroundStyle(palette.textSecondary) }
                        if let error = task.error, !error.isEmpty {
                            Text(error).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.danger)
                            if let fix = task.fix, !fix.isEmpty { Text(fix).font(.system(size: 12)).foregroundStyle(palette.textSecondary) }
                        }
                        if !readOnly, task.canRetry == true {
                            Button { act(task, "retry") } label: { Label(task.type == "scan" ? "Scan again" : "Try again", systemImage: "arrow.clockwise") }
                                .pageButton(.secondary)
                        }
                    }
                    .padding(Tokens.Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, Tokens.Space.s6)
        }
    }
}

// MARK: - The foot of a page

/// The short legal notice and "WittyMediaServer 0.4.0 ALPHA", at the end of every page as the website's. A page with
/// a notice of its own (an album's "metadata", a podcast's "webMedia") shows that one instead of the general one.
struct PageFoot: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    var notice = "general"

    var body: some View {
        let version = VersionTag.parts(model.serverVersion)
        VStack(alignment: .leading, spacing: 28) {
            if let notice = model.legal?.notices[self.notice] {
                let link = model.legal?.linkText ?? "Legal"
                (Text(notice.text + " ") + Text(.init("[\(link)](wms://legal)")))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textHint)
                    .tint(palette.accentText)
                    .lineSpacing(3)
                    .environment(\.openURL, OpenURLAction { _ in
                        model.path.append(.page("/settings/legal" + ((notice.section ?? "").isEmpty ? "" : "#\(notice.section!)")))
                        return .handled
                    })
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Legal notice: \(notice.text)")
            }
            HStack(spacing: 6) {
                Text("WittyMediaServer \(version.number)").font(.system(size: 15)).foregroundStyle(palette.text)
                if !version.stage.isEmpty {
                    Text(version.stage).font(.system(size: 11, weight: .bold)).tracking(0.55)
                        .foregroundStyle(palette.accentText)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).fill(palette.accent.opacity(0.16)))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.top, 28)
    }
}
#endif
