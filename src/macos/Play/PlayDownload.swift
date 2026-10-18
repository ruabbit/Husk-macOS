// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

struct PlayDownloadedFiles {
    let directory: URL
    let apks: [URL]
    var expansions: [URL] = []
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

struct PlayDownload {
    let session: URLSession
    let root: URL
    init(session: URLSession? = nil, root: URL = FileManager.default.temporaryDirectory) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 3600
        self.session = session ?? URLSession(configuration: configuration)
        self.root = root
    }
    func fetch(_ delivery: PlayAPI.DeliveryData, package: String? = nil, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> PlayDownloadedFiles {
        guard !delivery.requiresAdditionalFiles else { throw PlayError("Play 未返回完整的扩展资源清单。") }
        guard let base = delivery.downloadUrl, !base.isEmpty, delivery.splits.count < 48 else {
            throw PlayError("Play 未返回完整的 APK 集合。")
        }
        var files = [("base.apk", base, delivery.size)] + delivery.splits.enumerated().map {
            (String(format: "split_%02d.apk", $0.offset), $0.element.downloadUrl, $0.element.size)
        }
        guard delivery.expansions.count <= 2, Set(delivery.expansions.map(\.isPatch)).count == delivery.expansions.count else {
            throw PlayError("Play 返回了重复或无效的扩展资源。")
        }
        for expansion in delivery.expansions {
            guard let package, package.range(of: "^[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+$", options: .regularExpression) != nil,
                  expansion.versionCode > 0 else { throw PlayError("扩展资源缺少有效包名或版本。") }
            files.append(("\(expansion.isPatch ? "patch" : "main").\(expansion.versionCode).\(package).obb", expansion.downloadUrl, expansion.size))
        }
        guard files.allSatisfy({ $0.2 >= 0 && $0.2 <= 4 << 30 }),
              Set(delivery.splits.map(\.name)).count == delivery.splits.count else { throw PlayError("Play 返回了无效的分包清单。") }
        let total = files.reduce(Int64(0)) { $0 + $1.2 }
        let fileCount = files.count
        guard total <= 4 << 30 else { throw PlayError("下载大小超过 4 GB。") }
        let directory = root.appendingPathComponent("HuskPlay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: directory) } }
        var apks: [URL] = [], expansions: [URL] = [], completed: Int64 = 0
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            guard let url = URL(string: file.1), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
                throw PlayError("Play 返回了无效的下载地址。")
            }
            var request = URLRequest(url: url)
            request.setValue(PlayDevice.finskyUserAgent, forHTTPHeaderField: "User-Agent")
            if let cookie = delivery.downloadAuthCookie {
                guard !cookie.name.contains(where: { $0.isNewline || $0 == ";" || $0 == "=" }),
                      !cookie.value.contains(where: { $0.isNewline || $0 == ";" }) else { throw PlayError("Play 返回的下载凭据无效。") }
                request.setValue("\(cookie.name)=\(cookie.value)", forHTTPHeaderField: "Cookie")
            }
            let previous = completed
            let destination = directory.appendingPathComponent(file.0)
            let status = try await FileStreamer.download(request, to: destination, configuration: session.configuration,
                                                        maxBytes: min(file.2 > 0 ? file.2 : 4 << 30, (4 << 30) - completed)) { bytes in
                let fraction = total > 0 ? Double(previous + bytes) / Double(total) : Double(index) / Double(fileCount)
                Task { @MainActor in progress(min(0.99, max(0, fraction))) }
            }
            try Task.checkCancellation()
            guard status == 200 else {
                throw PlayError("下载失败（HTTP \(status)），可以重试。")
            }
            let size = (try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard size > 0, size <= 4 << 30, file.2 == 0 || size == file.2, completed + Int64(size) <= 4 << 30 else {
                throw PlayError("下载文件的大小与清单不符。")
            }
            if file.0.hasSuffix(".obb") { expansions.append(destination) } else { apks.append(destination) }
            completed += Int64(size)
            await progress(total > 0 ? min(1, Double(completed) / Double(total)) : Double(index + 1) / Double(files.count))
        }
        complete = true
        return PlayDownloadedFiles(directory: directory, apks: apks, expansions: expansions)
    }
}
