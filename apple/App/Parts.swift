import ImageIO
import SwiftUI
import WittyKit

// The pieces every screen shares. Colour never carries a meaning by itself: a problem has an icon
// and the word in its label, something selected changes shape, and progress is also said aloud.

/// Says something to whoever is using a screen reader, without moving where they are.
@MainActor
func announce(_ words: String) {
    guard !words.isEmpty else { return }
    #if os(macOS)
    if let window = NSApplication.shared.mainWindow {
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [.announcement: words, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
    #else
    UIAccessibility.post(notification: .announcement, argument: words)
    #endif
}

/// One line saying what went wrong.
struct ProblemLine: View {
    @Environment(\.palette) private var palette
    let words: String

    init(_ words: String) { self.words = words }

    var body: some View {
        Label {
            Text(words).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(palette.danger)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Problem: \(words)")
        .onAppear { announce("Problem: \(words)") }
    }
}

/// A whole screen that couldn't load, with a way forward. Never a dead end: on a TV these buttons
/// are also what the remote's focus lands on.
struct ProblemView: View {
    let words: String
    var retry: (() -> Void)?
    var back: (() -> Void)?

    var body: some View {
        VStack(spacing: Tokens.Space.s4) {
            ProblemLine(words).frame(maxWidth: 640)
            if let retry { Button("Try again", action: retry) }
            if let back { Button(say("back"), action: back) }
        }
        .padding(Tokens.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// While something loads.
struct LoadingView: View {
    var body: some View {
        ProgressView()
            .accessibilityLabel("Loading")
            .frame(maxWidth: .infinity, minHeight: 200)
    }
}

/// When there's honestly nothing to show, saying why and what to do.
struct EmptyMessage: View {
    @Environment(\.palette) private var palette
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Tokens.Space.s2) {
            Text(title).font(.wmSection).accessibilityAddTraits(.isHeader)
            Text(detail).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
        }
        .padding(Tokens.gutter)
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

/// A chip that selects something. Selected is shown by being filled in, in every theme.
struct ChipLabel: View {
    @Environment(\.palette) private var palette
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .lineLimit(1)
            .foregroundStyle(selected ? palette.background : palette.textSecondary)
            .padding(.horizontal, Tokens.Space.s4)
            .frame(minHeight: Tokens.minTarget)
            .background(Capsule().fill(selected ? palette.text : Color.clear))
            .contentShape(Capsule())
    }
}

#if !os(tvOS)
/// The one main action on a screen. Apple TV has its own: a system button lifts when focused.
struct PillButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, Tokens.Space.s6)
            .frame(minHeight: Tokens.minTarget)
            .background(Capsule().fill(palette.accent))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
    }
}
#endif

/// Pictures are decoded at the size shown, and only so many bytes of them stay in memory: a poster
/// held as pixels is many times the size of the file, and an Apple TV HD has 2 GB for everything.
final class ArtCache {
    static let shared: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
}

func decodeArt(_ data: Data, maxPixels: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        kCGImageSourceShouldCacheImmediately: true, // decoded here, off the main thread, not while scrolling
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

/// A picture from the server. Nothing with a picture missing is an error: the server answers 404
/// for those, and they get a plain card.
struct ArtImage: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    /// The width it's shown at, in points.
    let width: CGFloat
    /// All of it, with bars if it has to: a photo, rather than a poster that fills its card.
    var fit = false
    @State private var image: CGImage?

    var body: some View {
        Rectangle()
            .fill(palette.card)
            .overlay {
                if let image {
                    if fit {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                    } else {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    }
                } else {
                    Image(systemName: "film").font(.title).foregroundStyle(palette.textHint)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        let pixels = Int(width * displayScale)
        let key = "\(url.absoluteString)#\(pixels)" as NSString
        if let cached = ArtCache.shared.object(forKey: key) {
            image = cached
            return
        }
        guard let data = try? await client.imageData(url) else { return }
        let decoded = await Task.detached(priority: .utility) { decodeArt(data, maxPixels: pixels) }.value
        guard let decoded, !Task.isCancelled else { return }
        ArtCache.shared.setObject(decoded, forKey: key, cost: decoded.bytesPerRow * decoded.height)
        image = decoded
    }
}

extension View {
    /// The Back button on the Apple TV remote. Without an action it does what the system does:
    /// goes up, and leaves the app only from the top. Used wherever that would quit a flow.
    @ViewBuilder func onRemoteBack(_ action: (() -> Void)?) -> some View {
        #if os(tvOS)
        self.onExitCommand(perform: action)
        #else
        self
        #endif
    }

    /// Keeps focus able to move into and out of a group, wherever its buttons line up.
    @ViewBuilder func remoteSection() -> some View {
        #if os(tvOS)
        self.focusSection()
        #else
        self
        #endif
    }

    /// Cards on Apple TV lift when focused, which is how focus is shown there.
    @ViewBuilder func tileStyle() -> some View {
        #if os(tvOS)
        self.buttonStyle(.card)
        #else
        self.buttonStyle(.plain)
        #endif
    }

    /// The main action on a screen.
    @ViewBuilder func mainAction() -> some View {
        #if os(tvOS)
        self
        #else
        self.buttonStyle(PillButtonStyle())
        #endif
    }

    /// Where focus goes first on Apple TV, within a scope marked by `focusRoot`.
    @ViewBuilder func firstFocus(in scope: Namespace.ID, when wanted: Bool = true) -> some View {
        #if os(tvOS)
        self.prefersDefaultFocus(wanted, in: scope)
        #else
        self
        #endif
    }

    @ViewBuilder func focusRoot(_ scope: Namespace.ID) -> some View {
        #if os(tvOS)
        self.focusScope(scope)
        #else
        self
        #endif
    }

    /// A text box that doesn't try to correct a server address or a name. On Apple TV the system's
    /// own keyboard opens when it's chosen, and a phone can type into that too.
    @ViewBuilder func plainEntry() -> some View {
        #if os(macOS)
        self.autocorrectionDisabled().textFieldStyle(.roundedBorder)
        #elseif os(tvOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
        #endif
    }

    /// A password box drawn like the text boxes beside it. Apple TV draws its own.
    @ViewBuilder func boxedField() -> some View {
        #if os(tvOS)
        self
        #else
        self.textFieldStyle(.roundedBorder)
        #endif
    }

    /// Scrolling content on the theme's background, running under the TV's edge so that lifted cards
    /// don't clip: what's inside keeps to the margins in `Tokens` by itself.
    @ViewBuilder func pageBackground(_ palette: Palette) -> some View {
        #if os(tvOS)
        self.background(palette.background.ignoresSafeArea()).ignoresSafeArea(.container, edges: .horizontal)
        #else
        self.background(palette.background.ignoresSafeArea())
        #endif
    }

    /// Lets a physical keyboard type the digits too. Apple TV has no keyboard shortcuts.
    @ViewBuilder func digitShortcut(_ digit: Character) -> some View {
        #if os(tvOS)
        self
        #else
        self.keyboardShortcut(KeyEquivalent(digit), modifiers: [])
        #endif
    }
}
