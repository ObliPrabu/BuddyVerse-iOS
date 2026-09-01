import SwiftUI
import WebKit

/// A WKWebView wrapper shared by MainWebView ("Try the Website") and
/// PaymentWebView (Stripe checkout). Mirrors both Android WebView setups:
/// navigation is restricted to a set of trusted hosts (everything else opens
/// in the system browser instead, matching MainActivity's
/// shouldOverrideUrlLoading fix), and the user-agent has the embedded-WebView
/// marker stripped so sites that serve a stripped-down page to "wv" browsers
/// render normally, without lying about the real engine version.
struct TrustedWebView: UIViewRepresentable {
    let url: URL
    /// Hosts allowed to load/navigate inside this WebView. Anything else
    /// (payment-method popups, Terms/Privacy links, etc.) opens externally.
    let allowedHosts: (String) -> Bool
    var onNavigate: ((URL) -> Bool)? = nil // return true to intercept and stop default handling
    var onLoadError: (() -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = strippedUserAgent(from: webView.value(forKey: "userAgent") as? String)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func strippedUserAgent(from base: String?) -> String? {
        // Default UA already looks like a real mobile Safari string; nothing
        // to strip on iOS (the "; wv)" marker is an Android WebView quirk),
        // kept here so both platforms' WebView wrappers read the same way.
        base
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: TrustedWebView
        // Guards against onNavigate firing more than once - decidePolicyFor,
        // didReceiveServerRedirect, and didFinish can all observe the same
        // successful landing on the target host.
        private var didIntercept = false
        init(_ parent: TrustedWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let host = url.host else {
                decisionHandler(.allow)
                return
            }
            if tryIntercept(url) {
                decisionHandler(.cancel)
                return
            }
            if parent.allowedHosts(host) {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        // Stripe's "after payment" redirect often arrives as a server-side
        // HTTP redirect chained off the checkout-completion request rather
        // than a fresh link click. WKWebView does NOT re-invoke
        // decidePolicyFor for that kind of same-navigation redirect hop -
        // unlike Android's WebViewClient.shouldOverrideUrlLoading, which
        // does get called again - so it can silently finish loading the
        // success page while decidePolicyFor never sees that host at all.
        // Watching the redirect notification and the final didFinish too
        // closes that gap so payment success is never missed here. Verified
        // live on a physical device: the success redirect is caught by
        // didFinish specifically (neither decidePolicyFor nor
        // didReceiveServerRedirect saw it), confirming this gap is real.
        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            if let url = webView.url { _ = tryIntercept(url) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url { _ = tryIntercept(url) }
        }

        private func tryIntercept(_ url: URL) -> Bool {
            guard !didIntercept, let onNavigate = parent.onNavigate, onNavigate(url) else { return false }
            didIntercept = true
            return true
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !Self.isIgnorableCancellation(error) else { return }
            parent.onLoadError?()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !Self.isIgnorableCancellation(error) else { return }
            parent.onLoadError?()
        }

        // decidePolicyFor's own decisionHandler(.cancel) - used above for any
        // host not in allowedHosts, e.g. a Terms/Privacy link during Stripe
        // checkout, opened in Safari instead - fires WebKit's own "cancelled"/
        // "frame load interrupted" error through these same delegate methods.
        // That's not a real load failure, just this WebView correctly
        // declining to follow the link itself, so it must not surface as
        // "Couldn't load checkout" over what's still a perfectly live page.
        private static func isIgnorableCancellation(_ error: Error) -> Bool {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
            if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return true }
            return false
        }
    }
}
