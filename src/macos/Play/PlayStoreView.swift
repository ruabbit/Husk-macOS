// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import SharedLibrary

struct MacPlayStoreView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var store: MacPlayStore
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var selected: String?
    @State private var details: PlayAPI.PlayApp?
    @State private var detailError: String?
    @State private var login = false
    @State private var reporting: CompatSubject?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索应用名称或包名", text: $query).textFieldStyle(.plain).disabled(store.session == nil)
                if store.searching { ProgressView().controlSize(.small) }
                Spacer()
                if let session = store.session {
                    Text(session.isAnonymous ? "访客" : session.email).foregroundStyle(.secondary).lineLimit(1)
                    Button("退出登录") { store.signOut() }.disabled(store.hasActiveDownloads)
                }
            }.padding(16)
            Divider()
            if store.session == nil {
                VStack(spacing: 18) {
                    Image(systemName: "bag").font(.system(size: 52)).foregroundStyle(.mint)
                    Text("Google Play").font(.largeTitle.weight(.semibold))
                    Text("搜索应用，下载后自动加入 Husk 资料库。").foregroundStyle(.secondary)
                    if store.busy { ProgressView("正在连接…"); Button("取消") { store.cancelLogin() } }
                    else {
                        HStack {
                            Button("使用访客账号") { store.connect() }.buttonStyle(.borderedProminent)
                            Button("登录 Google 账号…") { store.error = nil; login = true }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(store.apps, selection: $selected) { app in
                        HStack(spacing: 12) {
                            PlayIcon(url: app.iconURL, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.title).font(.headline).lineLimit(1)
                                Text(app.developer).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }.padding(.vertical, 5).tag(app.id)
                    }.frame(minWidth: 270, idealWidth: 330)
                    ScrollView {
                        if let app = details {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack(spacing: 16) {
                                    PlayIcon(url: app.iconURL, size: 80)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(app.title).font(.title.weight(.semibold))
                                        Text(app.developer).foregroundStyle(.secondary)
                                        Text(app.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                }
                                HStack {
                                    Text(app.versionString.isEmpty ? "版本 \(app.versionCode)" : app.versionString)
                                    if app.sizeBytes > 0 { Text(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file)) }
                                    if app.rating > 0 { Label(String(format: "%.1f", app.rating), systemImage: "star.fill") }
                                }.font(.caption).foregroundStyle(.secondary)
                                downloadControls(app)
                                MacCompatibilitySection(subject: CompatSubject(package: app.id, name: app.title, isGame: false), reporting: $reporting)
                                Text(app.summary.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                ScrollView(.horizontal) {
                                    HStack { ForEach(app.screenshotURLs, id: \.self) { url in
                                        AsyncImage(url: URL(string: url)) { image in image.resizable().scaledToFit() }
                                            placeholder: { Color.clear }.frame(height: 220)
                                    } }
                                }
                            }.padding(24)
                        } else if let detailError { Text(detailError).foregroundStyle(.red).padding(24) }
                        else { Text(selected == nil ? "选择一个应用查看详情" : "正在加载详情…").foregroundStyle(.secondary).padding(40) }
                    }.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                }
                if store.apps.isEmpty && !store.searching && store.error == nil { Text("没有找到应用，可更换关键词或输入包名。").foregroundStyle(.secondary).padding() }
            }
            if let error = store.error {
                HStack {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    Spacer()
                    if store.session != nil { Button("重试") { Task { await store.load(query: query) } } }
                    Button("关闭") { store.error = nil }
                }.padding(12).background(.bar)
            }
            if store.hasActiveDownloads { downloadsBar }
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle("Google Play")
        .sheet(isPresented: $login) { GoogleLoginView(store: store, browser: store.browserLogin) }
        .sheet(item: $reporting) { MacCompatReportSheet(subject: $0) }
        .task { await store.restore() }
        .task(id: query + (store.session?.email ?? "")) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await store.load(query: query)
        }
        .task(id: selected) {
            details = nil; detailError = nil
            guard let selected else { return }
            do { let app = try await store.details(selected); if !Task.isCancelled { details = app } }
            catch { if !Task.isCancelled { detailError = error.localizedDescription } }
        }
        .onChange(of: store.session?.email) { _, _ in selected = nil; details = nil }
    }
    @ViewBuilder private func downloadControls(_ app: PlayAPI.PlayApp) -> some View {
        let installed = model.games.first(where: { $0.packageName == app.id })
        if let state = store.downloads[app.id], state.active {
            ProgressView(value: state.progress)
            HStack { Text(state.phase); if state.cancellable { Button("取消") { store.cancel(app.id) } } }
        } else {
            HStack {
                Button(installed != nil ? "检查并安装更新" : app.isFree ? "下载到资料库" : "下载已购版本") {
                    store.install(app) { files, fresh in
                        guard let repository = model.repository else { throw LibraryFailure("资料库不可用。") }
                        model.playImports += 1
                        defer { model.playImports -= 1 }
                        let game = try await repository.importAPKs(files, package: fresh.id, version: fresh.versionCode,
                                                                  title: fresh.title, blockedIDs: model.busyGameIDs)
                        await model.reload(); model.selection = game.id
                        return game
                    }
                }.buttonStyle(.borderedProminent).disabled(!app.isFree && store.session?.isAnonymous == true)
                if let game = installed {
                    Button("在资料库中打开") { model.selection = game.id; openWindow(id: "library") }
                }
            }
            if !app.isFree { Text("\(app.formattedPrice) · 需登录已购买此应用的 Google 账号").font(.caption).foregroundStyle(.secondary) }
            if let state = store.downloads[app.id] {
                Text(state.error ?? state.phase).foregroundStyle(state.error == nil ? Color.secondary : Color.red).textSelection(.enabled)
            }
        }
    }
    private var downloadsBar: some View {
        VStack(alignment: .leading) {
            ForEach(store.downloads.keys.sorted(), id: \.self) { package in
                if let state = store.downloads[package], state.active {
                    HStack {
                        Text(package).lineLimit(1)
                        ProgressView(value: state.progress).frame(width: 160)
                        Text(state.phase).foregroundStyle(.secondary)
                        if state.cancellable { Button("取消") { store.cancel(package) } }
                    }.font(.caption)
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
    }
}

private struct PlayIcon: View {
    let url: String?
    let size: CGFloat
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in image.resizable().scaledToFit() }
            placeholder: { Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(.secondary).padding(8) }
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}
