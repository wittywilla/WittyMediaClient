// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(tvOS)
import SwiftUI
import WittyKit

// WittyTV More info (Design 2): one programme in full, over the guide, the watch banner and the mini guide. Drawn from
// `GET /tv/{key}/programme?start=` as a `DesignPageSpec` (`MoreInfo.spec`): the programme's title and times, its
// description, the buttons the server offered, facts, cast and crew, trailers and other airings. A person only the
// guide names has no page and is not a stop for focus. The advisory is never shown.

/// What More info is about: a channel and a moment in the programme.
struct MoreInfoAsk: Identifiable {
    let channel: String
    let start: Int64
    var id: String { "\(channel)|\(start)" }
}

struct MoreInfoSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reminders = TvReminders.shared
    let channel: String
    let start: Int64
    /// Watching, from here: the guide or banner closes this and tunes.
    let onWatch: (String) -> Void
    let onFromStart: (String, Int64) -> Void
    @State private var info: ProgrammeInfo?
    @State private var problem = ""
    @State private var message = ""

    private var spec: DesignPageSpec {
        guard var page = info.map({ MoreInfo.spec($0) }) else {
            return DesignPageSpec(eyebrow: "WittyTV", title: problem.isEmpty ? "Loading…" : "More info isn’t available", lead: problem,
                                  actions: [.A2("Close")], layer: true)
        }
        if !message.isEmpty { page.sections.insert(.secN("", message, true), at: 0) }
        page.actions.append(.A2("Close"))
        page.start = page.actions.first?.id ?? ""
        return page
    }

    private func load() async {
        do {
            info = try await client.programmeInfo(channel: channel, start: start)
        } catch let error as APIError {
            problem = error.status == 404 ? "Details are no longer available" : error.message
        } catch {
            problem = plainWords(Problem.of(error))
        }
    }

    private func said(_ words: String) { message = words; announce(words) }

    private func pressed(_ id: String) {
        guard let info else { dismiss(); return }
        let p = info.programme
        let guideProgramme = GuideProgramme(start: p.start, end: p.end, kind: p.kind, title: p.title, sub: p.sub.isEmpty ? nil : p.sub,
                                           itemId: info.library?.itemId, showId: info.library?.showId)
        switch id {
        case "close": dismiss()
        case "watch", "watch-now": onWatch(info.channel.key)
        case "watch-from-the-start": onFromStart(info.channel.key, p.start)
        case "record":
            Task {
                do {
                    try await client.record(channel: info.channel.key, title: p.title, sub: p.sub.isEmpty ? nil : p.sub, start: p.start, stop: p.end)
                    said("Recording \(p.title)")
                } catch { said((error as? APIError)?.message ?? "That couldn’t be recorded.") }
            }
        case "remind-me", "remove-reminder":
            Task { said(await reminders.toggle(info.channel.key, guideProgramme)) }
        case "open-item-page":
            if let item = info.library?.itemId { dismiss(); model.path.append(.item(item)) }
            else if let show = info.library?.showId { dismiss(); model.path.append(.show(show)) }
        case "add-to-watch-list", "remove-from-watch-list":
            let on = id == "add-to-watch-list"
            Task {
                do {
                    try await client.setWatchLater(item: info.library?.itemId, show: info.library?.itemId == nil ? info.library?.showId : nil, on: on)
                    said(on ? "Added to Watch later" : "Removed from Watch later")
                    await load()
                } catch { said((error as? APIError)?.message ?? "That didn’t work. Try again.") }
            }
        default:
            // A person in the library opens their page; a trailer plays; another airing goes to its channel.
            if id.hasPrefix("person-"), let n = Int64(id.dropFirst(7)) {
                dismiss()
                model.path.append(.sdui(SDUIPlace(page: "detail", params: ["person": String(n)], route: "/person/\(n)")))
            } else if id.hasPrefix("trailer-"), let n = Int64(id.dropFirst(8)) {
                dismiss()
                model.path.append(.player(n, startOver: true))
            } else if id.hasPrefix("airing-") { dismiss() }
        }
    }

    var body: some View {
        DesignSpecPage(spec: spec, onPress: pressed, onBack: { dismiss() })
            .accessibilityIdentifier("tv.moreInfo")
            .task { await load() }
    }
}
#endif
