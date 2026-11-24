// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// The bell (the server's docs/NOTIFICATIONS.md): beside the activity button on an iPhone or iPad, and before You in
// Apple TV's bar, with how many notifications are unread; its list opens over the page. One small request a minute,
// and only while the bell is on screen.

@MainActor
final class NoteWatch: ObservableObject {
    static let shared = NoteWatch()
    @Published var unread = 0
    @Published var latest: Int64 = 0
    private var watchers = 0
    private var loop: Task<Void, Never>?

    func watch(_ client: WittyClient) {
        watchers += 1
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if let count = try? await client.noteCount() {
                    self?.unread = count.unread
                    self?.latest = count.latest
                }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
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
}

/// Where a notification leads in this app: a show's page, Apple TV's recordings, or the server's page.
func noteRoute(_ note: Note) -> Route? {
    if let show = NoteKinds.show(note.link) { return .show(show) }
    guard let path = NoteKinds.safeLink(note.link) else { return nil }
    if path.hasPrefix("/tv/recordings") { return .recordings }
    return .page(path)
}

private func noteLabel(_ unread: Int) -> String { unread > 0 ? "Notifications, \(unread) unread" : "Notifications" }

#if os(iOS) || os(visionOS)
/// The strip's bell: a 40 circle of the page colour at 70%, as the activity button is, with the count in the accent.
struct NotesButton: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @ObservedObject private var watch = NoteWatch.shared
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            ZStack {
                Circle().fill(palette.background.opacity(0.7))
                Image(systemName: "bell").font(.wm(size: 15, weight: .semibold))
                    .foregroundStyle(watch.unread > 0 ? palette.text : palette.textHint)
            }
            .frame(width: 40, height: 40)
            .overlay(alignment: .topTrailing) {
                if watch.unread > 0 {
                    Text(watch.unread > 99 ? "99+" : "\(watch.unread)").font(.wm(size: 11, weight: .bold).monospacedDigit())
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
        .accessibilityLabel(noteLabel(watch.unread))
        .sheet(isPresented: $open) { NotesSheet().presentationDetents([.medium, .large]) }
        .onAppear { watch.watch(client) }
        .onDisappear { watch.stop() }
    }
}
#endif

#if os(tvOS)
/// Apple TV's bell: a round pill before You, its count in the accent. The list opens over the tab.
struct TvNotesPill: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @ObservedObject private var watch = NoteWatch.shared
    @State private var open = false
    let height: CGFloat

    var body: some View {
        Button { open = true } label: {
            Image(systemName: "bell")
                .font(.wmLabel)
                .foregroundStyle(palette.textSecondary)
                .frame(width: height, height: height)
                .overlay(alignment: .topTrailing) {
                    if watch.unread > 0 {
                        Text(watch.unread > 99 ? "99+" : "\(watch.unread)").font(.system(size: 18, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.onAccent)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 30, minHeight: 30)
                            .background(Capsule().fill(palette.accent))
                    }
                }
        }
        .buttonStyle(SurfaceStyle(fill: nil, radius: 999))
        .accessibilityLabel(noteLabel(watch.unread))
        .fullScreenCover(isPresented: $open) { NotesSheet() }
        .onAppear { watch.watch(client) }
        .onDisappear { watch.stop() }
    }
}
#endif

/// The list: newest first, unread ones marked, each opening what it's about. On Apple TV there is nothing to change
/// here and no keys are shown: Back closes it.
struct NotesSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var watch = NoteWatch.shared
    @State private var notes: [Note]?
    @State private var more = false
    @State private var said = ""
    @State private var choices: [NoteChoice] = []

    private func load(older: Bool = false) async {
        do {
            let got = try await client.notes(before: older ? (notes?.last?.id ?? 0) : 0)
            let list = got.notes ?? []
            notes = older ? (notes ?? []) + list : list
            more = list.count == 30
            watch.unread = got.unread
            watch.latest = got.latest
        } catch { said = model.handle(error) }
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task { do { try await work() } catch { said = model.handle(error) } }
    }

    private func open(_ note: Note) {
        if !note.read {
            act {
                let c = try await client.markNotesRead([note.id])
                watch.unread = c.unread
                notes = notes?.map { $0.id == note.id ? Note(id: $0.id, kind: $0.kind, title: $0.title, body: $0.body, link: $0.link, at: $0.at, read: true) : $0 }
            }
        }
        if let route = noteRoute(note) {
            dismiss()
            model.path.append(route)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    if let notes, !notes.isEmpty {
                        HStack(spacing: Tokens.Space.s3) {
                            Button("Mark all read") { act { try await client.markNotesRead(); watch.unread = 0; await load() } }
                                .disabled(watch.unread == 0)
                            Button("Clear all") { act { try await client.clearNotes(); watch.unread = 0; self.notes = []; more = false } }
                        }
                    }
                    if !said.isEmpty { Text(said).foregroundStyle(palette.textSecondary) }
                    if let notes {
                        if notes.isEmpty {
                            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                                Text("Nothing new").font(.wm(size: 17, weight: .semibold)).foregroundStyle(palette.text)
                                Text("New episodes, finished recordings and updates show up here.").foregroundStyle(palette.textSecondary)
                            }
                        }
                        ForEach(notes) { note in row(note) }
                        if more { Button("Show more") { Task { await load(older: true) } } }
                    } else {
                        ProgressView()
                    }
                    #if !os(tvOS)
                    if !choices.isEmpty { choicesSection }
                    #endif
                }
                .padding(Tokens.Space.s4)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Notifications")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            #endif
        }
        .task {
            await load()
            #if !os(tvOS)
            choices = (try? await client.noteChoices()) ?? []
            #endif
        }
    }

    private func row(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s2) {
            Button { open(note) } label: {
                HStack(alignment: .top, spacing: Tokens.Space.s3) {
                    Circle().fill(note.read ? Color.clear : palette.accent).frame(width: 10, height: 10).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).font(.wm(size: 16, weight: note.read ? .medium : .semibold)).foregroundStyle(palette.text)
                        if let body = note.body, !body.isEmpty { Text(body).font(.wm(size: 14)).foregroundStyle(palette.textSecondary) }
                        Text(Date(timeIntervalSince1970: note.at), style: .relative).font(.wm(size: 12)).foregroundStyle(palette.textHint)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Tokens.Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(note.title + (note.body.map { ". " + $0 } ?? "") + (note.read ? "" : ", unread"))
            #if !os(tvOS)
            Button {
                act {
                    let c = try await client.clearNotes(note.id)
                    watch.unread = c.unread
                    notes = notes?.filter { $0.id != note.id }
                }
            } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(note.title)")
            #endif
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(note.read ? palette.border : palette.accent, lineWidth: 1))
    }

    #if !os(tvOS)
    private var choicesSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("What you're told about").font(.wm(size: 17, weight: .semibold)).foregroundStyle(palette.text).padding(.top, Tokens.Space.s4)
            ForEach(Array(choices.enumerated()), id: \.element.kind) { at, choice in
                let words = NoteKinds.names[choice.kind] ?? (choice.kind, "")
                Toggle(isOn: Binding(get: { choices[at].on }, set: { on in
                    choices[at].on = on
                    act { choices = try await client.setNoteChoices([NoteChoice(kind: choice.kind, on: on)]) }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(words.name).foregroundStyle(palette.text)
                        Text(words.about).font(.wm(size: 13)).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }
    #endif
}
