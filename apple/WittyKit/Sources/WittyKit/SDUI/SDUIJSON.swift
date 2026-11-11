// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// Any JSON value. A server-driven page's properties are whatever the server's catalogue says they are,
/// and a newer server sends ones this app has never heard of: they're kept as they came and read by name,
/// so nothing unknown can stop a page being read.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() {
            self = .null
        } else if let value = try? box.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? box.decode(Double.self) {
            self = .number(value)
        } else if let value = try? box.decode(String.self) {
            self = .string(value)
        } else if let value = try? box.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try box.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .null: try box.encodeNil()
        case .bool(let value): try box.encode(value)
        case .number(let value):
            // Whole numbers go back out as whole numbers, as the server wrote them.
            if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
                try box.encode(Int64(value))
            } else {
                try box.encode(value)
            }
        case .string(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        }
    }

    public var string: String? { if case .string(let value) = self { return value } else { return nil } }
    public var bool: Bool? { if case .bool(let value) = self { return value } else { return nil } }
    public var double: Double? { if case .number(let value) = self { return value } else { return nil } }
    public var int: Int? {
        guard case .number(let value) = self, value.isFinite, abs(value) < 1e15 else { return nil }
        return Int(value)
    }
    public var array: [JSONValue]? { if case .array(let value) = self { return value } else { return nil } }
    public var object: [String: JSONValue]? { if case .object(let value) = self { return value } else { return nil } }
    public var isNull: Bool { self == .null }

    public subscript(key: String) -> JSONValue? { object?[key] }

    /// Something that's Encodable, as a value: how the conformance tests compare what was built with what was expected.
    public init<T: Encodable>(encoding value: T) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(value))
    }

    /// The value read as a type of the app's own. Nil when it doesn't fit.
    public func decoded<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// The same value with everything that means "nothing" taken out: nulls, false, 0, "" and empty lists and
    /// objects. The conformance kit treats a missing key and its zero value as the same.
    public var withoutZeroValues: JSONValue {
        switch self {
        case .object(let fields):
            var kept: [String: JSONValue] = [:]
            for (key, value) in fields {
                let inner = value.withoutZeroValues
                if !inner.isZero { kept[key] = inner }
            }
            return .object(kept)
        case .array(let values):
            return .array(values.map(\.withoutZeroValues))
        default:
            return self
        }
    }

    var isZero: Bool {
        switch self {
        case .null: return true
        case .bool(let value): return !value
        case .number(let value): return value == 0
        case .string(let value): return value.isEmpty
        case .array(let value): return value.isEmpty
        case .object(let value): return value.isEmpty
        }
    }
}

/// A node's or an action's properties, read by name. Every reader answers nothing for a value of the wrong kind.
public typealias SDUIProps = [String: JSONValue]

public extension Dictionary where Key == String, Value == JSONValue {
    func text(_ key: String) -> String { self[key]?.string ?? "" }
    func flag(_ key: String) -> Bool? { self[key]?.bool }
    func whole(_ key: String) -> Int? { self[key]?.int }
    func number(_ key: String) -> Double? { self[key]?.double }
    func fields(_ key: String) -> SDUIProps? { self[key]?.object }
    func items(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }
}
