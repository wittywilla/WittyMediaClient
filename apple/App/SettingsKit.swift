import SwiftUI
import WittyKit
#if canImport(UIKit)
import UIKit
#endif

// The parts You and its screens are made of: docs/APP-DESIGN.md, Grouped list and You and settings.

/// Room at the end of a scrolling page for the floating bar to sit over without hiding anything:
/// the bar, its margin and a little air. A TV's bar is along the top.
func barRoom(_ metrics: Metrics) -> CGFloat { metrics.tv ? Tokens.Space.s10 : 104 }

/// A caption over a `panel` card of rows. Rows draw their own hairline under them; the card hides the
/// last one, so any row can be left out without a stray line.
struct ListGroup<Content: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    var footer = ""
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.leading, Tokens.Space.s4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .background(shape.fill(palette.panel))
                .overlay(alignment: .bottom) {
                    palette.panel.frame(height: 2).allowsHitTesting(false).accessibilityHidden(true)
                }
                .clipShape(shape)
                .remoteSection()
            if !footer.isEmpty {
                Text(footer)
                    .font(.wmSecondary)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Tokens.Space.s4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A rounded square holding a symbol, in a quiet tint of its colour: strong enough to find a row by,
/// never louder than the pictures elsewhere.
struct IconTile: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.metrics) private var metrics
    let symbol: String
    let hex: String

    var body: some View {
        let size: CGFloat = metrics.tv ? 32 : 28
        let base = Color(hex: hex)
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(scheme == .light ? base : Self.lifted(hex))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(base.opacity(scheme == .light ? 0.14 : 0.24)))
            .accessibilityHidden(true)
    }

    /// The colour mixed 40% towards white, so a dark hue still reads on a dark page.
    static func lifted(_ hex: String) -> Color {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return Color(hex: hex) }
        func mix(_ shift: UInt32) -> Double {
            let c = Double((value >> shift) & 0xff) / 255
            return c + (1 - c) * 0.4
        }
        return Color(red: mix(16), green: mix(8), blue: mix(0))
    }
}

/// One row: its icon, its name (and a second line), what it's set to, and a chevron when it opens something.
struct RowLabel: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    let icon: String
    let tint: String
    let title: String
    var value = ""
    var detail = ""
    var chevron = true
    var destructive = false

    var body: some View {
        let tile: CGFloat = metrics.tv ? 32 : 28
        HStack(spacing: Tokens.Space.s3) {
            IconTile(symbol: icon, hex: destructive ? "#ff5c6c" : tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(metrics.tv ? .body : .subheadline)
                    .foregroundStyle(destructive ? palette.danger : palette.text)
                if !detail.isEmpty {
                    Text(detail).font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: Tokens.Space.s2)
            if !value.isEmpty {
                Text(value).font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.textHint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Tokens.Space.s4)
        .frame(minHeight: metrics.tv ? 72 : (detail.isEmpty ? 52 : 64))
        .overlay(alignment: .bottom) {
            // Lined up with the words, as the system's lists are.
            Rectangle()
                .fill(palette.border)
                .frame(height: 1 / max(displayScale, 1))
                .padding(.leading, Tokens.Space.s4 + tile + Tokens.Space.s3)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Pressed, a row darkens to `card`; with a remote's focus it fills and gains the ring.
struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct RowBody<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    let label: Label
    let pressed: Bool

    var body: some View {
        let lit = pressed || (metrics.tv && focused)
        label
            .background(lit ? palette.card : Color.clear)
            .overlay {
                if metrics.tv && focused {
                    RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
                        .strokeBorder(palette.text, lineWidth: metrics.focusRing)
                }
            }
            .opacity(enabled ? 1 : 0.55)
            .animation(.easeOut(duration: Tokens.Motion.press), value: lit)
    }
}

extension View {
    func rowStyle() -> some View { buttonStyle(RowStyle()) }
}

/// A screen of You's: its title, a line about it, and what it's for, in one column.
struct SettingsScreen<Content: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let title: String
    var detail = ""
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Heading(title)
                if !detail.isEmpty {
                    Text(detail)
                        .font(metrics.tv ? .body : .subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .frame(maxWidth: metrics.tv ? 1100 : 640, alignment: .leading)
            .padding(.horizontal, metrics.gutter)
            .padding(.top, Tokens.Space.s2)
            .padding(.bottom, barRoom(metrics))
            .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .pageBackground(palette)
    }
}

/// A done or failed moment, said in a line with its symbol.
struct OutcomeLine: View {
    @Environment(\.palette) private var palette
    let words: String
    var good = true

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(good ? palette.ok : palette.danger)
            Text(words).font(.subheadline).foregroundStyle(palette.text)
        }
        .accessibilityElement(children: .combine)
        .onAppear { announce(words) }
    }
}

/// Six digits: the boxes, and under them the system's number keyboard on a phone (which can fill in a
/// code it was sent) or the number pad on a TV. Tapping the boxes brings the keyboard back.
struct DigitsEntry: View {
    @Binding var code: String
    var checking = false
    var wrongTries = 0
    var label = say("codeLabel")
    var scope: Namespace.ID?
    let onComplete: (String) -> Void
    @FocusState private var focused: Bool

    private func typed(_ text: String) {
        let digits = String(text.filter(\.isNumber).prefix(6))
        if digits != code { code = digits }
        if digits.count == 6 { onComplete(digits) }
    }

    var body: some View {
        VStack(spacing: Tokens.Space.s4) {
            CodeBoxes(digits: code, checking: checking, wrongTries: wrongTries)
                .frame(maxWidth: .infinity)
                #if !os(tvOS)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
                .background {
                    TextField("", text: Binding(get: { code }, set: typed))
                        #if os(iOS) || os(visionOS)
                        .keyboardType(.numberPad)
                        #endif
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .frame(width: 1, height: 1)
                        .opacity(0.02)
                        .accessibilityLabel(label)
                }
                .task { focused = true }
                #endif
            #if os(tvOS)
            NumberPad(onDigit: { digit in
                guard code.count < 6 else { return }
                typed(code + String(digit))
            }, onDelete: { if !code.isEmpty { code.removeLast() } }, scope: scope)
            #endif
        }
    }
}

/// Puts words where they can be pasted, on the devices that have a pasteboard.
enum Clipboard {
    static var available: Bool {
        #if os(iOS) || os(visionOS)
        return true
        #else
        return false
        #endif
    }

    static func copy(_ text: String) {
        #if os(iOS) || os(visionOS)
        UIPasteboard.general.string = text
        #endif
    }
}
