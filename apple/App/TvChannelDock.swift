// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(tvOS)
import AVKit
import SwiftUI
import WittyKit

// The fourth of WittyTV's four places (docs/plans/DESIGN-2.md section 4): inside the player, OK shows the banner, Up and Down
// change channel, Left opens the mini guide, Right opens this Dock (audio, subtitles, ten seconds back or on, Look, back to
// the guide), and Back closes the topmost.

/// One choice of audio or subtitles.
struct LiveTrack: Identifiable, Equatable {
    let id: Int
    let name: String
    let selected: Bool
}

extension LiveTv {
    /// The audio or subtitle choices of what is playing, with the one in use marked. Subtitles start with "Off" (id -1).
    func tracks(_ characteristic: AVMediaCharacteristic) async -> [LiveTrack] {
        guard let item = player.currentItem,
              let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic) else { return [] }
        let chosen = item.currentMediaSelection.selectedMediaOption(in: group)
        var out = group.options.enumerated().map { index, option in
            LiveTrack(id: index, name: option.displayName, selected: option == chosen)
        }
        if characteristic == .legible { out.insert(LiveTrack(id: -1, name: "Off", selected: chosen == nil), at: 0) }
        return out
    }

    func choose(_ track: LiveTrack, _ characteristic: AVMediaCharacteristic) async {
        guard let item = player.currentItem,
              let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic) else { return }
        item.select(group.options.indices.contains(track.id) ? group.options[track.id] : nil, in: group)
    }
}

/// The player's Dock, over the foot of the picture in the look's own colours.
struct ChannelDock: View {
    let dress: TvDress
    @ObservedObject var live: LiveTv
    let onGuide: () -> Void
    let onLook: () -> Void
    let onClose: () -> Void
    @State private var audio: [LiveTrack] = []
    @State private var subtitles: [LiveTrack] = []
    @State private var choosing: (title: String, kind: AVMediaCharacteristic, tracks: [LiveTrack])?
    @FocusState private var focused: String?

    var body: some View {
        let p = dress.paint
        VStack(spacing: 12) {
            if let choosing {
                HStack(spacing: 12) {
                    Text(choosing.title).font(dress.font(25, .bold)).foregroundStyle(p.text)
                    ForEach(choosing.tracks) { track in
                        Button(track.name) {
                            Task { await live.choose(track, choosing.kind); await reload(); self.choosing = nil; focused = "audio" }
                        }
                        .buttonStyle(TvButtonStyle(dress: dress, kind: .chip, on: track.selected, onBar: true))
                        .accessibilityAddTraits(track.selected ? [.isSelected] : [])
                    }
                }
                .focusSection()
            }
            HStack(spacing: 16) {
                Button { live.seek(by: -10) } label: { Label("Back 10", systemImage: "gobackward.10") }
                    .buttonStyle(TvButtonStyle(dress: dress, onBar: true)).focused($focused, equals: "back")
                Button { live.seek(by: 10) } label: { Label("On 10", systemImage: "goforward.10") }
                    .buttonStyle(TvButtonStyle(dress: dress, onBar: true))
                if audio.count > 1 {
                    Button { choosing = ("Audio", .audible, audio) } label: { Label("Audio", systemImage: "speaker.wave.2") }
                        .buttonStyle(TvButtonStyle(dress: dress, onBar: true)).focused($focused, equals: "audio")
                }
                if subtitles.count > 1 {
                    Button { choosing = ("Subtitles", .legible, subtitles) } label: { Label("Subtitles", systemImage: "captions.bubble") }
                        .buttonStyle(TvButtonStyle(dress: dress, onBar: true))
                }
                Button(action: onLook) { Label("Look", systemImage: "paintpalette") }.buttonStyle(TvButtonStyle(dress: dress, onBar: true))
                Button(action: onGuide) { Label("Guide", systemImage: "list.bullet.rectangle") }.buttonStyle(TvButtonStyle(dress: dress, onBar: true))
                Spacer(minLength: 16)
                GuideLegend(dress: dress)
            }
            .focusSection()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 77)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onExitCommand { if choosing != nil { choosing = nil } else { onClose() } }
        .task { await reload(); focused = "back" }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player controls")
        .accessibilityIdentifier("tv.player.dock")
    }

    private func reload() async {
        audio = await live.tracks(.audible)
        subtitles = await live.tracks(.legible)
    }
}
#endif
