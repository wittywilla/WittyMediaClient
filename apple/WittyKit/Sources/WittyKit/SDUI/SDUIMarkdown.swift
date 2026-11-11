// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// The small Markdown a `Text` may hold, and nothing else: bold, italic, code, `#` to `###` headings, `-` and
/// `1.` lists, paragraphs, and links to a route in the app or an http(s) address. Raw HTML is the characters it is.
public enum SDUIMarkdown {
    public enum Span: Equatable, Sendable {
        case plain(String)
        case bold(String)
        case italic(String)
        case code(String)
        case link(String, to: String)

        public var words: String {
            switch self {
            case .plain(let text), .bold(let text), .italic(let text), .code(let text), .link(let text, _): return text
            }
        }
    }

    public enum Block: Equatable, Sendable {
        /// Level 1 to 3.
        case heading(Int, [Span])
        case paragraph([Span])
        /// `number` nil for a bullet.
        case item(number: Int?, [Span])
    }

    /// Markdown as assistive technology reads it: links by their text, marks removed, white space folded.
    public static func plainText(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "[*_`#>]+", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(spans(paragraph.joined(separator: " ")))) }
            paragraph = []
        }
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let level = ["### ": 3, "## ": 2, "# ": 1].first(where: { line.hasPrefix($0.key) }) {
                flush()
                out.append(.heading(level.value, spans(String(line.dropFirst(level.key.count)))))
            } else if line.hasPrefix("- ") {
                flush()
                out.append(.item(number: nil, spans(String(line.dropFirst(2)))))
            } else if let dot = line.firstIndex(of: "."), let number = Int(line[..<dot]), line[dot...].hasPrefix(". ") {
                flush()
                out.append(.item(number: number, spans(String(line[line.index(dot, offsetBy: 2)...]))))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return out
    }

    /// One line's spans. A mark that never closes is the characters it is.
    public static func spans(_ line: String) -> [Span] {
        var out: [Span] = []
        var plain = ""
        let chars = Array(line)
        var i = 0
        func flush() {
            if !plain.isEmpty { out.append(.plain(plain)) }
            plain = ""
        }
        func close(_ mark: [Character], from start: Int) -> Int? {
            guard start < chars.count else { return nil }
            var j = start
            while j + mark.count <= chars.count {
                if Array(chars[j..<j + mark.count]) == mark, j > start { return j }
                j += 1
            }
            return nil
        }
        while i < chars.count {
            let c = chars[i]
            if c == "*", i + 1 < chars.count, chars[i + 1] == "*", let end = close(["*", "*"], from: i + 2) {
                flush()
                out.append(.bold(String(chars[i + 2..<end])))
                i = end + 2
            } else if c == "*", let end = close(["*"], from: i + 1) {
                flush()
                out.append(.italic(String(chars[i + 1..<end])))
                i = end + 1
            } else if c == "`", let end = close(["`"], from: i + 1) {
                flush()
                out.append(.code(String(chars[i + 1..<end])))
                i = end + 1
            } else if c == "[", let mid = close(["]", "("], from: i + 1), let end = close([")"], from: mid + 2) {
                let to = String(chars[mid + 2..<end])
                flush()
                // Only a route in the app or a web address is a link; anything else is its words.
                if (to.hasPrefix("/") && !to.hasPrefix("//")) || to.lowercased().hasPrefix("http://") || to.lowercased().hasPrefix("https://") {
                    out.append(.link(String(chars[i + 1..<mid]), to: to))
                } else {
                    out.append(.plain(String(chars[i + 1..<mid])))
                }
                i = end + 1
            } else {
                plain.append(c)
                i += 1
            }
        }
        flush()
        return out
    }
}
