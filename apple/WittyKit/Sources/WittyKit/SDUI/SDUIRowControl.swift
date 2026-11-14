// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// A list row's control (docs/SDUI.md, Control): a switch, a select, a field or a slider on the row, run with the row's
/// action. A select's choice goes into the action's params as `value`; a switch's action already carries the new state.
/// Disabled draws it dimmed, out of focus, with `why` under it. As the website's ControlView (web/src/sdui/formsModel.ts).
public struct SDUIRowControl: Equatable, Sendable {
    public struct Option: Equatable, Sendable, Identifiable {
        public var value: String
        public var label: String
        public var id: String { value }
    }

    public var type: String
    public var name: String
    /// A select's or field's value as text; a switch's as "true"/"false".
    public var value: String
    public var on: Bool
    public var options: [Option]
    public var disabled: Bool
    public var why: String

    public init?(_ raw: JSONValue?) {
        guard let o = raw?.object, let type = o["type"]?.string, !type.isEmpty else { return nil }
        self.type = type
        name = o["name"]?.string ?? ""
        on = o["value"]?.bool ?? false
        value = o["value"]?.string ?? o["value"]?.double.map { String($0) } ?? (on ? "true" : "")
        options = (o["options"]?.array ?? []).compactMap { opt in
            guard let v = opt.object?["value"] else { return nil }
            let text = v.string ?? v.double.map { String($0) } ?? ""
            return Option(value: text, label: opt.object?["label"]?.string ?? text)
        }
        disabled = o["disabled"]?.bool ?? false
        why = o["why"]?.string ?? ""
    }

    /// What the row says the control is set to: a select's chosen option's label, a switch's On or Off.
    public var shown: String {
        switch type {
        case "switch": return on ? "On" : "Off"
        case "select": return options.first { $0.value == value }?.label ?? value
        default: return value
        }
    }

    /// The row's action run with a choice: a select's or field's value added to its params; a switch's as it is.
    public func action(_ base: SDUIAction?, choosing value: String) -> SDUIAction? {
        guard var action = base, !disabled else { return nil }
        if type != "switch" {
            var params = action.params ?? [:]
            params["value"] = .string(value)
            action.params = params
        }
        return action
    }
}
