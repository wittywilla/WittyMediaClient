import SwiftUI
import WittyKit

@main
struct WittyMediaApp: App {
    @StateObject private var model = AppModel()

    init() {
        ClientLog.shared.start(app: "WittyMedia Apple", version: WittyClient.appVersion)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG && os(iOS)
            // For checking the touch controls with no game: `-WittyPlayTouchPreview snes` at launch.
            if let console = UserDefaults.standard.string(forKey: "WittyPlayTouchPreview") {
                TouchPreviewScreen(console: console)
            } else {
                rootView
            }
            #else
            rootView
            #endif
        }
    }

    private var rootView: some View {
        Group {
            RootView()
                .environmentObject(model)
                .environmentObject(model.listening)
                .modifier(MetricsForWidth())
                .preferredColorScheme(model.scheme)
                .tint(model.palette.accentText)
                .task { await model.start() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    /// The device's own, while the automatic theme leaves it be; otherwise the theme's.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            model.palette.background.ignoresSafeArea()
            switch model.stage {
            case .starting:
                LoadingView()
            case .connect(let message):
                ConnectView(initialMessage: message)
            case .code(let server, let fromSignIn):
                CodeView(server: server, fromSignIn: fromSignIn)
            case .mismatch(let server):
                MismatchView(server: server)
            case .signIn(let way):
                SignInView(way: way).id(way)
            case .browsing:
                BrowseShell()
            }
        }
        // From here, which redraws with the model, and not from the scene above it, which can draw a
        // moment later: a screen that has just appeared must never ask with the connection before.
        .environment(\.palette, model.palette)
        .environment(\.client, model.client)
        .animation(.easeInOut(duration: 0.2), value: model.effectiveThemeId)
        .onAppear { model.systemScheme = colorScheme }
        .onChange(of: colorScheme) { scheme in
            if model.themeChoice == "auto" || model.scheme == nil { model.systemScheme = scheme }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.recheck() } }
        }
        #if os(tvOS)
        // Only Apple TV has anything that opens this, the Top Shelf, so only it registers the scheme.
        .onOpenURL { model.open(link: $0) }
        #endif
    }
}
