// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// The steps of connecting from away and why one can fail, in the server's words (its
/// pkg/connectsteps/steps.json, kept as shared/data/connect-steps.json): the same codes as the
/// server's Recent tries, and the same sentences on every app. Tested against the file's cases.
public struct ConnectSteps: Sendable {
    public struct Step: Decodable, Equatable, Sendable {
        public let id: String
        public let title: String
        public var failed = ""
        /// Shown while an app is on this step ("Looking for a way to reach your server…").
        public var doing = ""
        enum CodingKeys: String, CodingKey { case id, title, failed, doing }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            failed = (try? c.decode(String.self, forKey: .failed)) ?? ""
            doing = (try? c.decode(String.self, forKey: .doing)) ?? ""
        }
    }

    /// The hint while connecting takes a while, and after how many seconds.
    public struct Slow: Decodable, Equatable, Sendable {
        public var after = 10
        public var say = ""
        enum CodingKeys: String, CodingKey { case after, say }
        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            after = (try? c.decode(Int.self, forKey: .after)) ?? 10
            say = (try? c.decode(String.self, forKey: .say)) ?? ""
        }
    }

    public struct Code: Decodable, Equatable, Sendable {
        public let code: String
        public var step = ""
        public var reasons: [String] = []
        public var match: [String] = []
        public var say = ""
        public var next = ""
        enum CodingKeys: String, CodingKey { case code, step, reasons, match, say, next }
        public init(code: String, say: String) { self.code = code; self.say = say }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(String.self, forKey: .code)
            step = (try? c.decode(String.self, forKey: .step)) ?? ""
            reasons = (try? c.decode([String].self, forKey: .reasons)) ?? []
            match = (try? c.decode([String].self, forKey: .match)) ?? []
            say = (try? c.decode(String.self, forKey: .say)) ?? ""
            next = (try? c.decode(String.self, forKey: .next)) ?? ""
        }
    }

    private struct File: Decodable {
        let steps: [Step]
        let slow: Slow?
        let codes: [Code]
    }

    /// The steps' order: their ids never change.
    public static let order = ["read", "found", "secure", "signin"]

    public let steps: [Step]
    public let slow: Slow
    public let codes: [Code]

    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        steps = file.steps
        slow = file.slow ?? Slow()
        codes = file.codes
    }

    /// The failure behind a server's reason ("expired") and an error's words. A reason is looked
    /// for first, then the words; with neither known, "unknown" at `step`, the step being tried.
    public func classify(reason: String, text: String, step: String) -> ConnectFailure {
        let r = reason.trimmingCharacters(in: .whitespaces)
        let lower = text.lowercased()
        func pick(_ c: Code) -> ConnectFailure {
            ConnectFailure(step: c.step.isEmpty ? step : c.step, code: c.code, say: c.say, next: c.next, error: String(Redact.clean(text).prefix(400)))
        }
        if !r.isEmpty, let c = codes.first(where: { $0.reasons.contains(r) }) { return pick(c) }
        if !lower.isEmpty, let c = codes.first(where: { $0.match.contains(where: { lower.contains($0) }) }) { return pick(c) }
        return pick(codes.first { $0.code == "unknown" } ?? Code(code: "unknown", say: "Something went wrong."))
    }

    public func of(_ code: String, step: String = "") -> ConnectFailure { classify(reason: code, text: "", step: step) }
}

/// A step that failed, why, and what to try next. `error` is the technical words, redacted.
public struct ConnectFailure: Equatable, Sendable {
    public var step: String
    public var code: String
    public var say: String
    public var next: String
    public var error = ""

    public init(step: String, code: String, say: String, next: String, error: String = "") {
        self.step = step
        self.code = code
        self.say = say
        self.next = next
        self.error = error
    }
}

/// One go at connecting from away: the steps that got through, the one that failed, and a short
/// log of what the app saw, for Copy details. Nothing in it is sent anywhere.
public final class ConnectRun: Identifiable, @unchecked Sendable {
    public enum State: String, Sendable { case ok, fail, skip }

    /// One step and how it went.
    public struct StepState: Identifiable, Sendable {
        public let step: ConnectSteps.Step
        public let state: State
        public var id: String { step.id }
    }

    public let id = UUID()
    public let kind: String
    public let server: String
    /// The server's name, once the invite or the server says it.
    public private(set) var name = ""
    private let started = Date()
    public private(set) var passed: [String] = []
    public private(set) var failure: ConnectFailure?
    private var log: [String] = []

    public init(kind: String, server: String = "") {
        self.kind = kind
        self.server = server
    }

    public func note(_ line: String) {
        guard log.count < 60 else { return }
        log.append(String(format: "+%.1fs ", Date().timeIntervalSince(started)) + String(Redact.clean(line).prefix(300)))
    }

    public func pass(_ step: String) {
        if !passed.contains(step) { passed.append(step) }
        note("ok: \(step)")
    }

    public func named(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { self.name = String(n.prefix(80)) }
    }

    /// It ended with words alone (a code no server made, say): the step it was on is the one that failed.
    public func stop(_ words: String) {
        guard failure == nil else { return }
        let at = ConnectSteps.order.first { !passed.contains($0) } ?? ConnectSteps.order[ConnectSteps.order.count - 1]
        fail(ConnectFailure(step: at, code: "", say: words, next: ""))
    }

    /// While connecting, for the connecting screen: each step done, being tried now, still to come or failed;
    /// what the step being tried is doing; how long it has taken; and the slow hint once it has taken a while.
    public func progress(_ steps: ConnectSteps, now: Date = Date()) -> ConnectProgress {
        let at = failure == nil ? steps.steps.firstIndex { !passed.contains($0.id) } : nil
        var items: [ConnectProgress.Item] = []
        for (i, s) in states(steps.steps).enumerated() {
            let state: ConnectProgress.State
            switch s.state {
            case .ok: state = .ok
            case .fail: state = .fail
            case .skip: state = failure != nil ? .skip : (i == at ? .now : .wait)
            }
            items.append(ConnectProgress.Item(step: s.step, state: state))
        }
        let step = at.map { steps.steps[$0] }
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        let slow = failure == nil && !steps.slow.say.isEmpty && seconds >= steps.slow.after ? steps.slow.say : ""
        return ConnectProgress(items: items, step: step?.id ?? "", doing: step.map { $0.doing.isEmpty ? $0.title : $0.doing } ?? "",
                               seconds: seconds, slow: slow, failure: failure)
    }

    /// Shown on the step being tried: words that belong to an earlier step that already got
    /// through (a time-out while signing in, say) move to the step after the last that did.
    @discardableResult
    public func fail(_ failure: ConnectFailure) -> ConnectFailure {
        var f = failure
        let last = passed.compactMap { ConnectSteps.order.firstIndex(of: $0) }.max() ?? -1
        let at = ConnectSteps.order.firstIndex(of: f.step) ?? -1
        if at < 0 || at < last { f.step = ConnectSteps.order[min(last + 1, ConnectSteps.order.count - 1)] }
        self.failure = f
        note("failed: \(f.step) (\(f.code))" + (f.error.isEmpty ? "" : ": \(f.error)"))
        return f
    }

    /// Each step: done, failed, or not reached. Nothing after the failed one is ever done.
    public func states(_ steps: [ConnectSteps.Step]) -> [StepState] {
        let at = steps.firstIndex { $0.id == failure?.step } ?? -1
        return steps.enumerated().map { i, s in
            if at >= 0 && i == at { return StepState(step: s, state: .fail) }
            if at >= 0 && i > at { return StepState(step: s, state: .skip) }
            return StepState(step: s, state: passed.contains(s.id) || at > i ? .ok : .skip)
        }
    }

    /// Copy details: plain text to paste to whoever runs the server. Redacted.
    public func details(_ steps: [ConnectSteps.Step], app: String, device: String) -> String {
        let stamp = ISO8601DateFormatter().string(from: started)
        var lines = [
            "WittyMediaClient connection check", "When: \(stamp)", "App: \(app)", "Device: \(device)",
            "Joining: \(kind)" + (server.isEmpty ? "" : " (server …\(server.suffix(8)))"),
        ]
        for s in states(steps) { lines.append("[\(s.state == .ok ? "x" : s.state == .fail ? "!" : " ")] \(s.step.title)") }
        if let f = failure {
            lines += ["Failed: \(f.step), \(f.code)", f.say, "Next: \(f.next)"]
            if !f.error.isEmpty { lines.append("Error: \(f.error)") }
        }
        lines.append("Log:")
        lines += log.map { "  \($0)" }
        return Redact.clean(lines.joined(separator: "\n"))
    }
}

/// What the connecting screen shows for a run, at one moment.
public struct ConnectProgress: Sendable {
    public enum State: String, Sendable { case ok, now, wait, fail, skip }

    public struct Item: Identifiable, Sendable {
        public let step: ConnectSteps.Step
        public let state: State
        public var id: String { step.id }
    }

    public let items: [Item]
    public let step: String
    public let doing: String
    public let seconds: Int
    public let slow: String
    public let failure: ConnectFailure?

    /// How long connecting has taken, as a clock: 0:07, 1:02.
    public var clock: String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
