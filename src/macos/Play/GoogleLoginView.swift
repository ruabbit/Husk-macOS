// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import WebKit

struct GoogleLoginView: View {
    @ObservedObject var store: MacPlayStore
    @ObservedObject var browser: GoogleBrowserLogin
    @Environment(\.dismiss) private var dismiss
    @State private var embedded = GoogleBrowserLogin.browser == nil
    @State private var attempt = UUID()
    @State private var loading = true
    @State private var webError: String?
    @State private var rejected = false
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("登录 Google Play").font(.title2.weight(.semibold))
                Spacer()
                Button("取消") { store.cancelLogin(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            if rejected {
                Spacer()
                Image(systemName: "exclamationmark.circle").font(.largeTitle).foregroundStyle(.orange)
                Text("Google 未接受本次登录").font(.headline)
                Text("当前个人账号登录方式无法继续。你可以关闭此窗口，使用访客账号浏览和下载免费应用。")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            } else if embedded {
                GoogleLoginWebView(loading: $loading, error: $webError, rejected: $rejected) { token in
                    store.connect(token: token)
                }.id(attempt).disabled(store.busy)
                if store.busy { ProgressView("正在建立 Play 会话…") }
                else if loading { ProgressView("正在加载 Google 登录…") }
                if GoogleBrowserLogin.browser != nil {
                    Button("使用 Chrome 登录") {
                        embedded = false; webError = nil; store.error = nil; openBrowser()
                    }.disabled(store.busy || browser.active)
                } else {
                    Text("内置登录不支持 Google passkey。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Spacer()
                if browser.active { ProgressView("请在 Chrome 中完成 Google 登录") }
                else if store.busy { ProgressView("正在建立 Play 会话…") }
                Text("请按 Google 页面提示完成验证。取得登录结果后，Husk 会尝试连接 Play。")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
                Button("改用内置登录") {
                    browser.cancel(); embedded = true; webError = nil; store.error = nil
                }.disabled(store.busy)
            }
            if let message = webError ?? store.error {
                Text(message).foregroundStyle(.red).textSelection(.enabled)
                if !rejected {
                    Button("重新打开登录页") {
                        store.cancelLogin(); store.error = nil; webError = nil; loading = true
                        if embedded { attempt = UUID() } else { openBrowser() }
                    }.disabled(browser.active || store.busy)
                }
            }
        }.padding(20).frame(width: embedded && !rejected ? 620 : 520, height: embedded && !rejected ? 720 : 300)
        .onAppear { if !embedded { openBrowser() } }
        .onDisappear { store.cancelLogin() }
        .onChange(of: store.session != nil) { _, signedIn in if signedIn { dismiss() } }
    }
    private func openBrowser() {
        browser.start { result in
            switch result {
            case .success(let token):
                NSApp.activate(ignoringOtherApps: true)
                store.connect(token: token)
            case .failure(let error):
                rejected = error is GoogleLoginFailure
                store.error = error.localizedDescription
            }
        }
    }
}

struct GoogleLoginWebView: NSViewRepresentable {
    @Binding var loading: Bool
    @Binding var error: String?
    @Binding var rejected: Bool
    let captured: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.view = view
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        view.load(URLRequest(url: GoogleLoginPolicy.url))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.closed = true
        view.stopLoading(); view.navigationDelegate = nil; view.uiDelegate = nil
        view.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        var parent: GoogleLoginWebView
        weak var view: WKWebView?
        var done = false
        var closed = false
        init(_ parent: GoogleLoginWebView) { self.parent = parent }
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !closed, !done else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.closed, !self.done,
                      let token = GoogleLoginPolicy.token(in: cookies.map {
                          .init(name: $0.name, value: $0.value, domain: $0.domain, secure: $0.isSecure)
                      }) else { return }
                self.done = true; self.parent.captured(token)
            }
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { parent.loading = true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false; cookiesDidChange(in: webView.configuration.websiteDataStore.httpCookieStore)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        private func failed(_ error: Error) {
            guard !closed, (error as NSError).code != NSURLErrorCancelled else { return }
            parent.loading = false; parent.error = "无法加载 Google 登录页面：\(error.localizedDescription)"
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, GoogleLoginPolicy.allows(url) else { decisionHandler(.cancel); return }
            if navigationAction.targetFrame?.isMainFrame == true, GoogleLoginPolicy.isRejection(url) {
                done = true
                parent.loading = false; parent.rejected = true
                parent.error = GoogleLoginFailure.browserRejected.localizedDescription
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url, GoogleLoginPolicy.allows(url) {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
