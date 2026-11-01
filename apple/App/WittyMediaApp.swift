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
            RootView()
                .environmentObject(model)
                .environment(\.palette, model.palette)
                .environment(\.client, model.client)
                .preferredColorScheme(model.scheme)
                .tint(model.palette.accent)
                .task { await model.start() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
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
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.recheck() } }
        }
        #if os(tvOS)
        // Only Apple TV has anything that opens this, the Top Shelf, so only it registers the scheme.
        .onOpenURL { model.open(link: $0) }
        #endif
    }
}
