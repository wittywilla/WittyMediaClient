import Foundation

// The programme guide's grid, as web/src/pages/tv/GuidePage.tsx in the server's repository builds it:
// half-hour columns, gaps that are cells too so every moment of every channel can be reached, and
// runs of programmes too short to draw that become one cell. Apple TV draws it natively; this is
// what it draws, held to the page by GuideRulesTests.

/// One cell of a channel's row: a programme, a gap, or a run of short programmes drawn as one.
public struct GuideCell: Equatable {
    public enum Kind: Equatable { case programme, none, group }

    public let start: Int64
    public let end: Int64
    public let kind: Kind
    public let title: String
    /// The programme itself. A gap has none.
    public let programme: GuideProgramme?
    /// What a run of short programmes holds.
    public let group: [GuideProgramme]

    public init(start: Int64, end: Int64, kind: Kind, title: String, programme: GuideProgramme? = nil, group: [GuideProgramme] = []) {
        self.start = start
        self.end = end
        self.kind = kind
        self.title = title
        self.programme = programme
        self.group = group
    }

    public func isOn(at now: Int64) -> Bool { start <= now && now < end }
    /// The channel's own "we'll be back", or nothing at all: drawn quieter.
    public var isDim: Bool { kind == .none || programme?.kind == "slate" }
    /// Something that can be recorded: a broadcast on a tuner channel.
    public var isBroadcast: Bool { programme?.kind == "broadcast" }

    /// The one programme of a run that's on at a time, or the cell's own.
    public func programme(at time: Int64) -> GuideProgramme? {
        if kind == .group { return group.first { $0.start <= time && time < $0.end } ?? group.first }
        return programme
    }
}

public enum GuideRules {
    /// The grid's columns are half hours.
    public static let slot: Int64 = 1800
    /// How much of the schedule is asked for at a time, and the step it's asked for in.
    public static let fetchHours = 8
    public static let fetchSpan: Int64 = 3 * 3600
    /// Rows asked for at a time.
    public static let page = 30
    /// A cell narrower than this can't show anything: several in a row are drawn as one.
    public static let tinyWidth = 14.0
    /// How far back and forward the guide goes.
    public static let earliest: Int64 = 2 * 3600
    public static let latest: Int64 = 14 * 86400

    public static func floorSlot(_ time: Int64) -> Int64 { time - ((time % slot) + slot) % slot }

    /// How many half hours fit across: from the viewer's choice of hours, or the screen's width.
    public static func slots(hours: Double, width: Double) -> Int {
        if hours > 0 { return Int((hours * 2).rounded()) }
        return width < 560 ? 3 : width < 1000 ? 4 : width < 1500 ? 5 : 6
    }

    /// The cells of a row for the stretch on screen; gaps are cells too.
    public static func cells(_ channel: GuideChannel?, from: Int64, to: Int64, pointsPerSecond: Double) -> [GuideCell] {
        guard let channel else { return [] }
        let gap = channel.kind == "library" ? "Off air" : "No guide data"
        var out: [GuideCell] = []
        var t = from
        for p in (channel.programmes ?? []).sorted(by: { $0.start < $1.start }) {
            if p.end <= from || p.start >= to { continue }
            if p.start > t { out.append(GuideCell(start: t, end: p.start, kind: .none, title: gap)) }
            out.append(GuideCell(start: p.start, end: p.end, kind: .programme, title: p.title, programme: p))
            t = max(t, p.end)
        }
        if t < to { out.append(GuideCell(start: t, end: to, kind: .none, title: gap)) }
        return groupTiny(out, pointsPerSecond: pointsPerSecond, from: from, to: to)
    }

    static func groupTiny(_ cells: [GuideCell], pointsPerSecond: Double, from: Int64, to: Int64) -> [GuideCell] {
        guard pointsPerSecond > 0 else { return cells }
        func width(_ c: GuideCell) -> Double { Double(min(c.end, to) - max(c.start, from)) * pointsPerSecond }
        var out: [GuideCell] = []
        var i = 0
        while i < cells.count {
            var j = i
            while j + 1 < cells.count, width(cells[j]) < tinyWidth, width(cells[j + 1]) < tinyWidth { j += 1 }
            if j > i {
                let run = Array(cells[i...j])
                out.append(GuideCell(start: run[0].start, end: run[run.count - 1].end, kind: .group, title: "\(run.count) short programmes",
                                     group: run.compactMap(\.programme)))
                i = j + 1
            } else {
                out.append(cells[i])
                i += 1
            }
        }
        return out
    }

    /// The cell at a time, or the first.
    public static func cell(at time: Int64, in cells: [GuideCell]) -> GuideCell? {
        cells.first { $0.start <= time && time < $0.end } ?? cells.first
    }

    /// Where the guide's window starts after moving by some seconds, held to how far it goes.
    public static func shifted(_ from: Int64, by seconds: Int64, now: Int64) -> Int64 {
        let low = floorSlot(now) - earliest, high = floorSlot(now) + latest
        return min(high, max(low, from + seconds))
    }

    /// "Tonight 8 PM" and "Tomorrow morning": times people actually jump to.
    public static func jumps(now: Int64, calendar: Calendar = .current) -> [(label: String, at: Int64)] {
        func at(_ days: Int, _ hour: Int) -> Int64 {
            let date = Date(timeIntervalSince1970: TimeInterval(now))
            let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) ?? date
            return Int64((calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day).timeIntervalSince1970)
        }
        let tonight = at(0, 20)
        return [tonight > now + 1800 ? ("Tonight 8 PM", tonight) : ("Tomorrow 8 PM", at(1, 20)), ("Tomorrow morning", at(1, 8))]
    }

    /// "Tonight", "Tomorrow", or the day's name: as someone would say it.
    public static func dayWord(_ time: Int64, now: Int64, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(time)))
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now)))
        let diff = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if diff == 0 { return calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(time))) >= 17 ? "Tonight" : "Today" }
        if diff == 1 { return "Tomorrow" }
        if diff == -1 { return "Yesterday" }
        return dayName(time)
    }

    /// "Wed, Nov 4".
    public static func dayName(_ time: Int64) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(time)))
    }

    /// "8:30 PM", as the device says times.
    public static func clock(_ time: Int64) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(time)))
    }

    public static func span(_ start: Int64, _ end: Int64) -> String { "\(clock(start)) to \(clock(end))" }

    /// "1h 28m": how long, in the fewest words that are still exact enough.
    public static func left(_ seconds: Int64) -> String {
        let m = max(1, Int((Double(seconds) / 60).rounded()))
        if m < 60 { return "\(m) min" }
        let h = m / 60
        return m % 60 == 0 ? "\(h)h" : "\(h)h \(m % 60)m"
    }

    /// The channels a filter shows.
    public static func matches(_ channel: GuideChannel, kind: String, group: String, favourites: Bool) -> Bool {
        (kind.isEmpty || channel.kind == kind)
            && (group.isEmpty || channel.group == group || (channel.categories ?? []).contains(group))
            && (!favourites || channel.favourite == true)
    }

    /// What the server is asked for: a stretch of the schedule, a page of channels, and a filter.
    public static func query(from: Int64, offset: Int, limit: Int = page, kind: String = "", group: String = "", favourites: Bool = false) -> String {
        "/guide?from=\(from)&hours=\(fetchHours)&offset=\(offset)&limit=\(limit)&kind=\(WittyClient.queryValue(kind))&group=\(WittyClient.queryValue(group))"
            + (favourites ? "&favourites=1" : "")
    }

    /// The programme after this one on the channel that's worth naming: not a slate or a gap.
    public static func next(after programme: GuideProgramme?, cell: GuideCell?, on channel: GuideChannel?) -> GuideProgramme? {
        guard let channel, let end = programme?.end ?? cell?.end else { return nil }
        return (channel.programmes ?? []).sorted { $0.start < $1.start }.first { $0.start >= end && $0.kind != "slate" && $0.kind != "none" }
    }
}

// MARK: - Recordings and reminders

/// One recording, past or to come. Each person sees their own; an administrator sees everyone's.
public struct Recording: Decodable, Equatable, Identifiable {
    public let id: Int64
    public let channelId: Int64?
    public let channel: String
    public let number: String?
    public let title: String
    public let sub: String?
    public let start: Int64
    public let stop: Int64
    /// `scheduled`, `recording`, `done`, `failed` or `cancelled`.
    public let status: String
    public let error: String?
    /// Only an administrator is told where its file is.
    public let path: String?
    public let sizeBytes: Int64?
    public let ruleId: Int64?

    public var isFinished: Bool { status == "done" || status == "failed" }

    public var statusWords: String {
        ["scheduled": "Scheduled", "recording": "Recording now", "done": "Done", "failed": "Failed", "cancelled": "Cancelled"][status] ?? status
    }

    /// "1.2 GB" or "340 MB".
    public var sizeWords: String {
        guard let b = sizeBytes, b > 0 else { return "" }
        return b > 1_000_000_000 ? String(format: "%.1f GB", Double(b) / 1e9) : "\(Int((Double(b) / 1e6).rounded())) MB"
    }
}

/// Every airing of a title on a channel.
public struct RecordingRule: Decodable, Equatable, Identifiable {
    public let id: Int64
    public let channelId: Int64?
    public let channel: String
    public let title: String
}

/// "Tell me when this starts", kept with the account.
public struct TvReminder: Decodable, Equatable, Identifiable {
    public let id: Int64
    public let channel: String
    public let title: String
    public let sub: String?
    public let start: Int64
    public let end: Int64
}

public enum ReminderRules {
    /// A reminder comes up this long before its programme starts.
    public static let lead: Int64 = 60
    /// And stays up this long after it has started.
    public static let stays: Int64 = 180

    /// The next reminder to come up, among those not already shown.
    public static func due(_ list: [TvReminder], shown: Set<Int64>, now: Int64) -> TvReminder? {
        list.filter { !shown.contains($0.id) && $0.end > now && $0.start - lead <= now && now < $0.start + stays }.min { $0.start < $1.start }
    }

    /// When to look again: the next reminder's moment, or nil when there's none to wait for.
    public static func nextCheck(_ list: [TvReminder], shown: Set<Int64>, now: Int64) -> Int64? {
        list.filter { !shown.contains($0.id) && $0.end > now }.map { max(now, $0.start - lead) }.min()
    }
}

/// Something coming up that matched a search of the schedule.
public struct GuideHit: Decodable, Equatable {
    public let channel: String
    public let number: String?
    public let name: String?
    public let start: Int64
    public let end: Int64
    public let title: String
    public let sub: String?
}

/// What the logo service has for a network or studio. It has nothing until the owner agrees to the download.
public struct LogoInfo: Decodable, Equatable {
    public let id: Int64?
    public let kind: String
    public let name: String
    public let has: Bool?
    public let version: Int64?
    /// A picture with its own background, shown on a plate.
    public let opaque: Bool?
}
