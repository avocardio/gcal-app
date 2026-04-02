import SwiftUI
import WebKit

struct CalendarWebView: NSViewRepresentable {
    static let calendarURL = URL(string: "https://calendar.google.com")!
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    // JS to count event elements visible on the page
    static let countEventsJS = """
    (function() {
        var selectors = ['[data-eventid]', '[data-eventchip]', '[data-eventchip-id]'];
        for (var i = 0; i < selectors.length; i++) {
            var els = document.querySelectorAll(selectors[i]);
            if (els.length > 0) return els.length;
        }
        return -1;
    })()
    """

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")

        #if DEBUG
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        #endif

        context.coordinator.bind(webView)
        webView.load(URLRequest(url: Self.calendarURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private weak var webView: WKWebView?
        private var observers: [Any] = []
        private var countTimer: Timer?

        func bind(_ webView: WKWebView) {
            self.webView = webView
            let nc = NotificationCenter.default
            observers = [
                nc.addObserver(forName: .reload, object: nil, queue: .main) { [weak webView] _ in
                    webView?.reload()
                },
                nc.addObserver(forName: .goBack, object: nil, queue: .main) { [weak webView] _ in
                    webView?.goBack()
                },
                nc.addObserver(forName: .goForward, object: nil, queue: .main) { [weak webView] _ in
                    webView?.goForward()
                },
                nc.addObserver(forName: .goHome, object: nil, queue: .main) { [weak webView] _ in
                    webView?.load(URLRequest(url: CalendarWebView.calendarURL))
                },
            ]
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            countTimer?.invalidate()
        }

        private func refreshEventCount() {
            webView?.evaluateJavaScript(CalendarWebView.countEventsJS) { result, _ in
                if let count = result as? Int, count >= 0 {
                    DispatchQueue.main.async { EventCount.shared.count = count }
                }
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Count events after page loads, with a short delay for JS rendering
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.refreshEventCount()
            }
            // Start periodic refresh
            countTimer?.invalidate()
            countTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.refreshEventCount()
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
            let host = url.host ?? ""

            let isGoogle = host.hasSuffix("google.com") || host.hasSuffix("googleapis.com") ||
                           host.hasSuffix("gstatic.com") || host.hasSuffix("googleusercontent.com")

            if !isGoogle && navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        // MARK: WKUIDelegate — popups

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                      for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: WKUIDelegate — file picker

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                      initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.begin { r in completionHandler(r == .OK ? panel.urls : nil) }
        }

        // MARK: WKUIDelegate — JS dialogs

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                      initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                      initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                      defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                      completionHandler: @escaping (String?) -> Void) {
            let alert = NSAlert()
            alert.messageText = prompt
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            input.stringValue = defaultText ?? ""
            alert.accessoryView = input
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }
}
