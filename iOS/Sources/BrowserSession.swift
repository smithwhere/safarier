import SwiftUI
import WebKit

@MainActor
final class BrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    let profile: BrowserProfile
    @Published var address = ""
    @Published var title = "新页面"
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var errorMessage: String?
    private var observations: [NSKeyValueObservation] = []

    init(profile: BrowserProfile) throws {
        self.profile = profile
        let configuration = WKWebViewConfiguration()
        let store = profile.temporary ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore(forIdentifier: profile.id)
        // 完成代理校验后才能创建网页视图，错误时绝不回退直连。
        if let proxy = profile.proxy {
            store.proxyConfigurations = [try proxy.configuration()]
        } else {
            store.proxyConfigurations = []
        }
        configuration.websiteDataStore = store
        // 保留系统 UA、系统隐私默认值；不调用私有 SPI，不伪造设备特征。
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refreshState() }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refreshState() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refreshState() }
            }
        ]
    }

    func navigate() {
        guard let url = BrowserAddress.resolve(address) else {
            errorMessage = BrowserError.invalidAddress.localizedDescription
            return
        }
        errorMessage = nil
        webView.load(URLRequest(url: url))
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        observations.removeAll()
    }

    private func refreshState() {
        progress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        address = webView.url?.absoluteString ?? address
        title = webView.title ?? "网页"
        refreshState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadError(error)
    }

    private func showLoadError(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = profile.proxy == nil ? "网页加载失败，请检查网络或网址。" : "网页或代理连接失败，未切换为直连。"
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        errorMessage = "网页进程已结束，请点击刷新重新加载。"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, BrowserAddress.permits(url) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // 新窗口链接仍留在当前环境，避免跳到系统浏览器而丢失隔离与代理。
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url, BrowserAddress.permits(url) {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

struct BrowserSurface: UIViewRepresentable {
    let session: BrowserSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
