// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// The connecting screen: from an invite link given, or a TV's code taken, until the server opens. One centred card
/// with the server's name, each step ticking off as it gets through, what the step being tried is doing in plain
/// words, the time so far and Cancel; after a while a hint that it can take up to a minute. A failure shows the
/// connection check (each step, and what to do) in its place, or, for words alone, the step it stopped on and those
/// words here. The same screen as the Android apps' ConnectingScreen and the desktop app's connectingScreen
/// (shared/connect/connect.js).
struct ConnectingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let run: ConnectRun
    @Namespace private var scope

    var body: some View {
        if model.connectCheck === run {
            ConnectCheckView(run: run, retry: model.connectingRetry)
        } else if let steps = SharedData.connectSteps {
            // Read again twice a second: the join ticks the run off as it goes, and the clock moves on.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                page(run.progress(steps, now: context.date))
            }
        } else {
            page(nil)
        }
    }

    @ViewBuilder private func page(_ p: ConnectProgress?) -> some View {
        let words = model.connectingWords
        let ended = !words.isEmpty
        let content = VStack(spacing: metrics.tv ? Tokens.Space.s8 : Tokens.Space.s5) {
            // The server's name is the lockup's, over the title, as on the sign-in screens: not said twice.
            HStack(spacing: metrics.tv ? Tokens.Space.s5 : 10) {
                BrandMark(size: metrics.tv ? 72 : 32, logo: nil, app: false)
                Wordmark(app: false, name: run.name)
            }
            .accessibilityElement(children: .combine)
            SignInHeading(title: say("connectingTitlePlain"), centred: true)
            if let p {
                DesignRows {
                    ForEach(p.items) { item in
                        DesignRow(title: item.step.title, value: word(item.state), on: item.state == .ok,
                                  detail: item.state == .fail ? words : "", symbol: symbol(item.state))
                            .accessibilityIdentifier("connecting.\(item.step.id).\(item.state.rawValue)")
                    }
                }
                if !ended && !p.doing.isEmpty {
                    HStack(spacing: Tokens.Space.s2) {
                        ProgressView()
                        Text(p.doing).foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("connecting.doing")
                }
                if !p.slow.isEmpty {
                    Text(p.slow)
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("connecting.slow")
                }
            } else if ended {
                ProblemLine(words)
            }
            VStack(spacing: Tokens.Space.s3) {
                if ended {
                    if let retry = model.connectingRetry {
                        Button(say("checkTryAgain")) { model.stopJoining(); retry() }.action(primary: true)
                            .firstFocus(in: scope, when: true)
                    }
                    Button(say("back")) { model.stopJoining() }.action(primary: model.connectingRetry == nil)
                        .firstFocus(in: scope, when: model.connectingRetry == nil)
                } else {
                    Button(say("cancel")) { model.stopJoining() }.action()
                        .firstFocus(in: scope, when: true)
                        .accessibilityIdentifier("connecting.cancel")
                }
            }
            if let p, !ended {
                Text(say("connectingSoFar").replacingOccurrences(of: "{time}", with: p.clock))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: metrics.tv ? 900 : 520)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connecting")
        Group {
            if metrics.tv {
                ZStack {
                    SignInBackground()
                    content.padding(.horizontal, metrics.gutter).frame(maxWidth: .infinity)
                }
            } else {
                SignInPage { content.frame(maxWidth: .infinity) }
            }
        }
        .onRemoteBack { model.stopJoining() }
        .focusRoot(scope)
    }

    private func word(_ state: ConnectProgress.State) -> String {
        switch state {
        case .ok: return say("checkStepDone")
        case .now: return say("checkStepNow")
        case .fail: return say("checkStepFailed")
        case .wait: return ""
        case .skip: return say("checkStepSkipped")
        }
    }

    private func symbol(_ state: ConnectProgress.State) -> String {
        switch state {
        case .ok: return "checkmark.circle.fill"
        case .now: return "circle.dotted"
        case .fail: return "xmark.circle.fill"
        case .wait: return "circle"
        case .skip: return "minus.circle"
        }
    }
}

extension View {
    /// The connecting screen over everything: the whole screen on a phone, a tablet and a TV, where swiping it away
    /// isn't how to stop it (Cancel is); a sheet on a Mac.
    @ViewBuilder func connectingCover<Item: Identifiable, Cover: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Cover) -> some View {
        #if os(macOS)
        sheet(item: item, content: content)
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }
}
