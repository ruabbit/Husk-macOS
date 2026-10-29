// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SharedLibrary
import Combine
import ImageIO

@MainActor final class LibraryModel: ObservableObject {
    @Published var games: [LibraryGame] = []
    @Published var selection: String?
    @Published var importing = false
    @Published var playImports = 0
    @Published var geodeBusyID: String?
    @Published var geodeStatus: [String: String] = [:]
    private var geodeTask: Task<Void, Never>?
    var importBusy: Bool { importing || playImports > 0 || geodeBusyID != nil }
    @Published var showImporter = false
    @Published var error: String?
    @Published var search = ""
    let playStore = MacPlayStore()
    let session = SessionController()
    let vm = VMController()
    var vmAvailability: VMAvailability { VMController.availability(executable: VMController.helper(in: Bundle.main.bundleURL)) }
    var vmAvailable: Bool { vmAvailability.available }
    let paths: LibraryPaths
    let repository: LibraryRepository?
    let resources: URL
    private var playingID: String?
    private var playtimeChanges: AnyCancellable?
    private var sessionChanges: AnyCancellable?
    private var vmChanges: AnyCancellable?
    private var pendingImports: [URL] = []

    init(root: URL? = nil, resources: URL? = nil) {
        paths = LibraryPaths(root: root)
        self.resources = resources ?? Bundle.main.resourceURL!
        do {
            let catalog = self.resources.appendingPathComponent("fixture-catalog.json")
            guard let data = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any],
                  let hash = data["sha256"] as? String else { throw LibraryFailure("安装不完整：缺少随附游戏清单。") }
            repository = try LibraryRepository(paths: paths, trustedFixtureHash: hash)
        } catch { repository = nil; self.error = error.localizedDescription }
        Account.shared.libraryRows = { [weak self] in MacAccountLibrary.rows(self?.games ?? []) }
        playtimeChanges = session.$state.sink { [weak self] state in
            guard let self else { return }
            let next = state == "running" ? self.session.gameID : nil
            if self.playingID != next {
                if let id = self.playingID { Playtime.end(id) }
                self.playingID = next
                if let id = next { Playtime.begin(id) }
            }
        }
        sessionChanges = session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        vmChanges = vm.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    var busyGameIDs: Set<String> {
        if vm.active { return Set(games.map(\.id)) }
        var ids = session.active ? Set([session.gameID].compactMap { $0 }) : []
        if let geodeBusyID { ids.insert(geodeBusyID) }
        return ids
    }
    func reload() async {
        do { games = try await repository?.games() ?? []; if selection == nil { selection = games.first?.id }; Account.shared.librarySoon() }
        catch { self.error = error.localizedDescription }
    }
    func importURLs(_ urls: [URL]) {
        guard geodeBusyID == nil else { error = "Geode 正在准备，请稍后导入游戏。"; return }
        guard let repository else { return }
        pendingImports.append(contentsOf: urls)
        guard !importing else { return }
        importing = true
        Task {
            defer { importing = false }
            while !pendingImports.isEmpty {
                let url = pendingImports.removeFirst()
                do { let game = try await repository.importGame(url, blockedIDs: busyGameIDs); selection = game.id }
                catch { self.error = error.localizedDescription }
                await reload()
            }
        }
    }
    func addExamples() {
        importURLs(["OrbitGarden", "OrbitGardenDusk"].map { resources.appendingPathComponent("Fixtures/\($0).apk") })
    }
    func importProviders(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                }
                if let url { urls.append(url) }
            }
            importURLs(urls)
        }
    }
    func play(_ game: LibraryGame) {
        guard !importBusy, let repository else { return }
        if game.settings.geode { prepareGeode(game, launch: true); return }
        Task {
            do { try await launch(game, repository: repository) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func launch(_ game: LibraryGame, repository: LibraryRepository) async throws {
        if session.active { session.stop(); try await session.wait(until: { !self.session.active }, timeout: 35) }
        try Task.checkCancellation()
        let (fresh, apks, checkpoint) = try await repository.prepare(game.id)
        let runner = fresh.runtime == "web" ? WebStorage.helper(in: Bundle.main.bundleURL) : Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner")
        try Task.checkCancellation()
        try session.start(executable: runner, game: fresh, apk: apks[0], checkpoint: checkpoint, logs: paths.logs)
        try await session.wait(until: { self.session.state == "running" || !self.session.active }, timeout: 95)
        if session.state == "running" { try await repository.update(game.id, played: true); await reload() }
    }
    func prepareGeode(_ game: LibraryGame, launch: Bool = false, checkForUpdates: Bool = false) {
        guard !importBusy, !vm.active, Geode.supports(game), let repository else { return }
        guard !session.active || launch else { return }
        geodeBusyID = game.id
        geodeStatus[game.id] = "正在准备 Geode…"
        geodeTask = Task {
            defer { geodeBusyID = nil; geodeTask = nil }
            do {
                let (fresh, apks, _) = try await repository.prepare(game.id)
                let importedLauncher = games.first { $0.packageName == Geode.launcherPackage }
                let launcher = importedLauncher.flatMap { item in item.apkNames.first.map { paths.game(item.id).appendingPathComponent($0) } }
                let record = try await Geode.prepare(game: fresh, apk: apks[0], launcher: launcher, checkForUpdates: checkForUpdates)
                try Task.checkCancellation()
                try await repository.update(game.id, geode: true)
                geodeStatus[game.id] = "Geode \(record.version) 已就绪"
                await reload()
                if launch { try await self.launch(game, repository: repository) }
            } catch is CancellationError { geodeStatus[game.id] = "下载已取消" }
            catch {
                if Task.isCancelled { geodeStatus[game.id] = "下载已取消" }
                else {
                    geodeStatus[game.id] = "准备失败：\(error.localizedDescription)"
                    self.error = error.localizedDescription
                }
            }
        }
    }
    func setGeode(_ game: LibraryGame, enabled: Bool) {
        if enabled { prepareGeode(game); return }
        guard !importBusy, !session.active, let repository else { return }
        geodeBusyID = game.id
        geodeTask = Task {
            defer { geodeBusyID = nil; geodeTask = nil }
            do { try await repository.update(game.id, geode: false); await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
    func cancelGeode() { geodeTask?.cancel() }
    func shortcut(_ game: LibraryGame) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "webloc")!]
        panel.nameFieldStringValue = game.title + ".webloc"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var link = URLComponents(); link.scheme = "husk-macos"; link.host = "open_app"
        link.queryItems = [URLQueryItem(name: "id", value: game.id)]
        do { try PropertyListSerialization.data(fromPropertyList: ["URL": link.url!.absoluteString], format: .xml, options: 0).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func settings(_ game: LibraryGame, muted: Bool? = nil, pause: Bool? = nil, fullScreen: Bool? = nil, jitless: Bool? = nil) {
        guard geodeBusyID != game.id, let repository else { return }
        Task {
            do {
                try await repository.update(game.id, muted: muted, pauseWhenInactive: pause, openFullScreen: fullScreen, jitless: jitless)
                if let pause, session.gameID == game.id { session.setPauseWhenInactive(pause) }
                await reload()
            } catch { self.error = error.localizedDescription }
        }
    }
    func chooseVM() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择 Android 数据目录"; panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "使用此虚拟机"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("guest.json").path) else {
            error = "此目录尚未准备好。请按构建指南准备 Android 镜像后再选择。"; return nil
        }
        UserDefaults.standard.set(url.path, forKey: "macos.vm.directory")
        return url
    }
    func startVM() {
        guard vmAvailable, !vm.active else { return }
        let directory = UserDefaults.standard.string(forKey: "macos.vm.directory").map { URL(fileURLWithPath: $0) } ?? chooseVM()
        guard let directory else { return }
        do {
            try vm.start(executable: VMController.helper(in: Bundle.main.bundleURL), guest: directory, logs: paths.logs)
        } catch { self.error = error.localizedDescription }
    }
    func playVM(_ game: LibraryGame) {
        guard !importBusy, let repository else { return }
        startVM(); guard vm.active else { return }
        Task {
            do {
                let (fresh, apks, package) = try await repository.prepareVMSet(game.id)
                try await vm.install(apks: apks, digest: fresh.digest, package: package)
                try await repository.update(game.id, played: true); await reload()
            } catch { self.error = error.localizedDescription }
        }
    }
    func remove(_ game: LibraryGame) {
        guard !importBusy, let repository, session.gameID != game.id || !session.active else { return }
        Task { do { try await repository.remove(game.id); selection = nil; await reload() } catch { self.error = error.localizedDescription } }
    }
    func deleteSave(_ game: LibraryGame) {
        guard !importBusy, let repository, session.gameID != game.id || !session.active else { return }
        Task { do { try await repository.deleteSave(game.id) } catch { self.error = error.localizedDescription } }
    }
}

struct LibraryView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: LibraryModel
    @State private var reporting: CompatSubject?
    var filtered: [LibraryGame] { model.games.filter { model.search.isEmpty || $0.title.localizedCaseInsensitiveContains(model.search) } }
    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("资料库") {
                    ForEach(filtered) { game in
                        HStack(spacing: 10) {
                            GameIcon(url: model.paths.game(game.id).appendingPathComponent("icon.data"), size: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(game.title).lineLimit(1)
                                if !game.playable { Text("尚未接入").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.padding(.vertical, 4).tag(game.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
            .searchable(text: $model.search, prompt: "搜索游戏")
            .safeAreaInset(edge: .bottom) {
                HStack { Text("\(model.games.count) 款游戏").foregroundStyle(.secondary); Spacer(); if model.importBusy { ProgressView().controlSize(.small) } }
                    .font(.caption).padding(12).background(.bar)
            }
        } detail: {
            if let game = model.games.first(where: { $0.id == model.selection }) {
                GameDetail(game: game, model: model, session: model.session)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "gamecontroller").font(.system(size: 60, weight: .light)).foregroundStyle(.mint)
                    Text("你的游戏资料库").font(.largeTitle.weight(.semibold))
                    Text("将 APK 或应用 bundle 拖到这里，\n也可以先体验随附的 Orbit Garden。").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    HStack { Button("导入游戏…") { model.showImporter = true }; Button("添加示例游戏") { model.addExamples() }.buttonStyle(.borderedProminent) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .navigationTitle("Husk")
        .toolbar {
            ToolbarItem { Button { openWindow(id: "play-store") } label: { Label("Google Play", systemImage: "bag") } }
            ToolbarItem { Button { model.showImporter = true } label: { Label("导入游戏", systemImage: "plus") }.disabled(model.importBusy) }
            if model.vmAvailability.installed {
                ToolbarItem {
                    Menu("Android（实验）") {
                        if let reason = model.vmAvailability.unavailableReason { Text(reason) }
                        else if let minimum = model.vmAvailability.minimumSystemVersion { Text("需要 macOS \(minimum) 或更新版本") }
                        Button("启动 Android") { model.startVM() }.disabled(!model.vmAvailable || model.vm.active)
                        Button("选择 Android 数据目录…") { _ = model.chooseVM() }.disabled(model.vm.active)
                        Button("暂停 / 继续") { model.vm.togglePause() }.disabled(!model.vm.ready)
                        Button("关闭 Android") { model.vm.stop() }.disabled(!model.vm.active)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.vm.active || model.vm.error != nil {
                HStack {
                    Text(model.vm.error ?? model.vm.detail).font(.caption)
                    Spacer()
                    if model.vm.active { Button("关闭 Android") { model.vm.stop() }.controlSize(.small) }
                }.padding(10).background(.bar)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            model.importProviders(providers)
            return true
        }
        .task { await model.reload() }
        .sheet(item: $reporting) { MacCompatReportSheet(subject: $0) }
        .onChange(of: model.session.state) { _, state in
            guard ["exited", "failed"].contains(state),
                  let game = model.games.first(where: { $0.id == model.session.gameID }),
                  let package = game.packageName, CompatibilityStore.shared.shouldAsk(package) else { return }
            CompatibilityStore.shared.markAsked(package)
            reporting = CompatSubject(package: package, name: game.title, isGame: true,
                iconPath: model.paths.game(game.id).appendingPathComponent("icon.data").path,
                afterPlaying: true, runtime: game.runtime)
        }
    }
}

struct GameIcon: View {
    let url: URL
    let size: CGFloat
    private var thumbnail: NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
    var body: some View {
        Group {
            if let icon = thumbnail { Image(nsImage: icon).resizable().interpolation(.high) }
            else { Image(systemName: "gamecontroller.fill").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(.secondary).background(.quaternary) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.19))
    }
}

struct GameDetail: View {
    let game: LibraryGame
    @ObservedObject var model: LibraryModel
    @ObservedObject var session: SessionController
    @State private var removeConfirmation = false
    @State private var saveConfirmation = false
    @State private var reporting: CompatSubject?
    var running: Bool { session.active && session.gameID == game.id }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 22) {
                    GameIcon(url: model.paths.game(game.id).appendingPathComponent("icon.data"), size: 100)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(game.title).font(.largeTitle.weight(.bold))
                        Text(game.runtime == "orbit" ? "收集八颗星星，避开穿行的障碍。" :
                             game.runtime == "minecraft" ? "Minecraft · macOS 原生运行" :
                             game.runtime == "nativeactivity" ? "macOS 原生运行" :
                             game.runtime == "unity" ? "Unity · macOS 原生运行" : "已导入资料库").foregroundStyle(.secondary)
                        Label(Playtime.text(Playtime.seconds(game.id)), systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                        if let last = game.lastPlayed { Text("上次游玩：\(last.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                HStack {
                    if running {
                        Button(session.state == "paused" ? "继续游戏" : "暂停") { session.togglePause() }.disabled(!["running", "paused"].contains(session.state))
                        Button("结束游戏") { session.stop() }
                        Text(session.state == "paused" ? "已暂停" : session.state == "starting" ? "正在启动…" : "运行中").foregroundStyle(.secondary)
                    } else {
                        Button { model.play(game) } label: { Label(session.active ? "切换到此游戏" : "开始游戏", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(!game.playable || model.importBusy)
                    }
                }
                if let error = session.error, session.gameID == game.id {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)
                }
                if let reason = game.unavailableReason { Label(reason, systemImage: "info.circle").foregroundStyle(.secondary) }
                if game.playable {
                    GroupBox("操作") {
                        VStack(alignment: .leading, spacing: 10) {
                            if game.runtime == "minecraft" {
                                Label("WASD 移动，鼠标控制视角；其他按键可在游戏中设置", systemImage: "keyboard")
                                Label("支持手柄与中文文字输入", systemImage: "gamecontroller")
                                Label("Esc 打开游戏菜单；结束游戏时等待世界保存完成", systemImage: "pause.circle")
                            } else if game.runtime != "orbit" {
                                Label("鼠标点击和拖动对应屏幕触摸", systemImage: "cursorarrow")
                                Label("键盘和手柄操作取决于游戏本身", systemImage: "gamecontroller")
                                Label("⌘P 暂停或继续；⌘Q 结束游戏", systemImage: "pause.circle")
                            } else {
                                Label("方向键 / WASD 移动；按住鼠标前往目标", systemImage: "keyboard")
                                Label("手柄左摇杆 / 方向键移动，A 开始新一轮", systemImage: "gamecontroller")
                                Label("P 或 Esc 暂停，R 开始新一轮；退出时自动保存", systemImage: "pause.circle")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }
                }
                if let package = game.packageName, game.fixture == nil {
                    MacCompatibilitySection(subject: CompatSubject(package: package, name: game.title, isGame: true,
                        iconPath: model.paths.game(game.id).appendingPathComponent("icon.data").path,
                        runtime: game.runtime), reporting: $reporting)
                }
                GroupBox("游戏设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("静音", isOn: Binding(get: { game.settings.muted }, set: { model.settings(game, muted: $0) })).disabled(running)
                        Toggle("启动时全屏", isOn: Binding(get: { game.settings.openFullScreen }, set: { model.settings(game, fullScreen: $0) })).disabled(running)
                        Toggle("游戏窗口失去焦点时暂停", isOn: Binding(get: { game.settings.pauseWhenInactive }, set: { model.settings(game, pause: $0) }))
                        Text("失焦暂停立即生效；静音在下次启动游戏时生效。").font(.caption).foregroundStyle(.secondary)
                        Toggle("JIT-less（实验性）", isOn: Binding(get: { game.settings.jitless }, set: { model.settings(game, jitless: $0) }))
                            .disabled(running || (!game.settings.jitless && game.jitlessUnavailableReason != nil))
                        Text(LocalizedStringKey(game.jitlessUnavailableReason ?? "首次启动会在本机转换并签名游戏库，可能需要较长时间。需要动态代码的游戏或模组不受支持；失败时可关闭此选项。"))
                            .font(.caption).foregroundStyle(.secondary)
                        if Geode.supports(game) {
                            Divider()
                            Toggle("启用 Geode 模组加载器", isOn: Binding(get: { game.settings.geode }, set: { model.setGeode(game, enabled: $0) }))
                                .disabled(model.session.active || model.vm.active || model.importBusy || game.settings.jitless)
                            Text(model.geodeStatus[game.id] ?? (game.settings.geode ? "启动时加载 Geode" : "启用时下载与游戏版本匹配的 Geode"))
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                if model.geodeBusyID == game.id {
                                    ProgressView().controlSize(.small)
                                    Button("取消") { model.cancelGeode() }
                                } else {
                                    Button(game.settings.geode ? "检查 Geode 更新" : "下载并启用 Geode") { model.prepareGeode(game, checkForUpdates: true) }
                                        .disabled(model.session.active || model.vm.active || model.importBusy || game.settings.jitless)
                                }
                            }
                        }
                    }.padding(10)
                }
                if model.vmAvailability.installed {
                    Button("在 Android 中安装并运行") { model.playVM(game) }
                        .disabled(!model.vmAvailable || game.apkNames.count > 32 || game.expansions?.isEmpty == false || model.vm.state == "stopping")
                    if game.expansions?.isEmpty == false { Text("OBB 资源目前仅支持原生运行。").font(.caption).foregroundStyle(.secondary) }
                    if let reason = model.vmAvailability.unavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    Text("Android 实验功能尚未通过 Minecraft 运行和持续音频验证。安装成功不代表游戏可运行；存档保存在所选虚拟机的数据盘中。").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("创建启动快捷方式…") { model.shortcut(game) }.disabled(!game.playable)
                    Button("在访达中显示文件") { NSWorkspace.shared.activateFileViewerSelecting([model.paths.game(game.id)]) }
                    Spacer()
                    Button("清除存档…", role: .destructive) { saveConfirmation = true }.disabled(running || model.importBusy)
                    Button("移除游戏…", role: .destructive) { removeConfirmation = true }.disabled(running || model.importBusy)
                }.controlSize(.small)
            }.padding(32).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
        .confirmationDialog("移除“\(game.title)”？", isPresented: $removeConfirmation) {
            Button("移除游戏，保留存档", role: .destructive) { model.remove(game) }
        } message: { Text("删除受管游戏文件。存档会保留，重新导入此游戏后可继续使用。") }
        .confirmationDialog("永久清除“\(game.title)”的存档？", isPresented: $saveConfirmation) {
            Button("清除存档", role: .destructive) { model.deleteSave(game) }
        } message: { Text("此操作无法撤销，游戏文件会保留。") }
        .sheet(item: $reporting) { MacCompatReportSheet(subject: $0) }
    }
}

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var account = Account.shared
    @ObservedObject var model: LibraryModel
    @AppStorage(CompatibilityStore.askKey) private var askCompatibility = false
    @AppStorage(Holiday.key) private var holiday = true
    @AppStorage("macos.appearance") private var appearance = "system"
    @AppStorage(AppLanguage.key) private var language = "system"
    var body: some View {
        Form {
            Button { openWindow(id: "account") } label: {
                HStack(spacing: 14) {
                    AccountAvatar(size: 46)
                    VStack(alignment: .leading) {
                        Text(account.user?.displayName ?? String(localized: "Sign in")).font(.headline)
                        Text("Profile, playtime and achievements").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "chevron.right")
                }
            }.buttonStyle(.plain)
            Picker("Language", selection: $language) {
                Text("System default").tag("system"); Text("English").tag("en"); Text("简体中文").tag("zh-Hans")
            }.onChange(of: language) { _, value in AppLanguage.set(value) }
            Text("Restart Husk to apply the language to every screen. Applications use it on their next launch.").font(.caption).foregroundStyle(.secondary)
            Picker("外观", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
            Toggle("圣诞装饰", isOn: $holiday)
            LabeledContent("资料目录") { Text(model.paths.root.path).font(.caption).textSelection(.enabled) }
            Button("在访达中打开资料目录") { NSWorkspace.shared.open(model.paths.root) }
            Text("导入会复制游戏到资料库。移除游戏保留存档；清除存档需在游戏详情中单独操作。").foregroundStyle(.secondary)
            Toggle("游戏结束后询问运行情况", isOn: $askCompatibility)
            Link("上游社区兼容性列表", destination: CompatibilityStore.site)
        }.padding(24).frame(width: 520)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: LibraryModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.session.active || model.vm.active || model.playStore.hasActiveDownloads || model.playStore.browserLogin.active || model.geodeBusyID != nil else { return .terminateNow }
        let session = model.session
        session.stop(); model.vm.stop(); model.playStore.stopDownloads(); model.playStore.cancelLogin(); model.cancelGeode()
        Task {
            let deadline = Date().addingTimeInterval(60)
            while (session.active || model.vm.active || model.playStore.hasActiveDownloads || model.playStore.browserLogin.active || model.geodeBusyID != nil) && Date() < deadline { try? await Task.sleep(nanoseconds: 200_000_000) }
            sender.reply(toApplicationShouldTerminate: !session.active && !model.vm.active && !model.playStore.hasActiveDownloads && !model.playStore.browserLogin.active && model.geodeBusyID == nil)
        }
        return .terminateLater
    }
}

@main
struct HuskMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = LibraryModel()
    var body: some Scene {
        Window("Husk", id: "library") {
            MacHomeShell(model: model).onAppear { delegate.model = model }
        }
        .defaultSize(width: 1040, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入游戏…") { model.showImporter = true }.keyboardShortcut("o").disabled(model.importBusy)
                Button("添加示例游戏") { model.addExamples() }.disabled(model.importBusy)
            }
            CommandMenu("游戏") {
                Button("暂停 / 继续") { model.session.togglePause() }.keyboardShortcut("p").disabled(!model.session.active)
                Button("显示游戏窗口") { model.session.send("window", values: ["action": "show"]) }.disabled(!model.session.active)
                Button("最小化游戏窗口") { model.session.send("window", values: ["action": "minimize"]) }.disabled(!model.session.active)
                Button("切换游戏全屏") { model.session.send("window", values: ["action": "fullscreen"]) }.disabled(!model.session.active)
                Button("文字输入 / 键盘控制") { model.session.send("keyboard") }.keyboardShortcut("t").disabled(!model.session.active)
                Button("结束游戏") { model.session.stop() }.disabled(!model.session.active)
            }
        }
        Window("Google Play", id: "play-store") {
            MacPlayStoreView(model: model, store: model.playStore)
        }.defaultSize(width: 1040, height: 700)
        Window("Husk 帮助", id: "help") { MacHelpView() }.defaultSize(width: 720, height: 600)
        Window("Husk Account", id: "account") { MacAccountView() }.defaultSize(width: 760, height: 660)
        WindowGroup("Screenshots", id: "play-screenshots", for: MacPlayGallery.self) { gallery in
            if let value = gallery.wrappedValue { MacPlayGalleryView(gallery: value) }
        }.defaultSize(width: 1000, height: 720)
        Settings { SettingsView(model: model) }
    }
}
