// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
@testable import SharedLibrary

final class OfflineRelease: URLProtocol {
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if request.url?.host == "api.geode-sdk.org" {
            let body = Data(#"{"payload":{"version":"6.0.0","downloads":{"android64":"https://downloads.invalid/release.zip"}}}"#.utf8)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        } else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    }
    override func stopLoading() {}
}
@main struct GeodeTests {
    static func check(_ value: Bool, _ why: String) throws {
        if !value { throw LibraryFailure(why) }; print("PASS \(why)")
    }
    static func rejects(_ why: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch { print("PASS \(why)"); return }
        throw LibraryFailure("did not reject: \(why)")
    }
    static func main() async {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1]), fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("husk-geode-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        do {
            let settings = try JSONDecoder().decode(GameSettings.self, from: Data(#"{"muted":true}"#.utf8))
            try check(!settings.geode && settings.muted, "old settings default Geode off")
            let release = try GeodeRelease.parse(["payload": ["version":"v5.0.0", "downloads":["android32":"https://example.com/32.zip", "android64":["url":"https://example.com/64.zip"]]]])
            try check(release.0 == "v5.0.0" && release.1.path == "/64.zip", "release selects version and arm64 asset")
            try rejects("missing arm64 is rejected") { _ = try GeodeRelease.parse(["version":"5.0.0","downloads":["android32":"https://example.com/32.zip"]]) }
            try rejects("unsafe release version is rejected") { _ = try GeodeRelease.parse(["version":"../5","downloads":["android64":"https://example.com/64.zip"]]) }
            try rejects("non-HTTPS asset is rejected") { _ = try GeodeRelease.parse(["version":"5.0.0","downloads":["android64":"http://example.com/64.zip"]]) }
            let launcher = try GeodeRelease.launcher(["assets":[["browser_download_url":"https://example.com/launcher-android32.apk"],["browser_download_url":"https://example.com/launcher-android64.apk"]]])
            try check(launcher.path.contains("android64"), "launcher skips 32-bit release")

            let paths = LibraryPaths(root: root)
            let repository = try LibraryRepository(paths: paths, trustedFixtureHash: "")
            let imported = try await repository.importGame(fixtures.appendingPathComponent("normal/game.apk"))
            try check(Geode.supports(imported) && imported.versionCode == 39, "actual manifest and Cocos profile enable Geode")
            let (_, apks, checkpoint) = try await repository.prepare(imported.id), apk = apks[0]
            let saves = checkpoint.deletingLastPathComponent().appendingPathComponent("mods.geode")
            try Data("user mod".utf8).write(to: saves)
            func stage() throws -> URL {
                let folder = apk.deletingLastPathComponent().appendingPathComponent(".stage-\(UUID().uuidString)")
                try fm.copyItem(at: fixtures.appendingPathComponent("normal/geode"), to: folder); return folder
            }
            var staged = try stage()
            _ = try Geode.install(game: imported, apk: apk, version: "5.0.0", staged: staged)
            try check(try Geode.installed(game: imported, apk: apk).version == "5.0.0", "complete staged install validates")
            try await repository.update(imported.id, geode: true)
            let (enabled, _, _) = try await repository.prepare(imported.id)
            try check(try Geode.arguments(game: enabled, apk: apk) == ["--geode-directory", Geode.directory(apk: apk).path], "enabled launch passes only validated cache")
            let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [OfflineRelease.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            _ = try await Geode.prepare(game: enabled, apk: apk, session: session)
            try check(OfflineRelease.requests == 0, "matching cache launches offline without a release query")
            do { _ = try await Geode.prepare(game: enabled, apk: apk, checkForUpdates: true, session: session); throw LibraryFailure("unexpected download success") }
            catch is URLError { print("PASS failed update download is reported") }
            try check(try Geode.installed(game: enabled, apk: apk).version == "5.0.0", "failed update preserves usable cache")
            try check(try !fm.contentsOfDirectory(atPath: apk.deletingLastPathComponent().path).contains { $0.hasPrefix(".geode-") }, "failed download cleans staging")
            staged = try stage(); try fm.removeItem(at: staged.appendingPathComponent(Geode.resourcesName))
            try rejects("Geode 5 requires separate resources") { _ = try Geode.install(game: enabled, apk: apk, version: "5.0.0", staged: staged) }
            try fm.removeItem(at: staged)
            staged = try stage(); try fm.removeItem(at: staged.appendingPathComponent(Geode.releaseName))
            try fm.copyItem(at: fixtures.appendingPathComponent("traversal.zip"), to: staged.appendingPathComponent(Geode.releaseName))
            try rejects("archive path traversal is rejected") { _ = try Geode.install(game: enabled, apk: apk, version: "5.0.0", staged: staged) }
            try fm.removeItem(at: staged)
            let resources = Geode.directory(apk: apk).appendingPathComponent(Geode.resourcesName)
            var corrupt = try Data(contentsOf: resources); corrupt[corrupt.count - 1] ^= 1; try corrupt.write(to: resources)
            try rejects("same-size cache tampering blocks launch") { _ = try Geode.arguments(game: enabled, apk: apk) }
            staged = try stage()
            try fm.removeItem(at: staged.appendingPathComponent(Geode.releaseName)); try fm.removeItem(at: staged.appendingPathComponent(Geode.resourcesName))
            try fm.copyItem(at: fixtures.appendingPathComponent("geode4.zip"), to: staged.appendingPathComponent(Geode.releaseName))
            _ = try Geode.install(game: enabled, apk: apk, version: "4.10.2", staged: staged)
            try check(try Geode.installed(game: enabled, apk: apk).version == "4.10.2", "atomic replacement accepts Geode 4 embedded resources")
            try check(!fm.fileExists(atPath: staged.path), "old cache removed after atomic replacement")
            var changed = enabled; changed.versionCode = 40
            try rejects("game update invalidates Geode cache") { _ = try Geode.installed(game: changed, apk: apk) }
            try await repository.update(imported.id, geode: false)
            let (disabled, _, _) = try await repository.prepare(imported.id)
            try check(try Geode.arguments(game: disabled, apk: apk).isEmpty, "disabled setting omits injection")
            try check(try Data(contentsOf: saves) == Data("user mod".utf8), "download, update and disable preserve save files")
        } catch { print("FAIL \(error)"); exit(1) }
    }
}
