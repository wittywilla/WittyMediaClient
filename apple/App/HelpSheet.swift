import CoreImage
import SwiftUI
import WittyKit
#if os(iOS) || os(visionOS)
import SafariServices
#endif

/// One of the server's public pages, such as its help on a forgotten password, for someone who may not
/// be signed in. Safari's own view on iPhone, iPad and Vision Pro; on Apple TV, which has no browser, a
/// code to open it on a phone, with its address under it. Android TV shows the same card.
struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        #if os(iOS) || os(visionOS)
        SafariPage(url: url).ignoresSafeArea()
        #else
        OpenOnPhone(url: url, onClose: { dismiss() })
        #endif
    }
}

#if os(iOS) || os(visionOS)
private struct SafariPage: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        #if os(iOS)
        controller.dismissButtonStyle = .close // Vision Pro has its own way to close a window
        #endif
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif

/// A page a TV can't show: its code for a phone's camera, and its address to type.
struct OpenOnPhone: View {
    @Environment(\.palette) private var palette
    let url: URL
    var onClose: (() -> Void)?

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            SignInGlow()
            VStack(spacing: Tokens.Space.s6) {
                SignInHeading(title: say("openOnPhone"))
                if let image = QRImage.make(for: url.absoluteString) {
                    QRCard(image: image, caption: say("pairScan"))
                }
                Text(url.absoluteString).font(.wmLabel).foregroundStyle(palette.accentText).multilineTextAlignment(.center)
                if let onClose {
                    Button(say("back"), action: onClose).action(.primary, tall: true)
                }
            }
            .padding(Tokens.gutter)
        }
    }
}

/// The picture of an address that a phone's camera can read. No network is involved in making it.
enum QRImage {
    static func make(for text: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: nil).createCGImage(output, from: output.extent)
    }
}
