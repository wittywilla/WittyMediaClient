#if os(tvOS)
import SwiftUI
import WittyKit

// Recordings and series, as the server's page lists them (web/src/pages/tv/RecordingsPage.tsx), in
// the account's WittyTV look. What's recorded lands in a library the server's owner chose, which is
// where it's played from: Play finds it there.

struct RecordingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @ObservedObject private var looks = TvLookStore.shared
    @State private var list: [Recording]?
    @State private var rules: [RecordingRule] = []
    @State private var error = ""
    @State private var asking: Asking?
    @State private var note = ""
    @Namespace private var scope

    /// What's being asked before something goes.
    struct Asking: Identifiable {
        let recording: Recording
        let deleteFile: Bool
        var id: String { "\(recording.id)|\(deleteFile)" }
    }

    private var dress: TvDress { looks.dress }

    var body: some View {
        let p = dress.paint
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 16) {
                    Text("Recordings").font(dress.font(30, .bold)).foregroundStyle(p.accent).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Back to the guide") { back() }.buttonStyle(TvButtonStyle(dress: dress))
                }
                .padding(.bottom, 12)
                if !error.isEmpty { Text(error).font(dress.font(21.25, .bold)).foregroundStyle(p.err) }
                if let list {
                    if list.isEmpty {
                        Text("Nothing recorded yet. Highlight a show on a Live TV channel in the guide, hold Select and choose Record this.")
                            .font(dress.font(21.25)).foregroundStyle(p.soft)
                    }
                    VStack(spacing: 16) {
                        ForEach(list) { r in recordingRow(r) }
                    }
                    .padding(.vertical, 8)
                } else if error.isEmpty {
                    LoadingView()
                }
                if !rules.isEmpty {
                    Text("Series").font(dress.font(21.25, .bold)).foregroundStyle(p.accent).padding(.top, 20).padding(.bottom, 8)
                    VStack(spacing: 16) {
                        ForEach(rules) { rule in ruleRow(rule) }
                    }
                }
                Text("Recordings are of Live TV channels only. Library channels play what is already in your library. Protected broadcasts are never recorded.")
                    .font(dress.font(16.25)).foregroundStyle(p.soft).padding(.top, 18)
            }
            .padding(.top, dress.top + 16)
            .padding(.horizontal, dress.edge)
            .padding(.bottom, Tokens.Space.s6 + dress.foot)
        }
        // The tabs are hidden here, so the page starts where the page's own top is.
        .ignoresSafeArea(.container, edges: .top)
        .focusRoot(scope)
        .toolbar(.hidden, for: .tabBar)
        .background(p.bg.ignoresSafeArea())
        .environment(\.colorScheme, dress.look.bgIsDark ? .dark : .light)
        .task {
            await looks.load(client: client, themeId: model.effectiveThemeId, app: model.tvAppColours)
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
        .alert("Not in a library yet", isPresented: Binding(get: { !note.isEmpty }, set: { if !$0 { note = "" } })) {
            Button("OK") { note = "" }
        } message: {
            Text(note)
        }
        .alert(item: $asking) { a in
            let r = a.recording
            if a.deleteFile {
                return Alert(title: Text("Delete the recording of “\(r.title)”?"), message: Text("Its file goes too. This can’t be undone."),
                             primaryButton: .destructive(Text("Delete recording")) { remove(r, deleteFile: true) }, secondaryButton: .cancel())
            }
            if r.isFinished {
                return Alert(title: Text("Remove “\(r.title)” from this list?"), message: Text("Any file it made stays where it is."),
                             primaryButton: .default(Text("Remove from list")) { remove(r, deleteFile: false) }, secondaryButton: .cancel())
            }
            return Alert(title: Text("Cancel the recording of “\(r.title)”?"), message: nil,
                         primaryButton: .destructive(Text("Cancel recording")) { remove(r, deleteFile: false) }, secondaryButton: .cancel(Text("Keep recording")))
        }
    }

    private func back() {
        if model.path.last == .recordings { model.path.removeLast() }
        if !model.path.contains(.guide) { model.path.append(.guide) }
    }

    private func recordingRow(_ r: Recording) -> some View {
        let p = dress.paint
        let size = r.sizeWords
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(dress.font(25, .bold)).foregroundStyle(p.text)
                if let sub = r.sub, !sub.isEmpty { Text(sub).font(dress.font(21.25, .bold)).foregroundStyle(p.accent) }
                Text("\(GuideRules.dayName(r.start)), \(GuideRules.span(r.start, r.stop)) · Channel \(r.number ?? "") \(r.channel)" + (size.isEmpty ? "" : " · " + size))
                    .font(dress.font(18.75)).foregroundStyle(p.soft)
                if let e = r.error, !e.isEmpty { Text(e).font(dress.font(18.75, .bold)).foregroundStyle(p.err) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(r.statusWords).font(dress.font(18.75, .bold)).foregroundStyle(r.status == "recording" ? p.accent : p.text)
            if r.status == "done" {
                Button { play(r) } label: { Label("Play", systemImage: "play.fill") }.buttonStyle(TvButtonStyle(dress: dress, on: true))
            }
            Button(r.isFinished ? "Remove" : "Cancel") { asking = Asking(recording: r, deleteFile: false) }.buttonStyle(TvButtonStyle(dress: dress))
            if model.user?.isAdmin == true, r.path?.isEmpty == false, r.status != "recording", r.status != "scheduled" {
                Button("Delete file") { asking = Asking(recording: r, deleteFile: true) }.buttonStyle(TvButtonStyle(dress: dress))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: dress.radius).fill(p.panel))
        .overlay(RoundedRectangle(cornerRadius: dress.radius).strokeBorder(p.line, lineWidth: 1))
        .overlay { if dress.bevel { Bevel() } }
        .focusSection()
    }

    private func ruleRow(_ rule: RecordingRule) -> some View {
        let p = dress.paint
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title).font(dress.font(25, .bold)).foregroundStyle(p.text)
                Text("Every airing on \(rule.channel)").font(dress.font(18.75)).foregroundStyle(p.soft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Stop") { stop(rule) }.buttonStyle(TvButtonStyle(dress: dress))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: dress.radius).fill(p.panel))
        .overlay(RoundedRectangle(cornerRadius: dress.radius).strokeBorder(p.line, lineWidth: 1))
        .focusSection()
    }

    private func load() async {
        do {
            list = try await client.recordings()
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
        rules = (try? await client.recordingRules()) ?? rules
    }

    private func remove(_ r: Recording, deleteFile: Bool) {
        Task {
            do { try await client.removeRecording(r.id, deleteFile: deleteFile); await load() }
            catch { self.error = (error as? APIError)?.message ?? "That didn't work. Try again." }
        }
    }

    private func stop(_ rule: RecordingRule) {
        Task {
            do { try await client.removeRecordingRule(rule.id); await load() }
            catch { self.error = (error as? APIError)?.message ?? "That didn't work. Try again." }
        }
    }

    /// A finished recording is a file in a library once the server has looked at it again: it's
    /// found there by its title and the time it was made, which its file name holds.
    private func play(_ r: Recording) {
        Task {
            note = ""
            let found = (try? await client.search(r.title))?.items ?? []
            let stamp = { () -> String in
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH.mm"
                return f.string(from: Date(timeIntervalSince1970: TimeInterval(r.start)))
            }()
            let best = found.first { $0.title.contains(stamp) } ?? found.first { $0.title.hasPrefix(r.title) && $0.kind != "audio" }
            if let best {
                model.path.append(.player(best.id, startOver: true))
            } else {
                note = "A recording is played from the library it lands in. It shows up there once this server's owner sets a library for recordings, under Live TV options, and that library has been looked at again."
            }
        }
    }
}

/// A reminder coming due, on whatever screen is showing: watch the channel, or let it go.
struct TvReminderAlert: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @ObservedObject private var reminders = TvReminders.shared

    func body(content: Content) -> some View {
        content
            .task(id: model.user?.id) { if model.user != nil { await reminders.load(client: client) } }
            .alert(item: $reminders.due) { r in
                let started = r.start <= Int64(Date().timeIntervalSince1970)
                return Alert(title: Text(r.title + (started ? " has started" : " is about to start")), message: r.sub.map { Text($0) },
                             primaryButton: .default(Text("Watch")) {
                                 reminders.dismiss(r)
                                 model.path.append(.channel(key: r.channel))
                             },
                             secondaryButton: .cancel(Text("Dismiss")) { reminders.dismiss(r) })
            }
    }
}
#endif
