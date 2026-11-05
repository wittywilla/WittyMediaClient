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

/// What went wrong, as on Android: a mark in the danger colour, and the words in the page's own
/// colour so they can be read in every theme.
struct ProblemLine: View {
    @Environment(\.palette) private var palette
    let words: String

    init(_ words: String) { self.words = words }

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s2) {
            Text("!")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.background)
                .frame(width: Tokens.Space.s5, height: Tokens.Space.s5)
                .background(Circle().fill(palette.danger))
            Text(words)
                .font(.subheadline)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            ProblemLine(words)
            if let retry { Button("Try again", action: retry).action(primary: true) }
            if let back { Button(say("back"), action: back).action() }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(Tokens.Space.s8)
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
            Text(title).font(.wmSection).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
            Text(detail).font(.wmSecondary).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
        }
        .padding(Tokens.Space.s8)
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
    /// The words that stand in for a missing picture, as on Android: usually the title.
    var placeholder = ""
    /// Nothing at all while there's no picture: a backdrop behind a page.
    var blank = false
    @State private var image: CGImage?

    var body: some View {
        Rectangle()
            .fill(blank ? Color.clear : palette.card)
            .overlay {
                if let image {
                    if fit {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                    } else {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    }
                } else if blank {
                    EmptyView()
                } else if !placeholder.isEmpty {
                    Text(placeholder)
                        .font(.wmCardSub)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(Tokens.Space.s2)
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

    /// The main action on a screen: Android's accent pill, on every device.
    func mainAction() -> some View {
        action(primary: true, pill: true)
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
