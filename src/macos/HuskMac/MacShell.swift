// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import AppKit
import SharedLibrary

/// macOS uses real AppKit game windows; the library remains available while a game runs.
struct MacHomeShell: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Holiday.key) private var holiday = true
    @AppStorage("macos.appearance") private var appearance = "system"
    @State private var tab = "home"
    @State private var featuredID: String?
    private var recentGames: [LibraryGame] {
        model.games.sorted { ($0.lastPlayed ?? $0.importedAt) > ($1.lastPlayed ?? $1.importedAt) }
    }
    private var featured: LibraryGame? {
        recentGames.first { $0.id == featuredID } ?? recentGames.first
    }
    var body: some View {
        TabView(selection: $tab) {
            home.tabItem { Label("首页", systemImage: "house") }.tag("home")
            LibraryView(model: model).tabItem { Label("资料库", systemImage: "square.grid.2x2") }.tag("library")
            MacPlayStoreView(model: model, store: model.playStore).tabItem { Label("商店", systemImage: "bag") }.tag("store")
            MacHelpView().tabItem { Label("帮助", systemImage: "questionmark.circle") }.tag("help")
        }
        .overlay { if holiday && Holiday.inSeason && !reduceMotion { Snowfall() } }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .frame(minWidth: 900, minHeight: 620)
        .task { await model.reload() }
        .onOpenURL { url in
            if url.isFileURL { model.importURLs([url]); tab = "library"; return }
            guard url.scheme == "husk-macos", url.host == "open_app",
                  let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value else { return }
            Task {
                await model.reload()
                guard let game = model.games.first(where: { $0.id == id }) else { return }
                model.selection = id; tab = "library"
                if !model.session.active { model.play(game) }
                else if model.session.gameID == id { window("show") }
            }
        }
        .onChange(of: model.selection) { _, _ in if model.importing { tab = "library" } }
    }
    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Husk").font(.largeTitle.bold())
                        Text("你的 Android 应用与游戏").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if holiday && Holiday.inSeason { ChristmasTree(size: 66) }
                }
                if let game = featured { featuredGame(game) }
                HStack(spacing: 16) {
                    tile("资料库", "\(model.games.count) 个应用", "square.grid.2x2") { tab = "library" }
                    tile("Google Play", "浏览与下载应用", "bag") { tab = "store" }
                    tile("导入应用", "APK、APKS、XAPK", "square.and.arrow.down") { tab = "library"; model.showImporter = true }
                    tile("使用帮助", "操作、存档和常见问题", "questionmark.circle") { tab = "help" }
                }
                if model.session.active {
                    GroupBox("当前窗口") {
                        HStack {
                            Text(model.games.first { $0.id == model.session.gameID }?.title ?? "应用")
                            Spacer()
                            Button("显示") { window("show") }
                            Button("最小化") { window("minimize") }
                            Button("缩放") { window("zoom") }
                            Button("全屏") { window("fullscreen") }
                            Button(model.session.state == "paused" ? "继续" : "暂停") { model.session.togglePause() }
                                .disabled(!["running", "paused"].contains(model.session.state))
                            Button("结束") { model.session.stop() }
                        }.padding(10)
                    }
                }
                Text("最近使用").font(.title2.bold())
                if model.games.isEmpty {
                    ContentUnavailableView("添加你的第一个应用", systemImage: "square.and.arrow.down", description: Text("导入 APK 或从 Google Play 下载，应用将保存在资料库。"))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 18)], spacing: 18) {
                        ForEach(recentGames.prefix(12)) { game in
                            Button { featuredID = game.id } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    GameIcon(url: model.paths.game(game.id).appendingPathComponent("icon.data"), size: 58).snowCap(height: 5)
                                    Text(game.title).font(.headline).lineLimit(2)
                                    Text(game.lastPlayed?.formatted(date: .abbreviated, time: .omitted) ?? "新导入")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, minHeight: 140, alignment: .leading).padding(16)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(featured?.id == game.id ? Color.accentColor : .clear, lineWidth: 2) }
                            }.buttonStyle(.plain)
                                .accessibilityLabel("选择 \(game.title)")
                                .accessibilityAddTraits(featured?.id == game.id ? .isSelected : [])
                        }
                    }
                }
            }.padding(30)
        }.navigationTitle("Husk")
    }
    private func featuredGame(_ game: LibraryGame) -> some View {
        HStack(spacing: 24) {
            GameIcon(url: model.paths.game(game.id).appendingPathComponent("icon.data"), size: 116).snowCap(height: 7)
            VStack(alignment: .leading, spacing: 12) {
                Text(game.title).font(.largeTitle.bold()).lineLimit(2)
                if let date = game.lastPlayed {
                    Text("上次使用 \(date.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                }
                HStack {
                    if model.session.active && model.session.gameID == game.id {
                        Button("显示窗口") { window("show") }.buttonStyle(.borderedProminent)
                    } else {
                        Button("启动") { model.play(game) }.buttonStyle(.borderedProminent)
                            .disabled(!game.playable || model.session.active || model.importing)
                    }
                    Button("查看详情") { model.selection = game.id; tab = "library" }
                }.controlSize(.large)
                if let reason = game.unavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }.padding(26).frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
            .background(LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
    }
    private func window(_ action: String) { model.session.send("window", values: ["action": action]) }
    private func tile(_ title: String, _ subtitle: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title2).foregroundStyle(.mint)
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16)).snowCap()
        }.buttonStyle(.plain)
    }
}

struct MacHelpView: View {
    @State private var query = ""
    private let answers: [(String, String)] = [
        ("如何安装应用？", "将 APK、APKS、XAPK 或 APKM 拖入资料库，或使用 Google Play 商店。导入会复制文件；原文件保持原位。带分包的应用需要完整 bundle。"),
        ("如何管理运行窗口？", "应用运行在独立的 macOS 窗口中，可拖动、调整大小、最小化与全屏。首页的当前窗口和“游戏”菜单可以找回最小化的窗口。游戏详情可设置下次启动时全屏。调整窗口会缩放游戏画布，保持触摸位置一致。"),
        ("如何使用鼠标、键盘和手柄？", "鼠标点击、拖动对应触摸；键盘与手柄支持取决于应用。可连接最多四个扩展手柄，断开或失去焦点会释放按键。⌘P 暂停或继续，⌘Q 正常结束游戏。应用需要文字时可使用系统输入法。"),
        ("切换窗口会暂停吗？", "默认继续运行。可在每个应用的详情里开启失焦暂停。暂停会释放正在按住的输入；恢复后可继续操作。"),
        ("应用黑屏或无法启动怎么办？", "确认使用 arm64 或纯 Java 应用，以及完整分包和游戏数据。社区列表中的 iPhone 结果仅供参考。失败日志保存在资料目录的 Logs 中；帮助排查时提供应用版本与日志。重新导入前无需删除存档。"),
        ("存档在哪里？", "资料目录中的 Saves 按应用隔离。结束游戏会等待运行组件完成关闭；若提示关闭失败，已有文件仍保留。移除应用保留存档；只有单独确认“清除存档”才会删除存档。"),
        ("Google Play 登录失败怎么办？", "登录使用浏览器完成。Google 可能拒绝此登录方式；浏览器显示成功也需要返回后建立可用的 Play 会话。目前个人账号和 passkey 的实测拒绝问题仍在处理中。也可以从你信任的来源导入 APK。"),
        ("原生运行与 Android 有什么区别？", "原生运行使用 Husk 的 Android API 与图形实现，启动快但应用兼容性有差异。Android 是独立虚拟机，使用单独的数据盘和系统要求。虚拟机安装成功不代表应用已通过运行验证。"),
        ("macOS 需要 iPhone 的 JIT 配对吗？", "不需要。macOS 运行组件使用随应用签名的执行内存权限。若提示缺少权限，请重新构建或安装完整应用。"),
        ("如何关闭圣诞装饰？", "装饰仅在 12 月 1 日至 1 月 6 日显示。打开 Husk 设置可以关闭“圣诞装饰”。系统开启减少动态效果时，飘雪动画自动关闭。")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Husk 帮助").font(.largeTitle.bold()).padding(.horizontal, 20)
            TextField("搜索问题", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 20)
            List {
                ForEach(answers.filter { query.isEmpty || $0.0.localizedCaseInsensitiveContains(query) || $0.1.localizedCaseInsensitiveContains(query) }, id: \.0) { answer in
                    DisclosureGroup(answer.0) { Text(answer.1).foregroundStyle(.secondary).textSelection(.enabled).padding(.vertical, 8) }
                }
                Link("上游社区兼容性列表", destination: CompatibilityStore.site)
            }
        }.padding(.top, 20)
    }
}
