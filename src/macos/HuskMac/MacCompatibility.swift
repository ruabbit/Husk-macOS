// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UniformTypeIdentifiers

extension CompatibilityStore.Status {
    var macLabel: String {
        switch self {
        case .works: return "正常运行"
        case .opens: return "能启动，但有问题"
        case .broken: return "无法运行"
        case .protected: return "受保护"
        }
    }
}

struct MacCompatibilitySection: View {
    let subject: CompatSubject
    @Binding var reporting: CompatSubject?
    @ObservedObject private var store = CompatibilityStore.shared
    var body: some View {
        GroupBox("社区兼容性") {
            VStack(alignment: .leading, spacing: 10) {
                if let entry = store.entry(subject.package), let status = entry.status {
                    Label(status.macLabel, systemImage: status.symbol).foregroundStyle(status.color)
                    if let official = entry.official, !official.note.isEmpty { Text(official.note).textSelection(.enabled) }
                    Text("\(entry.community.reports) 份玩家报告").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(store.error == nil ? "暂无社区报告" : "暂时无法更新社区报告").foregroundStyle(.secondary)
                }
                Text("来自上游兼容性列表，官方结果在 iPhone 上测试；不代表此 Mac 的运行结果。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("报告运行情况…") { reporting = subject }
                    Link("查看原始报告", destination: store.pageURL(subject.package))
                    if store.error != nil { Button("重试") { Task { await store.refresh(force: true) } } }
                }.controlSize(.small)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }.task { await store.refresh() }
    }
}

struct MacCompatReportSheet: View {
    let subject: CompatSubject
    @Environment(\.dismiss) private var dismiss
    @AppStorage("husk.compatAuthor") private var author = ""
    @State private var status: CompatibilityStore.Status?
    @State private var isGame = true
    @State private var notes = ""
    @State private var sending = false
    @State private var error: String?
    @State private var sendTask: Task<Void, Never>?
    @State private var choosingLog = false
    @State private var logName: String?
    @State private var logText: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("报告“\(subject.name)”的运行情况").font(.title2)
            Picker("运行结果", selection: $status) {
                Text("请选择").tag(Optional<CompatibilityStore.Status>.none)
                ForEach([CompatibilityStore.Status.works, .opens, .broken], id: \.self) { value in
                    Text(value.macLabel).tag(Optional(value))
                }
            }
            Picker("类型", selection: $isGame) { Text("游戏").tag(true); Text("应用").tag(false) }
            TextField("你的称呼（可留空）", text: $author)
            TextField("运行到哪一步、遇到什么问题", text: $notes, axis: .vertical).lineLimit(4...8)
            HStack {
                Button("选择日志附件…") { choosingLog = true }.disabled(sending)
                if let logName {
                    Text(logName).lineLimit(1).truncationMode(.middle)
                    Button("移除") { self.logName = nil; logText = nil }.disabled(sending)
                } else { Text("不附带日志").foregroundStyle(.secondary) }
            }
            if let logText {
                DisclosureGroup("预览将公开的日志（\(logText.utf8.count) 字节）") {
                    ScrollView { Text(logText).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 140)
                }
                Text("仅附带所选文件末尾最多 400 KB。请检查预览中的账号、路径或其他个人信息。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("将公开发布到 itslevii.dev（备用 antiweb.lol）：应用包名、名称、图标、类型、所选结果、称呼和说明，以及 \(CompatibilityStore.device)、\(CompatibilityStore.systemVersion)、Husk build \(CompatibilityStore.build)、运行组件 \(subject.runtime ?? "unknown")。")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button(subject.afterPlaying ? "稍后" : "取消") {
                    if subject.afterPlaying { CompatibilityStore.shared.markAsked(subject.package) }
                    dismiss()
                }.keyboardShortcut(.cancelAction).disabled(sending)
                Spacer()
                if sending { ProgressView().controlSize(.small) }
                Button("发送报告") { send() }.keyboardShortcut(.defaultAction).disabled(sending || status == nil)
            }
        }.padding(24).frame(width: 530)
        .onAppear { isGame = subject.isGame; if let crash = subject.crash { status = .broken; notes = crash } }
        .onDisappear { sendTask?.cancel() }
        .fileImporter(isPresented: $choosingLog, allowedContentTypes: [.plainText, .json, .log, .data]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let text = CompatibilityStore.logTail(url: url) else {
                    error = "日志为空或无法读取。"; return
                }
                logName = url.lastPathComponent; logText = text; error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
    private func send() {
        guard let status else { return }
        sending = true; error = nil
        sendTask = Task { @MainActor in
            do {
                try await CompatibilityStore.shared.send(package: subject.package, name: subject.name, isGame: isGame,
                    status: status, notes: notes, author: author, iconPath: subject.iconPath, runtime: subject.runtime,
                    attachLog: logText != nil, logText: logText)
                dismiss()
            } catch { self.error = error.localizedDescription }
            sending = false
        }
    }
}
