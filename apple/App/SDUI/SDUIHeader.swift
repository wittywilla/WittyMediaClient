// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// The buttons of a hero's slide or a title's header, in a row: the primary one filled and first to take focus.
/// One the app can't carry out on this device isn't drawn.
struct SDUIActionRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    let buttons: [SDUIButtonModel]
    /// The ID of the node these belong to: its focus stop lands on the primary button.
    let owner: String
    var ownerFocusable = true
    /// Left or right pressed on the first or last button, on Apple TV: a hero changes title.
    var beyond: ((Int) -> Void)?
    /// Told whether one of these has focus: a hero never advances while one has.
    var focusChanged: ((Bool) -> Void)?
    @FocusState private var inside: String?

    private var actor: SDUIActor { SDUIActor(model: model, center: center, store: store) }
    private var usable: [SDUIButtonModel] { buttons.filter { actor.canPerform($0.action) } }

    var body: some View {
        let shown = usable
        let lead = shown.first(where: \.primary)?.id ?? shown.first?.id
        HStack(spacing: layout.sp(layout.isTV ? "s" : "xs")) {
            ForEach(shown) { button in
                Button { actor.perform(button.action) } label: {
                    Label(button.label, systemImage: SDUIIcon.symbol(button.icon.isEmpty ? button.id : button.icon, or: "circle"))
                }
                .action(primary: button.primary, selected: button.pressed, pill: true)
                .focused($inside, equals: button.id)
                .sduiFocusable(button.id == lead && ownerFocusable ? focus : nil, owner)
                .accessibilityLabel(button.label)
                .accessibilityAddTraits(button.pressed ? [.isSelected] : [])
                .accessibilityIdentifier("sdui.action." + button.id)
            }
        }
        .remoteSection()
        .sduiOnChange(of: inside) { focusChanged?($0 != nil) }
        #if os(tvOS)
        .onMoveCommand { direction in
            guard let beyond, let inside, let at = shown.firstIndex(where: { $0.id == inside }) else { return }
            if direction == .right, at == shown.count - 1 { beyond(1) }
            if direction == .left, at == 0 { beyond(-1) }
        }
        #endif
    }
}

// MARK: - Hero

/// A large rotating spotlight of a few titles. On Apple TV: the hero's own height from the page, the backdrop
/// across it behind a scrim, the logo or title, facts, at most three lines of synopsis and the buttons in a row;
/// left and right past the buttons' ends change title. On a touch screen: the backdrop in the hero's shape with
/// the words over a scrim at its foot, swiped sideways, with page dots. It never moves by itself while one of
/// its buttons has focus, while it's off screen, or when motion is reduced.
struct SDUIHeroView: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiWidth) private var pageWidth
    @Environment(\.sduiOnImage) private var onImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hero: SDUIElement
    @State private var index = 0
    @State private var held = false
    @State private var onScreen = false

    private var slides: [SDUIElement] { hero.children }
    private var current: SDUIElement? { slides.indices.contains(index) ? slides[index] : slides.first }
    private var seconds: Int { hero.props.whole("autoAdvanceSec") ?? 0 }
    private var still: Bool { reduceMotion || layout.reducedMotion == true }
    private var size: CGSize {
        let w = CGFloat(hero.cardWidth > 0 ? hero.cardWidth : 16), h = CGFloat(hero.cardHeight > 0 ? hero.cardHeight : 9)
        if layout.isTV { return CGSize(width: w, height: h) }
        // The hero's shape at the window's width.
        let width = pageWidth > 0 ? pageWidth : w
        // Never shorter than its words need: a page narrowed by an open menu, a drawer or a split view would otherwise give a
        // hero too short for its title, facts and dots (title lines wrap, the art keeps filling the width).
        let least: CGFloat = width < 520 ? 280 : 240
        return CGSize(width: width, height: max((width * h / w).rounded(), least))
    }

    private func step(_ by: Int) {
        guard slides.count > 1 else { return }
        let next = (index + by + slides.count) % slides.count
        if still { index = next } else { withAnimation(.easeInOut(duration: 0.35)) { index = next } }
    }

    var body: some View {
        Group {
            if slides.isEmpty {
                // Nothing to feature: a hero with no titles is left out.
                EmptyView()
            } else {
                #if os(tvOS)
                television
                #else
                touch
                #endif
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hero.label)
        .accessibilityIdentifier("sdui.section." + hero.id)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .sduiOnChange(of: slides.count) { count in if index >= count { index = 0 } }
        .task(id: "\(seconds)|\(held)|\(onScreen)|\(still)|\(slides.count)") {
            guard seconds > 0, !held, onScreen, !still, slides.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                if Task.isCancelled { return }
                step(1)
            }
        }
    }

    private func words(_ slide: SDUIElement, over: Bool) -> some View {
        VStack(alignment: .leading, spacing: layout.sp("xs")) {
            if hero.props.flag("showLogo") != false, slide.poster != nil {
                SDUIPicture(picture: slide.poster, contain: true, blank: true)
                    .frame(width: layout.isTV ? 520 : 220, height: layout.isTV ? 160 : 72, alignment: .leading)
                    .accessibilityHidden(true)
            } else {
                Text(slide.shown("title"))
                    .sduiFont("heading")
                    .foregroundStyle(over ? onImage : palette.text)
                    .sduiLines(slide.lineLimit("title"))
                    .accessibilityAddTraits(.isHeader)
            }
            if !slide.shown("facts").isEmpty {
                Text(slide.shown("facts")).sduiFont("caption").foregroundStyle(over ? onImage.opacity(0.85) : palette.textSecondary).lineLimit(1)
            }
            if !slide.shown("synopsis").isEmpty, hero.props.flag("showSynopsis") != false {
                Text(slide.shown("synopsis"))
                    .sduiFont(layout.isTV ? "body" : "caption")
                    .foregroundStyle(over ? onImage.opacity(0.9) : palette.textSecondary)
                    .sduiLines(slide.lineLimit("synopsis"))
                    .multilineTextAlignment(.leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slide.label)
    }

    #if os(tvOS)
    @ViewBuilder private var television: some View {
        if let slide = current {
            VStack(alignment: .leading, spacing: layout.sp("s")) {
                Spacer(minLength: 0)
                words(slide, over: false).frame(maxWidth: Tokens.heroTextWidth, alignment: .leading)
                SDUIActionRow(buttons: slide.buttons, owner: hero.id, ownerFocusable: hero.isFocusable, beyond: { step($0) }, focusChanged: { held = $0 })
                if slides.count > 1 { dots }
            }
            .padding(.horizontal, layout.margin)
            .padding(.bottom, layout.sp("s"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: size.height)
            .background {
                SDUIPicture(picture: slide.picture, blank: true)
                    .id(slide.id)
                    .transition(.opacity)
                    .overlay(LinearGradient(stops: [.init(color: palette.background, location: 0), .init(color: palette.background.opacity(0.6), location: 0.4),
                                                    .init(color: .clear, location: 0.8)], startPoint: .leading, endPoint: .trailing))
                    .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.6), .init(color: palette.background, location: 1)],
                                            startPoint: .top, endPoint: .bottom))
                    .clipped()
                    .accessibilityHidden(true)
            }
        }
    }
    #else
    private var touch: some View {
        VStack(alignment: .leading, spacing: layout.sp("s")) {
            TabView(selection: $index) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { at, slide in
                    SDUIPicture(picture: slide.picture, symbol: "film", shownWidth: size.width)
                        .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: palette.scrim, location: 1)],
                                                startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .bottomLeading) {
                            words(slide, over: true)
                                // A third of the width on a wide page; the whole width (less the margins) once the page is narrow, so
                                // the title wraps instead of running into the art's other parts.
                                .frame(maxWidth: layout.phone || size.width < 760 ? .infinity : max(size.width / 3, 320), alignment: .leading)
                                .padding(layout.margin)
                                .padding(.bottom, slides.count > 1 ? 16 : 0)
                        }
                        .clipped()
                        .tag(at)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: slides.count > 1 ? .always : .never))
            .frame(height: size.height)
            // A slice of the next slide at the trailing edge (`peek`): there is more to swipe to.
            .overlay(alignment: .trailing) {
                if hero.peek > 0, index + 1 < slides.count {
                    SDUIPicture(picture: slides[index + 1].picture, symbol: "film", shownWidth: size.width)
                        .frame(width: size.width, height: size.height)
                        .frame(width: size.width * CGFloat(hero.peek), alignment: .leading)
                        .clipped()
                        .overlay(alignment: .leading) { Rectangle().fill(palette.background).frame(width: 2) }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // A finger on it holds it where it is.
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in held = true }.onEnded { _ in held = false })
            if let slide = current, !slide.buttons.isEmpty {
                SDUIActionRow(buttons: slide.buttons, owner: hero.id, ownerFocusable: false).padding(.horizontal, layout.margin)
            }
        }
    }
    #endif

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { at in
                Circle().fill(at == index ? palette.text : palette.textHint.opacity(0.5)).frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Title \(index + 1) of \(slides.count)")
    }
}

// MARK: - A title's header

/// The top of a title's page: its art, name, facts, synopsis and the buttons that play it and act on it.
/// On Apple TV the backdrop runs across the screen under a scrim with the words at the left and Play focused.
/// On a phone the backdrop is at the top with everything under it and a full-width main button; a tablet has
/// the poster beside the words.
struct SDUIDetailHeaderView: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiWidth) private var pageWidth
    @Environment(\.sduiFocus) private var focus
    let header: SDUIElement
    @State private var whole = false

    private var actor: SDUIActor { SDUIActor(model: model, center: center, store: store) }
    private var style: String { header.props.text("layout") }

    private var words: some View {
        VStack(alignment: .leading, spacing: layout.sp("xs")) {
            Text(header.shown("title"))
                .sduiFont("pageTitle")
                .foregroundStyle(palette.text)
                .sduiLines(header.lineLimit("title"))
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(.h1)
            if !header.shown("tagline").isEmpty {
                Text(header.shown("tagline")).sduiFont("body").italic().foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            if !header.shown("facts").isEmpty {
                Text(header.shown("facts")).sduiFont("caption").foregroundStyle(palette.textSecondary).lineLimit(layout.isTV ? 1 : 2)
            }
            if let percent = header.progress, percent > 0 {
                ProgressStrip(fraction: Double(percent) / 100, track: palette.border).frame(maxWidth: 320)
                    .accessibilityElement().accessibilityLabel("\(percent) percent watched")
            }
        }
    }

    @ViewBuilder private var overview: some View {
        if !header.shown("overview").isEmpty {
            VStack(alignment: .leading, spacing: layout.sp("xs")) {
                Text(header.shown("overview"))
                    .sduiFont("body")
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(whole ? nil : header.lineLimit("overview"))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                #if !os(tvOS)
                // "More" reads the rest, where four lines weren't enough.
                if !whole, header.shown("overview").count > 180 {
                    Button("More") { whole = true }
                        .sduiFont("caption", weight: .semibold)
                        .foregroundStyle(palette.accentText)
                        .frame(minHeight: 44, alignment: .leading)
                        .buttonStyle(.plain)
                }
                #endif
            }
            .frame(maxWidth: CGFloat(layout.textSize("body")) * 38, alignment: .leading)
        }
    }

    var body: some View {
        Group {
            #if os(tvOS)
            television
            #else
            touch
            #endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(header.label)
        .accessibilityIdentifier("sdui.section." + header.id)
    }

    #if os(tvOS)
    private var television: some View {
        HStack(alignment: .bottom, spacing: layout.sp("m")) {
            if style == "poster", header.poster != nil {
                SDUIPicture(picture: header.poster, shownWidth: 300)
                    .frame(width: 300, height: 450)
                    .clipShape(RoundedRectangle(cornerRadius: draw.radius("DetailHeader", "poster"), style: .continuous))
            }
            VStack(alignment: .leading, spacing: layout.sp("s")) {
                Spacer(minLength: 0)
                words
                overview
                SDUIActionRow(buttons: header.buttons, owner: header.id, ownerFocusable: header.isFocusable)
            }
            .frame(maxWidth: 1100, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.margin)
        .padding(.top, CGFloat(layout.safeArea.top))
        .padding(.bottom, layout.sp("s"))
        .frame(maxWidth: .infinity, minHeight: style == "compact" ? 360 : 700, alignment: .bottomLeading)
        .background {
            if style != "compact" {
                SDUIPicture(picture: header.picture ?? header.poster, blank: true)
                    .overlay { CanvasLayer(item: store.params["item"].flatMap { Int64($0) }, active: !model.listening.screenShown) }
                    .opacity(0.55)
                    .overlay(LinearGradient(stops: [.init(color: palette.background, location: 0), .init(color: .clear, location: 0.8)],
                                            startPoint: .leading, endPoint: .trailing))
                    .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: palette.background, location: 1)],
                                            startPoint: .top, endPoint: .bottom))
                    .clipped()
                    .accessibilityHidden(true)
            }
        }
    }
    #else
    private var usable: [SDUIButtonModel] { header.buttons.filter { actor.canPerform($0.action) } }

    private var touch: some View {
        let wide = !layout.compact
        let main = usable.first(where: \.primary) ?? usable.first
        let others = usable.filter { $0.id != main?.id }
        return VStack(alignment: .leading, spacing: layout.sp("m")) {
            if style != "compact", header.picture != nil || header.poster != nil {
                let width = pageWidth > 0 ? pageWidth : 390
                SDUIPicture(picture: header.picture ?? header.poster, symbol: "film", shownWidth: width)
                    .frame(height: min(width * 9 / 16, 460))
                    // The title's canvas, where it has one, loops over the still (MediaCanvas.swift decides when).
                    .overlay { CanvasLayer(item: store.params["item"].flatMap { Int64($0) }, active: !model.listening.screenShown) }
                    .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: palette.background, location: 1)],
                                            startPoint: .top, endPoint: .bottom))
                    .clipped()
            }
            HStack(alignment: .top, spacing: layout.sp("m")) {
                if (wide || style == "poster"), header.poster != nil, style != "compact" {
                    let side: CGFloat = wide ? 200 : 110
                    SDUIPicture(picture: header.poster, shownWidth: side)
                        .frame(width: side, height: side / CGFloat(header.poster?.ratio ?? 2.0 / 3.0))
                        .clipShape(RoundedRectangle(cornerRadius: draw.radius("DetailHeader", "poster"), style: .continuous))
                }
                VStack(alignment: .leading, spacing: layout.sp("m")) {
                    words
                    if let main {
                        Button { actor.perform(main.action) } label: {
                            Label(main.label, systemImage: SDUIIcon.symbol(main.icon.isEmpty ? main.id : main.icon, or: "play.fill"))
                        }
                        .pageButton(.primary, wide: !wide)
                        .accessibilityLabel(main.label)
                        .accessibilityIdentifier("sdui.action." + main.id)
                    }
                    if !others.isEmpty {
                        // The other actions: icons with their names under them.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: layout.sp("m")) {
                                ForEach(others) { button in
                                    Button { actor.perform(button.action) } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: SDUIIcon.symbol(button.icon.isEmpty ? button.id : button.icon, or: "circle"))
                                                .font(.system(size: 20, weight: .medium))
                                                .frame(width: 44, height: 32)
                                            Text(button.label).sduiFont("caption").lineLimit(1)
                                        }
                                        // On (Watch later with the title on the list): in the accent.
                                        .foregroundStyle(button.pressed ? palette.accentText : palette.text)
                                        .frame(minWidth: 64, minHeight: 56)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(button.label)
                                    .accessibilityAddTraits(button.pressed ? [.isSelected] : [])
                                    .accessibilityIdentifier("sdui.action." + button.id)
                                }
                            }
                        }
                    }
                    overview
                }
            }
            .padding(.horizontal, layout.margin)
        }
    }
    #endif
}

// MARK: - Banner

/// One wide promotional block: a picture, a title, a line of text and one button. The whole banner is the button.
struct SDUIBannerView: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    @Environment(\.sduiOnImage) private var onImage
    @Environment(\.sduiWidth) private var pageWidth
    let banner: SDUIElement

    private var compact: Bool { banner.props.text("style") == "compact" }
    private var hasPicture: Bool { banner.picture != nil }

    private func words(over: Bool) -> some View {
        VStack(alignment: .leading, spacing: layout.sp("xs")) {
            if !banner.shown("title").isEmpty {
                Text(banner.shown("title")).sduiFont(layout.isTV ? "heading" : "title").foregroundStyle(over ? onImage : palette.text)
                    .sduiLines(banner.lineLimit("title")).multilineTextAlignment(.leading)
            }
            if !banner.shown("text").isEmpty {
                Text(banner.shown("text")).sduiFont("body").foregroundStyle(over ? onImage.opacity(0.9) : palette.textSecondary)
                    .sduiLines(banner.lineLimit("text")).multilineTextAlignment(.leading)
            }
            if !banner.shown("button").isEmpty {
                Text(banner.shown("button"))
                    .sduiFont("body", weight: .semibold)
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, layout.sp("m"))
                    .frame(minHeight: layout.isTV ? 66 : 44)
                    .background(Capsule().fill(palette.accent))
                    .padding(.top, layout.sp("xs"))
            }
        }
    }

    @ViewBuilder private var block: some View {
        if layout.isTV {
            // A television's banner: 300 points tall across the content, the picture behind a scrim.
            HStack { words(over: hasPicture && !compact); Spacer(minLength: 0) }
                .padding(layout.sp("m"))
                .frame(maxWidth: .infinity, minHeight: compact ? 200 : 300, alignment: .leading)
                .background {
                    if hasPicture, !compact {
                        SDUIPicture(picture: banner.picture, blank: true)
                            .overlay(LinearGradient(colors: [palette.scrim, .clear], startPoint: .leading, endPoint: .trailing))
                    } else {
                        palette.panel
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: draw.radius("Banner"), style: .continuous))
        } else if compact {
            // A 96-point row with a square picture.
            HStack(spacing: layout.sp("s")) {
                if hasPicture {
                    SDUIPicture(picture: banner.picture, shownWidth: 96).frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: draw.radius("Banner", "thumb"), style: .continuous))
                } else if !banner.icon.isEmpty {
                    Image(systemName: SDUIIcon.symbol(banner.icon)).font(.system(size: 28, weight: .medium)).foregroundStyle(palette.accentText)
                        .frame(width: 64, height: 64)
                }
                words(over: false)
                Spacer(minLength: 0)
            }
            .padding(layout.sp("s"))
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: draw.radius("Banner"), style: .continuous).fill(palette.panel))
        } else {
            // A full-width 16/9 card.
            let width = max(pageWidth - layout.margin * 2, 200)
            Color.clear
                .frame(height: min(width * 9 / 16, 360))
                .frame(maxWidth: .infinity)
                .overlay {
                    if hasPicture {
                        SDUIPicture(picture: banner.picture, shownWidth: width)
                            .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: palette.scrim, location: 1)], startPoint: .top, endPoint: .bottom))
                    } else {
                        palette.panel
                    }
                }
                .overlay(alignment: .bottomLeading) { words(over: hasPicture).padding(layout.sp("m")) }
                .clipShape(RoundedRectangle(cornerRadius: draw.radius("Banner"), style: .continuous))
        }
    }

    var body: some View {
        Group {
            if banner.action != nil {
                Button { SDUIActor(model: model, center: center, store: store).perform(banner.action) } label: { block }
                    .tileStyle()
                    .sduiFocusable(banner.isFocusable ? focus : nil, banner.id)
                    .accessibilityAddTraits(.isButton)
            } else {
                block
            }
        }
        .padding(.horizontal, layout.margin)
        .padding(.vertical, layout.isTV ? Tokens.focusRoom / 2 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(banner.label)
        .accessibilityIdentifier("sdui.section." + banner.id)
    }
}
