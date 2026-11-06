import Foundation
import WebKit

/// Loads a page in an off-screen WKWebView, lets its JavaScript run, and
/// returns the rendered HTML. This handles single-page-app trackers and
/// "checking your browser" interstitials that plain URLSession can't.
@MainActor
final class WebPageRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private let settleDelay: TimeInterval
    private let deadline: Date
    private var captureScheduled = false

    private init(timeout: TimeInterval, settle: TimeInterval) {
        self.settleDelay = settle
        self.deadline = Date().addingTimeInterval(timeout)
    }

    static func render(_ url: URL, timeout: TimeInterval = 35, settle: TimeInterval = 3) async throws -> String {
        let renderer = WebPageRenderer(timeout: timeout, settle: settle)
        return try await renderer.load(url, timeout: timeout)
    }

    private func load(_ url: URL, timeout: TimeInterval) async throws -> String {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // keeps challenge cookies between runs
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.customUserAgent = SourceFetcher.userAgent
        webView.navigationDelegate = self
        self.webView = webView

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: timeout))
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(.failure(FetchError.timeout))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scheduleCapture()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func scheduleCapture() {
        guard !captureScheduled else { return }
        captureScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.settleDelay ?? 3) * 1_000_000_000))
            self?.capture()
        }
    }

    private func capture() {
        captureScheduled = false
        guard let webView, continuation != nil else { return }
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            guard let self else { return }
            if let error { self.finish(.failure(error)); return }
            let html = result as? String ?? ""
            let lower = html.lowercased()
            let isChallenge = lower.contains("challenge-platform") || lower.contains("just a moment")
                || lower.contains("checking your browser")
            if isChallenge && Date() < self.deadline {
                self.scheduleCapture() // wait for the challenge to redirect
            } else {
                self.finish(.success(html))
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }
}
