import SafariServices
import SwiftUI

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// A web page shown in the in-app browser, for `.sheet(item:)`.
struct WebPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

extension View {
    /// Opens web links inside LocSim instead of switching to Safari.
    func webPageSheet(_ page: Binding<WebPage?>) -> some View {
        sheet(item: page) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
    }
}
