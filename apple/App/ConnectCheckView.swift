// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// What a failed connection from away shows, instead of going back to the list of servers: each
/// step of connecting with a tick or a cross, one sentence on the step that failed and the next
/// thing to try, and the details (redacted) to copy or share. The same screen as the Android apps'
/// ConnectCheckScreen and the desktop app's checkScreen (shared/connect/connect.js).
struct ConnectCheckView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let run: ConnectRun
    var retry: (() -> Void)? = nil
    @State private var copied = false
    @Namespace private var scope

    private var steps: [ConnectSteps.Step] { SharedData.connectSteps?.steps ?? [] }

    private var details: String {
        run.details(steps, app: "WittyMediaClient \(model.platformName) \(WittyClient.appVersion)", device: model.deviceName)
    }

    private func close() { model.connectCheck = nil }

    var body: some View {
        DesignPage(eyebrow: say("rowAway"), title: say("checkTitle"), lead: say("checkLead"), identifier: "connectCheck") {
            DesignSection(title: "") {
                DesignRows {
                    ForEach(run.states(steps)) { item in
                        DesignRow(title: item.step.title, value: word(item.state), on: item.state == .ok,
                                  detail: item.state == .fail ? run.failure?.say ?? "" : "", symbol: symbol(item.state))
                            .accessibilityIdentifier("check.\(item.step.id)")
                    }
                }
            }
            if let f = run.failure {
                DesignSection(title: "") {
                    DesignNote(text: say("checkNext").replacingOccurrences(of: "{next}", with: f.next), tone: true)
                    if copied { DesignNote(text: say("checkCopied")) }
                }
            }
            DesignSection(title: say("checkDetails")) {
                DesignNote(text: say("checkDetailsHint"))
                Text(details)
                    .font(.system(metrics.tv ? .body : .footnote, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .textSelectionIfAvailable()
                    .accessibilityIdentifier("check.details")
            }
        } actions: {
            if let retry {
                Button(say("checkTryAgain")) { close(); retry() }.action(primary: true)
                    .firstFocus(in: scope, when: true)
            }
            // A TV has nowhere to paste or send the details: they're on the screen instead.
            #if os(iOS)
            if !metrics.tv {
                Button(say("checkCopy")) { Clipboard.copy(details); copied = true }.action()
                ShareLink(item: details) { Text(say("checkShare")) }.action()
            }
            #endif
            Button(say("checkOtherServer"), action: close).action(primary: retry == nil)
                .firstFocus(in: scope, when: retry == nil)
        }
        .onRemoteBack(close)
        .focusRoot(scope)
    }

    private func word(_ state: ConnectRun.State) -> String {
        switch state {
        case .ok: return say("checkStepDone")
        case .fail: return say("checkStepFailed")
        case .skip: return say("checkStepSkipped")
        }
    }

    private func symbol(_ state: ConnectRun.State) -> String {
        switch state {
        case .ok: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .skip: return "minus.circle"
        }
    }
}
