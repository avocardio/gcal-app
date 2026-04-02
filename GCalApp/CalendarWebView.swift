import SwiftUI
import WebKit

struct CalendarWebView: NSViewRepresentable {
    static let calendarURL = URL(string: "https://calendar.google.com")!
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    // JS to extract start times (minutes since midnight) of today's timed events
    static let eventTimesJS = """
    (function() {
        var now = new Date();
        var y = now.getFullYear();
        var m = String(now.getMonth() + 1).padStart(2, '0');
        var d = String(now.getDate()).padStart(2, '0');
        var todayYMD = y + m + d;
        var months = ['January','February','March','April','May','June','July',
                      'August','September','October','November','December'];
        var todayStr = months[now.getMonth()] + ' ' + now.getDate() + ', ' + now.getFullYear();
        var els = document.querySelectorAll('[data-eventid]');
        var times = [];
        for (var i = 0; i < els.length; i++) {
            var text = els[i].innerText || '';
            if (!text) continue;
            var isToday = false;
            var raw = els[i].getAttribute('data-eventid') || '';
            try {
                var p = raw; while (p.length % 4 !== 0) p += '=';
                if (atob(p).includes(todayYMD)) isToday = true;
            } catch(e) {}
            if (!isToday && text.includes(todayStr)) isToday = true;
            if (!isToday) continue;
            var h = -1, mn = 0;
            var m12 = text.match(/(\\d{1,2})(?::(\\d{2}))?\\s*(AM|PM|am|pm)/);
            if (m12) {
                h = parseInt(m12[1]);
                mn = m12[2] ? parseInt(m12[2]) : 0;
                var ap = m12[3].toUpperCase();
                if (ap === 'PM' && h !== 12) h += 12;
                if (ap === 'AM' && h === 12) h = 0;
            } else {
                var m24 = text.match(/\\b(\\d{1,2}):(\\d{2})\\b/);
                if (m24) { h = parseInt(m24[1]); mn = parseInt(m24[2]); }
            }
            if (h >= 0) times.push(h * 60 + mn);
        }
        return JSON.stringify(times);
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
            webView?.evaluateJavaScript(CalendarWebView.eventTimesJS) { result, _ in
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let times = try? JSONDecoder().decode([Int].self, from: data)
                else { return }
                DispatchQueue.main.async { EventCount.shared.update(times: times) }
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
