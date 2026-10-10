// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import WebKit

struct GoogleLoginView: View {
    @ObservedObject var store: MacPlayStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var started = false
    @State private var loading = true
    @State private var webError: String?
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("登录 Google Play").font(.title2.weight(.semibold))
                Spacer()
                Button("取消") { store.cancelLogin(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            if started {
                GoogleLoginWebView(email: email, loading: $loading, error: $webError) { token in
                    store.connect(email: email, token: token)
                }.disabled(store.busy)
                if store.busy { ProgressView("正在建立 Play 会话…") }
                else if loading { ProgressView("正在加载 Google 登录…") }
            } else {
                Spacer()
                TextField("Google 账号邮箱", text: $email).textFieldStyle(.roundedBorder).frame(width: 360)
                Button("继续") { started = true }.buttonStyle(.borderedProminent)
                    .disabled(!email.contains("@") || email.contains(where: \.isWhitespace))
                Spacer()
            }
            if let message = webError ?? store.error {
                Text(message).foregroundStyle(.red).textSelection(.enabled)
                Button("重新打开登录页") { store.cancelLogin(); store.error = nil; webError = nil; started = false }
            }
        }.padding(20).frame(width: 620, height: 720)
        .onChange(of: store.session != nil) { _, signedIn in if signedIn { dismiss() } }
    }
}

struct GoogleLoginWebView: NSViewRepresentable {
    let email: String
    @Binding var loading: Bool
    @Binding var error: String?
    let captured: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = PlayDevice.authUserAgent
        view.navigationDelegate = context.coordinator
        context.coordinator.view = view
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        var url = URLComponents(string: "https://accounts.google.com/EmbeddedSetup")!
        url.queryItems = [URLQueryItem(name: "Email", value: email)]
        view.load(URLRequest(url: url.url!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.closed = true
        view.stopLoading(); view.navigationDelegate = nil
        view.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var parent: GoogleLoginWebView
        weak var view: WKWebView?
        var done = false
        var closed = false
        init(_ parent: GoogleLoginWebView) { self.parent = parent }
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !closed, !done else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.closed, !self.done,
                      let token = cookies.first(where: {
                          $0.name == "oauth_token" && !$0.value.isEmpty &&
                          ["accounts.google.com", ".accounts.google.com", ".google.com", "google.com"].contains($0.domain) && $0.isSecure
                      })?.value else { return }
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
            guard let url = navigationAction.request.url, url.scheme == "https", let host = url.host,
                  host == "google.com" || host.hasSuffix(".google.com") else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
    }
}
