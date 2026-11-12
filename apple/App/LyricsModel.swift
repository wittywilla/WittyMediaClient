// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// A song's words, shared by Lyrics, Read and karaoke, and asked for only when one of them is open (lyrics.ts).
@MainActor
final class LyricsModel: ObservableObject {
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var loading = false
    @Published private(set) var failed = ""
    @Published private(set) var offset = 0.0
    private var itemId: Int64?
    private var held: [Int64: Lyrics] = [:]
    private var task: Task<Void, Never>?
    private var saving: Task<Void, Never>?

    /// The words of this song, if they're wanted now.
    func want(_ id: Int64?, wanted: Bool, client: WittyClient, model: AppModel) {
        failed = ""
        guard let id, wanted else {
            if id != itemId {
                task?.cancel()
                loading = false
                itemId = id
                lyrics = id.flatMap { held[$0] }
                offset = lyrics?.offsetMs ?? 0
            }
            return
        }
        if itemId == id, lyrics != nil || loading { return }
        itemId = id
        if let have = held[id] {
            lyrics = have
            offset = have.offsetMs ?? 0
            return
        }
        lyrics = nil
        load(id, client: client, model: model)
    }

    /// After someone has corrected them.
    func reload(client: WittyClient, model: AppModel) {
        guard let itemId else { return }
        held[itemId] = nil
        lyrics = nil
        load(itemId, client: client, model: model)
    }

    private func load(_ id: Int64, client: WittyClient, model: AppModel) {
        task?.cancel()
        loading = true
        task = Task { [weak self] in
            // The server was busy with another song: ask again after a while, a few times.
            for attempt in 0..<5 {
                do {
                    let found = try await client.lyrics(item: id)
                    guard let self, !Task.isCancelled, self.itemId == id else { return }
                    if found.retry == true, attempt < 4 {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        continue
                    }
                    if (found.failed ?? "").isEmpty { self.held[id] = found }
                    self.lyrics = found
                    self.offset = found.offsetMs ?? 0
                    self.loading = false
                    return
                } catch {
                    guard let self, !Task.isCancelled, self.itemId == id else { return }
                    self.failed = model.handle(error)
                    self.loading = false
                    return
                }
            }
        }
    }

    /// The listener's own timing, saved a moment after the last change.
    func setOffset(_ ms: Double, client: WittyClient) {
        guard let itemId else { return }
        let clamped = max(-120_000, min(120_000, ms))
        offset = clamped
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            try? await client.setLyricsOffset(item: itemId, ms: clamped)
        }
    }
}
