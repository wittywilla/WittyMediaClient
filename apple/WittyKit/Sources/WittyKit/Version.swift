import Foundation

/// Dotted version numbers, for one question only: is this app older than the lowest
/// version a server says it works with? Optional abilities are never decided this way:
/// they go by the names in `features`.
public enum Version {
    /// "0.2.0-alpha" and "v0.2" read as numbers. Anything else can't be compared.
    static func numbers(_ version: String) -> [Int]? {
        var text = Substring(version.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        // A release's label doesn't count: 0.2.0-alpha is 0.2.0 for this question.
        if let label = text.firstIndex(where: { $0 == "-" || $0 == "+" }) { text = text[..<label] }
        guard !text.isEmpty, text.count <= 32 else { return nil }
        var out: [Int] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            out.append(number)
        }
        return out
    }

    /// Missing parts count as zero, so 0.2 and 0.2.0 are the same. Nil if either can't be read.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult? {
        guard let left = numbers(a), let right = numbers(b) else { return nil }
        for i in 0..<max(left.count, right.count) {
            let (x, y) = (i < left.count ? left[i] : 0, i < right.count ? right[i] : 0)
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// Something that can't be read never locks anyone out.
    public static func isOlder(_ version: String, than minimum: String) -> Bool {
        compare(version, minimum) == .orderedAscending
    }
}
