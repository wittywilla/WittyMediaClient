// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit
#if canImport(UIKit)
import UIKit
#endif

// Skip recap, Skip intro, Skip adverts and Skip credits in the video player, from every source the server knows
// (docs/PLAYING.md, "Skip intro"), and skipping by itself for the parts chosen on this device. The rules are WittyKit's
// MediaSkips.swift; this keeps them for the video that's playing and draws the buttons. The player tells it the
// film's time once a second and whenever it seeks, and does the jumps it answers through its own `seek(toFilm:)`,
// so a seek that has to reopen the stream, a remote control or a watch party all go the one way.

@MainActor
final class SkipDriver: ObservableObject {
    /// What can be skipped right now.
    @Published private(set) var offer: SkipOffer?
    /// A part was just skipped without anyone asking.
    @Published private(set) var notice: SkipNotice?
    /// The server lists `skip-markers`: ask it for every part. Otherwise the playback answer's intro is all there is.
    var wanted = false
    /// Off while something else decides where the film is for everyone (a watch party): the buttons stay.
    var skipsByItself = true

    private var markers: SkipMarkers?
    private var fromServer = false
    private var tracker = SkipTracker()
    private var item: Int64 = 0
    private var asking: Task<Void, Never>?
    private var hiding: Task<Void, Never>?
    private var jumping = false

    /// A stream opened: the same video again (another sound track, a seek too far for the stream) keeps what's known.
    func opened(item id: Int64, stream: Playback, client: WittyClient) {
        if id != item {
            reset()
            item = id
        }
        if !fromServer { markers = SkipMarkers(intro: stream.intro) }
        guard wanted, !fromServer, asking == nil else { return }
        asking = Task { [weak self] in
            let found = try? await client.markers(item: id)
            guard let self, !Task.isCancelled, self.item == id else { return }
            self.asking = nil
            if let found {
                self.markers = found
                self.fromServer = true
            }
        }
    }

    /// The player is about to seek. This driver's own jumps aren't a person's.
    func seeked() {
        if !jumping { tracker.seeked() }
    }

    /// The film's time, about once a second. Answers where to jump to when a part is to be skipped by itself.
    func tick(film: Double, duration: Double, hasNext: Bool, playing: Bool, rate: Double) -> Double? {
        let now = SkipRules.offer(markers, at: film, duration: duration, hasNext: hasNext)
        if now != offer { offer = now }
        let prefs = skipsByItself ? SkipPrefs.load() : SkipPrefs.none
        let to = tracker.tick(now: film, rate: rate, playing: playing, offer: now, prefs: prefs)
        if tracker.notice != notice { show(tracker.notice) }
        return to
    }

    /// Runs a jump this driver asked for, so the player's "I'm seeking" isn't taken for a person's.
    func jump(_ seek: () -> Void) {
        jumping = true
        seek()
        jumping = false
    }

    /// The button was pressed.
    func pressed() -> SkipOffer? {
        guard let offer else { return nil }
        tracker.pressed(offer)
        show(nil)
        self.offer = nil
        return offer
    }

    /// Undo: where to go back to.
    func undo() -> Double? {
        let back = tracker.undo()
        show(nil)
        return back
    }

    func reset() {
        asking?.cancel()
        asking = nil
        hiding?.cancel()
        hiding = nil
        markers = nil
        fromServer = false
        tracker = SkipTracker()
        item = 0
        if offer != nil { offer = nil }
        if notice != nil { notice = nil }
    }

    private func show(_ next: SkipNotice?) {
        hiding?.cancel()
        hiding = nil
        notice = next
        guard let next else { return }
        announce(next.words)
        hiding = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SkipTracker.noticeSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.tracker.clearNotice()
            self.notice = nil
        }
    }
}

extension PlaybackModel {
    /// The skip button: past the part, or on to the next episode while the last credits roll.
    func skipNow() {
        guard let offer = skips.pressed() else { return }
        if offer.next { playNext() } else { skips.jump { seek(toFilm: offer.to) } }
    }

    /// Back to where a part was skipped by itself.
    func undoSkip() {
        guard let back = skips.undo() else { return }
        skips.jump { seek(toFilm: back) }
    }
}

#if os(tvOS)
extension SkipDriver {
    /// What the system player's own bar is built from, so it's rebuilt when these change and not otherwise.
    var shape: String { "\(offer?.id ?? "")|\(offer?.next == true)|\(notice != nil)" }

    /// Apple TV: the system player shows these as buttons over the picture that the remote can reach with a press of
    /// Down, without taking the focus from the transport bar when they appear.
    func actions(_ playback: PlaybackModel) -> [UIAction] {
        var actions: [UIAction] = []
        if let offer { actions.append(UIAction(title: offer.label, identifier: UIAction.Identifier("wms.skip")) { _ in playback.skipNow() }) }
        if let notice {
            actions.append(UIAction(title: "\(notice.words) · Undo", identifier: UIAction.Identifier("wms.skip.undo")) { _ in playback.undoSkip() })
        }
        return actions
    }
}
#endif

#if os(iOS) || os(visionOS)
/// Over the picture on a phone and a tablet, where the website's Skip intro is: the part's button while it plays,
/// or for a few seconds what was skipped by itself with a way back. The caller gives the button its look.
struct SkipButtons: View {
    @ObservedObject var playback: PlaybackModel
    @ObservedObject var skips: SkipDriver
    /// Shows the controls again, as any touch does.
    let touched: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: Tokens.Space.s2) {
            if let notice = skips.notice {
                Button("\(notice.words) · Undo") { touched(); playback.undoSkip() }
                    .accessibilityIdentifier("skip-undo")
                    .accessibilityLabel("\(notice.words). Undo")
            }
            if let offer = skips.offer {
                Button("\(offer.label) ›") { touched(); playback.skipNow() }
                    .accessibilityIdentifier("skip-\(offer.next ? "next" : offer.kind.rawValue)")
                    .accessibilityLabel(offer.label)
            }
        }
    }
}

/// The gear's rows for skipping by itself, in the look of its other rows: for every video on this device.
struct SkipGearRows: View {
    @Environment(\.palette) private var palette
    @State private var prefs = SkipPrefs.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SkipKind.allCases, id: \.self) { kind in
                let on = prefs.skips(kind)
                HStack(spacing: Tokens.Space.s3) {
                    Text("Skip \(kind.settingName.lowercased()) by itself").font(.system(size: 14)).foregroundStyle(Color.white)
                    Spacer(minLength: 0)
                    Button {
                        prefs.set(kind, !on)
                        SkipPrefs.save(prefs)
                    } label: {
                        Capsule().fill(on ? palette.accent : Color.white.opacity(0.3))
                            .frame(width: 44, height: 24)
                            .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).frame(width: 18, height: 18).padding(3) }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip \(kind.settingName.lowercased()) by itself")
                    .accessibilityValue(on ? "On" : "Off")
                    .accessibilityIdentifier("gear-skip-\(kind.rawValue)")
                }
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
            }
        }
    }
}
#endif
