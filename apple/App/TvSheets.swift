#if os(tvOS)
import SwiftUI
import WittyKit

// What opens over the guide: more about a programme or the channel's whole day, searching the
// schedule, and the Look panel. As on the server's page (Details.tsx, SearchPanel.tsx and
// LookPanel.tsx), these are in the app's own colours, whichever look the guide has.

/// More about a programme, or the whole of the channel's day: one sheet, so one is a press from the other.
struct GuideDetails: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reminders = TvReminders.shared
    let ask: GuideAsk
    let now: Int64
    let onWatch: (String) -> Void
    let onSaid: (String) -> Void
    @State private var day = false
    @State private var desc = ""
    @State private var list: [GuideProgramme]?
    @State private var error = ""
    @Namespace private var scope

    private var channel: GuideChannel { ask.channel }
    private var p: GuideProgramme? { ask.programme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text(day ? "Channel \(channel.number ?? ""), \(channel.name)" : p?.title ?? ask.cell.title).font(.wmPage).accessibilityAddTraits(.isHeader)
                HStack(spacing: Tokens.Space.s4) {
                    Button("This programme") { day = false }.action(selected: !day)
                    Button("The whole day") { day = true }.action(selected: day)
                }
                .remoteSection()
                if day { dayList } else { one }
                actions
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
            .frame(maxWidth: 1300, alignment: .leading)
        }
        .focusRoot(scope)
        .background(palette.background.ignoresSafeArea())
        .onAppear { day = ask.day; desc = p?.desc ?? "" }
        .task {
            if desc.isEmpty, let id = p?.itemId, let item = try? await client.item(id) { desc = item.overview ?? "" }
        }
        .task(id: day) { if day, list == nil { await loadDay() } }
    }

    @ViewBuilder private var one: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if let sub = p?.sub, !sub.isEmpty { Text(sub).foregroundStyle(palette.textSecondary) }
            Text("Channel \(channel.number ?? ""), \(channel.name)" + (ask.cell.kind == .none ? "" : " · \(GuideRules.dayName(ask.cell.start)), \(GuideRules.span(ask.cell.start, ask.cell.end))") + (p?.rating.map { " · \($0)" } ?? ""))
                .foregroundStyle(palette.textSecondary)
            if ask.cell.kind == .group {
                ForEach(ask.cell.group, id: \.start) { x in
                    Text("\(tvClock(x.start))  \(x.title)" + (x.sub.map { " \($0)" } ?? ""))
                }
            }
            if !desc.isEmpty { Text(desc).fixedSize(horizontal: false, vertical: true) }
            if let s = channel.security, s.state == "encrypted" { (Text(s.label + ". ").bold() + Text(s.detail)) }
            if let s = channel.security, s.state == "unknown" { Text(s.detail).font(.wmSecondary).foregroundStyle(palette.textSecondary) }
            if let why = channel.noRecord, !why.isEmpty { Text("This channel can't be recorded: \(why).").font(.wmSecondary).foregroundStyle(palette.textSecondary) }
            ForEach(channel.notices ?? [], id: \.self) { Text($0).font(.wmSecondary).foregroundStyle(palette.textSecondary) }
            // Only ever an explanation: whether Record is offered is the server's canRecord alone.
            if channel.canRecord != true, channel.kind == "library" {
                Text("Library channels can't be recorded: what they play is already in your library.").font(.wmSecondary).foregroundStyle(palette.textSecondary)
            }
        }
    }

    @ViewBuilder private var dayList: some View {
        if !error.isEmpty {
            Text(error).foregroundStyle(palette.danger)
        } else if let list {
            if list.isEmpty { Text("Nothing is listed for this day.").foregroundStyle(palette.textSecondary) }
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                ForEach(list, id: \.start) { x in
                    let on = x.isOn(at: now)
                    HStack(spacing: Tokens.Space.s4) {
                        Text(tvClock(x.start)).monospacedDigit().foregroundStyle(palette.textSecondary).frame(width: 150, alignment: .leading)
                        (Text(x.title).bold() + Text(x.sub.map { " \($0)" } ?? "").foregroundColor(palette.textSecondary) + Text(on ? "  On now" : "").foregroundColor(palette.accentText))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if x.start > now, x.kind != "slate", channel.canTune {
                            Button(reminders.has(channel.key, x.start) ? "✓ Reminder set" : "Remind") {
                                Task { onSaid(await reminders.toggle(channel.key, x)) }
                            }
                            .action(selected: reminders.has(channel.key, x.start))
                            .accessibilityLabel("Remind me about \(x.title) at \(tvClock(x.start))")
                        }
                    }
                    .opacity(x.end <= now ? 0.6 : 1)
                    .padding(.horizontal, Tokens.Space.s2)
                    .background(on ? palette.accent.opacity(0.16) : .clear)
                }
            }
        } else {
            LoadingView()
        }
    }

    private var actions: some View {
        let later = ask.cell.start > now
        let reminded = p.map { reminders.has(channel.key, $0.start) } ?? false
        return FlowLayout(spacing: Tokens.Space.s4, rowSpacing: Tokens.Space.s4) {
            if !channel.canTune {} else {
                Button { onWatch(channel.key) } label: { Label("Watch channel now", systemImage: "play.fill") }
                    .action(primary: channel.alternative == nil).firstFocus(in: scope)
            }
            if let alt = channel.alternative {
                Button { onWatch(alt.key) } label: { Label("Watch \(alt.number) \(alt.name) instead", systemImage: "play.fill") }.action(primary: true)
            }
            if later, channel.canTune, ask.cell.kind == .programme, let p {
                Button(reminded ? "✓ Reminder set" : "Remind me") { Task { onSaid(await reminders.toggle(channel.key, p)) } }.action(selected: reminded)
            }
            if channel.canRecord == true, ask.cell.isBroadcast, ask.cell.end > now, let p {
                Button("Record every airing") {
                    Task {
                        do { try await client.recordSeries(channel: channel.key, title: p.title); onSaid("Every airing of \(p.title) will be recorded"); dismiss() }
                        catch { onSaid((error as? APIError)?.message ?? "That couldn't be recorded.") }
                    }
                }
                .action()
                Button("Record this") {
                    Task {
                        do { try await client.record(channel: channel.key, title: p.title, sub: p.sub, start: p.start, stop: p.end); onSaid("Recording \(p.title)"); dismiss() }
                        catch { onSaid((error as? APIError)?.message ?? "That couldn't be recorded.") }
                    }
                }
                .action()
            }
            if model.user?.isAdmin == true, channel.kind == "library" {
                NavigationLink("Edit channel", value: Route.page("/tv/channels")).action(.quiet)
            }
            Button("Close") { dismiss() }.action(.quiet)
        }
    }

    private func loadDay() async {
        let start = Int64(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(ask.cell.start))).timeIntervalSince1970)
        do {
            list = try await client.guideDay(channel.key, from: max(start, now - 86000))
            error = ""
        } catch {
            self.error = (error as? APIError)?.message ?? "The day couldn't be loaded."
        }
    }
}

/// Searching what's coming up, by title.
struct GuideSearch: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onGo: (GuideHit) -> Void
    @State private var words = ""
    @State private var hits: [GuideHit]?
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("Search the schedule").font(.wmPage).accessibilityAddTraits(.isHeader)
                TextField("A programme's name", text: $words).plainEntry().onSubmit { Task { await search() } }
                if !error.isEmpty { Text(error).foregroundStyle(palette.danger) }
                if let hits {
                    if hits.isEmpty { Text("Nothing coming up matches that.").foregroundStyle(palette.textSecondary) }
                    ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                        Button { onGo(hit) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.title).font(.wmLabel)
                                Text("\(GuideRules.dayName(hit.start)), \(GuideRules.span(hit.start, hit.end)) · \(hit.number ?? "") \(hit.name ?? "")")
                                    .font(.wmSecondary).foregroundStyle(palette.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Tokens.Space.s3)
                        }
                        .buttonStyle(SurfaceStyle(fill: palette.card))
                    }
                }
                Button("Close") { dismiss() }.action(.quiet)
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
            .frame(maxWidth: 1300, alignment: .leading)
        }
        .background(palette.background.ignoresSafeArea())
    }

    private func search() async {
        do {
            hits = try await client.searchGuide(words)
            error = ""
        } catch {
            self.error = (error as? APIError)?.message ?? "The schedule couldn't be searched."
        }
    }
}

/// WittyTV's look: one big choice, the theme, each drawn as a small picture of itself, then the rest.
/// Everything shows at once and is kept with the account, as on the page.
struct TvLookPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var looks = TvLookStore.shared
    @Namespace private var scope

    private var look: TvLookChoice { looks.look }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                Text("Look").font(.wmPage).accessibilityAddTraits(.isHeader)
                Text(sourceWords).foregroundStyle(palette.textSecondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32), count: 3), spacing: 32) {
                    ForEach(TvTheme.all) { theme in
                        Button { looks.pick(theme.id, client: client) } label: { ThemeCard(theme: theme, on: look.theme == theme.id, current: look) }
                            .buttonStyle(SurfaceStyle(fill: palette.panel, radius: Tokens.Radius.lg))
                            .firstFocus(in: scope, when: look.theme == theme.id)
                            .accessibilityAddTraits(look.theme == theme.id ? [.isSelected] : [])
                    }
                }
                .remoteSection()
                if look.source == .you {
                    Button("Follow the app's theme and the server's choice again") { looks.change(["theme": nil], client: client) }.action(.quiet)
                }
                if look.theme == "custom" {
                    choice("Layout", value: look.shape.rawValue, options: TvShape.allCases.map { ($0.rawValue, $0.name) }) { shape in
                        looks.change(["custom": ["shape": shape, "font": look.font]], client: client)
                    }
                    choice("Type", value: look.font, options: [("", "As the layout has it"), ("system", "Plain"), ("narrow", "Narrow"), ("mono", "Typewriter"), ("serif", "Newspaper")]) { font in
                        looks.change(["custom": ["shape": look.shape.rawValue, "font": font]], client: client)
                    }
                }
                choice("Row size", value: look.density, options: [("compact", "Compact"), ("normal", "Normal"), ("large", "Large")]) { looks.change(["density": $0], client: client) }
                choice("Hours across", value: String(look.hours), options: [("0.0", "What fits"), ("1.5", "1½"), ("2.0", "2"), ("3.0", "3"), ("4.0", "4")]) {
                    looks.change(["hours": Double($0) ?? 0], client: client)
                }
                choice("Preview", value: look.preview, options: [("highlight", "What's highlighted"), ("last", "The last channel"), ("off", "Off")]) { looks.change(["preview": $0], client: client) }
                choice("Preview side", value: look.previewSide, options: [("left", "Left"), ("right", "Right")]) { looks.change(["previewSide": $0], client: client) }
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    toggle("The line at the current time", look.nowLine, "nowLine")
                    toggle("How far into what's on now", look.progress, "progress")
                    toggle("Episode names and details in the grid", look.subtitles, "subtitles")
                    toggle("Channel logos", look.logos, "logos")
                    toggle("The programme's picture at the top", look.art, "art")
                    toggle("Preview sound", look.previewSound, "previewSound")
                }
                Text("Colours are chosen on the server's page, under Look, and they come here too.").font(.wmSecondary).foregroundStyle(palette.textSecondary)
                Button("Done") { dismiss() }.action(primary: true, pill: true)
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
        }
        .focusRoot(scope)
        .background(palette.background.ignoresSafeArea())
    }

    private var sourceWords: String {
        switch look.source {
        case .you: return "You chose this. It's kept with your account, on every device."
        case .app: return "The app's theme suggests this one, until you choose."
        case .owner: return "This server's owner starts everyone on this one, until you choose."
        }
    }

    private func choice(_ title: String, value: String, options: [(String, String)], set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(title).font(.wmSection)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.s4) {
                    ForEach(options, id: \.0) { o in
                        Button(o.1) { set(o.0) }.action(selected: value == o.0, pill: true)
                            .accessibilityAddTraits(value == o.0 ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, Tokens.Space.s6)
                .padding(.horizontal, Tokens.Space.s2)
            }
            .remoteSection()
        }
    }

    private func toggle(_ title: String, _ on: Bool, _ key: String) -> some View {
        Button { looks.change([key: !on], client: client) } label: {
            Label(title, systemImage: on ? "checkmark.square.fill" : "square")
        }
        .action(selected: on)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// A theme drawn as a small picture of itself: the guide's own proportions, in its own colours.
private struct ThemeCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let theme: TvTheme
    let on: Bool
    let current: TvLookChoice

    var body: some View {
        let shape = theme.id == "custom" ? current.shape : theme.shape
        let colours = TvLook.resolve(saved: TvSaved(theme: theme.id, themeColours: on ? [theme.id: current.overrides] : nil), ownerTheme: nil, ownerLayout: nil, ownerSkin: nil, app: model.tvAppColours).colours
        let p = TvPaint(colours)
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            picture(shape, p)
            HStack {
                Text(theme.name).font(.wmLabel.weight(.bold))
                Spacer()
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accent) }
            }
            Text(theme.blurb).font(.wmCardSub).foregroundStyle(palette.textSecondary).lineLimit(3, reservesSpace: true)
        }
        .padding(Tokens.Space.s3)
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg).strokeBorder(on ? palette.accent : .clear, lineWidth: 3))
    }

    private func picture(_ shape: TvShape, _ p: TvPaint) -> some View {
        let r: CGFloat = [.receiver, .teletext, .listings].contains(shape) ? 0 : 3
        let previewLeft = shape == .cinema
        return GeometryReader { box in
            let w = box.size.width, h = box.size.height
            ZStack(alignment: .topLeading) {
                p.bg
                RoundedRectangle(cornerRadius: r).fill(shape == .teletext ? p.accent : p.text).frame(width: w * 0.34, height: h * 0.08).offset(x: w * (previewLeft ? 0.62 : 0.06), y: h * 0.13)
                RoundedRectangle(cornerRadius: r).fill(p.soft).frame(width: w * 0.24, height: h * 0.04).offset(x: w * (previewLeft ? 0.62 : 0.06), y: h * 0.26)
                RoundedRectangle(cornerRadius: shape == .modern ? 20 : r).fill(p.hi).frame(width: w * 0.14, height: h * 0.07).offset(x: w * (previewLeft ? 0.62 : 0.06), y: h * 0.34)
                Rectangle().fill(Color.white.opacity(0.18)).overlay(Rectangle().strokeBorder(p.line, lineWidth: 1))
                    .frame(width: w * (previewLeft ? 0.52 : shape == .compact ? 0.2 : 0.36), height: h * (previewLeft ? 0.56 : shape == .compact ? 0.22 : 0.34))
                    .offset(x: previewLeft ? w * 0.05 : w * (shape == .compact ? 0.74 : 0.58), y: h * 0.08)
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: shape == .receiver || shape == .listings || shape == .teletext ? 0 : w * 0.01) {
                        RoundedRectangle(cornerRadius: r).fill(shape == .outline ? .clear : p.ch).frame(width: w * 0.18)
                            .overlay(RoundedRectangle(cornerRadius: r).strokeBorder(shape == .outline ? p.line : .clear, lineWidth: 1))
                        RoundedRectangle(cornerRadius: r).fill(i == 1 ? p.hi : shape == .outline ? .clear : p.live).frame(width: w * 0.3)
                            .overlay(RoundedRectangle(cornerRadius: r).strokeBorder(shape == .outline && i != 1 ? (i == 0 ? p.accent : p.line) : .clear, lineWidth: 1))
                        RoundedRectangle(cornerRadius: r).fill(shape == .outline ? .clear : p.cell)
                            .overlay(RoundedRectangle(cornerRadius: r).strokeBorder(shape == .outline ? p.line : .clear, lineWidth: 1))
                    }
                    .frame(width: w * 0.88, height: h * (shape == .compact ? 0.07 : previewLeft ? 0.09 : 0.12))
                    .offset(x: w * 0.06, y: h * ((previewLeft ? 0.67 : shape == .compact ? 0.32 : 0.48) + Double(i) * (previewLeft ? 0.11 : shape == .compact ? 0.12 : 0.15)))
                }
                if shape != .teletext, shape != .listings {
                    p.accent.frame(width: max(1, w * 0.01), height: h * (previewLeft ? 0.32 : 0.48)).offset(x: w * 0.42, y: h * (previewLeft ? 0.65 : 0.44))
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        .accessibilityHidden(true)
    }
}
#endif
