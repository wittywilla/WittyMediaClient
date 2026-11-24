// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// The parts of Design 2's "Choose a server" (the design canvas's `sConnect`): section labels with a hairline, a card
// for each server, and one distinct panel for connecting from anywhere, peer to peer. The same on a phone, a tablet, a
// Mac and a TV, with a TV's room.

/// The page around it: the app's wordmark centred, "Choose a server" and its line, then the sections, one column on
/// a phone and no wider than reads well elsewhere. Drawn on DesignPage's sizes and colours. A standalone page, so it is
/// centred throughout on every device (`designCentred`): section labels, notes and the foot follow the head, while
/// the cards and rows fill the width.
struct ConnectFrame<Content: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            let sizes = DesignSizes.of(metrics, width: geo.size.width)
            ScrollView {
                VStack(alignment: .center, spacing: 0) {
                    VStack(spacing: sizes.gap) {
                        BrandLockup(app: true)
                        Text(say("findTitle"))
                            .font(.system(size: sizes.title, weight: .heavy, design: .rounded))
                            .kerning(-sizes.title * 0.04)
                            .foregroundStyle(palette.text)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("connect-title")
                        Text(say("findSubtitle").replacingOccurrences(of: "'", with: "’"))
                            .font(.system(size: sizes.body))
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, sizes.gap)
                    content
                }
                .frame(maxWidth: metrics.tv ? 1200 : 680, alignment: .center)
                .padding(.horizontal, metrics.tv ? Tokens.gutter : metrics.gutter)
                .padding(.vertical, metrics.tv ? Tokens.edge : Tokens.Space.s8)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboardIfAvailable()
            .environment(\.designSizes, sizes)
            .environment(\.designCentred, true)
        }
        .background(palette.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connect")
    }
}

/// "YOUR SERVERS", "ON THIS NETWORK": small capitals, then a hairline to the edge. On a centred page (Choose a server)
/// the label sits in the middle with a hairline on both sides.
struct ConnectSectionLabel: View {
    @Environment(\.palette) private var palette
    @Environment(\.designSizes) private var sizes
    @Environment(\.designCentred) private var centred
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: sizes.gap) {
            if centred { Rectangle().fill(palette.border).frame(height: 1).accessibilityHidden(true) }
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: sizes.tiny, weight: .bold))
                .kerning(sizes.tiny * 0.08)
                .foregroundStyle(palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(palette.border).frame(height: 1).accessibilityHidden(true)
            if let trailing { trailing }
        }
        .padding(.top, sizes.gap2)
        .padding(.bottom, sizes.gap * 0.4)
    }
}

/// How a server is reached, for its card's line, its chip and its status dot.
enum ServerReach {
    /// On this network now (green).
    case home
    /// From anywhere, peer to peer (blue).
    case peer
    /// Found on this network, not added yet.
    case found
    /// Added, and not seen on this network just now.
    case saved

    var icon: String {
        switch self {
        case .home, .saved: return "house"
        case .peer: return "globe"
        case .found: return "wifi"
        }
    }

    var chip: String {
        switch self {
        case .home: return "Home network"
        case .peer: return "Peer to peer"
        case .found: return "Connect"
        case .saved: return ""
        }
    }
}

/// One server: a gradient avatar (its logo, else its first letter) with a status dot, its name, a line with a small
/// icon, a chip and a chevron. The chosen one is ringed and lifted.
struct ServerTile: View {
    @Environment(\.palette) private var palette
    @Environment(\.designSizes) private var sizes
    @Environment(\.metrics) private var metrics
    var saved: SavedServer?
    let name: String
    let line: String
    let reach: ServerReach
    var selected = false
    var connecting = false
    let action: () -> Void

    private var hue: Double { GameShelves.titleHue(name) / 360 }

    private var avatar: some View {
        let side: CGFloat = metrics.tv ? 64 : 44
        return ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.85),
                                                      Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.5)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                if let saved, LogoCache.image(server: saved.url, version: saved.brandLogo) != nil {
                    ServerLogo(server: saved, size: side * 0.62)
                } else {
                    Text(String(name.first ?? "W").uppercased())
                        .font(.system(size: side * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, height: side)
            if reach == .home || reach == .peer {
                Circle()
                    .fill(reach == .home ? palette.ok : Color.blue)
                    .frame(width: side * 0.28, height: side * 0.28)
                    .overlay(Circle().stroke(palette.card, lineWidth: 2.5))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var chip: some View {
        if !reach.chip.isEmpty {
            Text(reach.chip)
                .font(.system(size: sizes.tiny, weight: .bold))
                .foregroundStyle(reach == .peer ? palette.accentText : palette.text)
                .padding(.horizontal, sizes.gap * 0.9)
                .padding(.vertical, 4)
                .background(Capsule().fill(reach == .peer ? palette.accent.opacity(0.18) : Color(white: 0.5).opacity(0.22)))
                .lineLimit(1)
                .fixedSize()
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: sizes.gap * 1.2) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: sizes.body, weight: .bold)).foregroundStyle(palette.text).lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: reach.icon).font(.system(size: sizes.tiny, weight: .semibold))
                        Text(line).lineLimit(2)
                    }
                    .font(.system(size: sizes.tiny))
                    .foregroundStyle(palette.text.opacity(0.7))
                }
                Spacer(minLength: sizes.gap)
                if connecting {
                    ProgressView().tint(palette.textSecondary)
                } else {
                    chip
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: sizes.tiny, weight: .bold))
                    .foregroundStyle(palette.textHint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, sizes.gap * 1.4)
            .padding(.vertical, sizes.gap * 1.1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DesignRowButton(selected: selected))
        .shadow(color: .black.opacity(selected ? 0.28 : 0), radius: selected ? 14 : 0, y: selected ? 6 : 0)
        .accessibilityLabel([name, line, reach.chip].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The one distinct panel: connecting from anywhere, peer to peer. A globe badge, what it is, a small picture of the
/// connection, the ways in as real buttons, and three promises with ticks.
struct ConnectAnywherePanel<Buttons: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.designSizes) private var sizes
    @Environment(\.metrics) private var metrics
    @ViewBuilder let buttons: Buttons

    private var device: String {
        #if os(tvOS)
        return "appletv"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
    }

    private func node(_ symbol: String, _ words: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: sizes.body * 1.3, weight: .semibold)).foregroundStyle(palette.text)
            Text(words).font(.system(size: sizes.tiny, weight: .semibold)).foregroundStyle(palette.textSecondary).lineLimit(1)
        }
        .fixedSize()
    }

    private var dashes: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(palette.textHint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .frame(height: 10)
    }

    private var diagram: some View {
        HStack(spacing: sizes.gap * 0.6) {
            node(device, "This device")
            dashes
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                Text("Encrypted")
            }
            .font(.system(size: sizes.tiny, weight: .bold))
            .foregroundStyle(palette.ok)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(palette.ok.opacity(0.16)))
            .fixedSize()
            dashes
            node("server.rack", "Your server")
        }
        .padding(.vertical, sizes.gap * 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This device connects to your server over an encrypted connection.")
    }

    private func promise(_ words: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.ok).accessibilityHidden(true)
            Text(words).foregroundStyle(palette.text)
        }
        .font(.system(size: sizes.tiny, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(white: 0.5).opacity(0.14)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: sizes.gap * 1.2) {
            HStack(alignment: .top, spacing: sizes.gap * 1.2) {
                Image(systemName: "globe")
                    .font(.system(size: sizes.body * 1.4, weight: .semibold))
                    .foregroundStyle(palette.accentText)
                    .frame(width: sizes.body * 2.6, height: sizes.body * 2.6)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.accent.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect from anywhere")
                        .font(.system(size: sizes.body * 1.15, weight: .heavy))
                        .foregroundStyle(palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Reach your server over the internet with a private peer to peer connection, with nothing to set up on your router.")
                        .font(.system(size: sizes.small))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            diagram
            // Stacked full width on a phone; side by side with more room.
            Group {
                if sizes.columns == 2 && !metrics.tv {
                    VStack(spacing: sizes.gap * 0.8) { buttons }
                } else {
                    HStack(spacing: sizes.gap) { buttons }
                }
            }
            .remoteSection()
            FlowLayout(spacing: 8, rowSpacing: 8) {
                promise("End to end encrypted")
                promise("Nothing opened on your router")
                promise("Invite only")
            }
        }
        .padding(sizes.gap * 1.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
                .fill(LinearGradient(colors: [palette.accent.opacity(0.14), palette.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(palette.accent.opacity(0.35), lineWidth: 1))
        .padding(.top, sizes.gap2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connect.anywhere")
    }
}
