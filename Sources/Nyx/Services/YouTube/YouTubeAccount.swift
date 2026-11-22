import AppKit
import WebKit

/// An optional YouTube sign-in for the player inside Nyx, so what Premium
/// gives (no ads) applies. The login page runs in a window of its own and
/// its cookies stay in Nyx's own web storage: Nyx never reads the browser's
/// cookies and never sees the password. Without signing in, songs still play.
@MainActor
final class YouTubeAccount: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = YouTubeAccount()

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    @Published private(set) var signedIn = false
    private var window: NSWindow?
    private var web: WKWebView?

    override private init() {
        super.init()
        refresh()
    }

    func refresh() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let signed = cookies.contains { $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" }
            Task { @MainActor in self?.signedIn = signed }
        }
    }

    func openSignIn() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: WKWebViewConfiguration())
        web.customUserAgent = Self.userAgent
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Sign in to YouTube"
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.delegate = self
        window.center()
        self.web = web
        self.window = window
        let address = "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2F"
        web.load(URLRequest(url: URL(string: address)!))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        web?.loadHTMLString("", baseURL: nil)
        web = nil
        // Give the page a moment to store its cookies.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
    }

    func signOut() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let ours = records.filter { $0.displayName.contains("youtube") || $0.displayName.contains("google") }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: ours) {
                Task { @MainActor in
                    YouTubeAccount.shared.refresh()
                }
            }
        }
    }
}
