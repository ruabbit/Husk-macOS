// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SharedLibrary
import Darwin

private func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
    guard try condition() else { throw PlayError("FAIL \(name)") }; print("PASS \(name)")
}
private func refused(_ name: String, _ operation: () async throws -> Void) async throws {
    do { try await operation() } catch { print("PASS \(name)"); return }
    throw PlayError("FAIL expected rejection: \(name)")
}
private final class MemoryCredentials: PlaySessionStorage {
    var saved: PlaySession?
    func load() -> PlaySession? { saved }
    func save(_ session: PlaySession) { saved = session }
    func remove() { saved = nil }
}
private actor FakeService: MacPlayService {
    var refreshes = 0
    var expire = true
    private var signInPending: CheckedContinuation<Void, Never>?
    private var signInStarted: CheckedContinuation<Void, Never>?
    private var searchPending: CheckedContinuation<Void, Never>?
    private var searchStarted: CheckedContinuation<Void, Never>?
    func signIn(email: String?, token: String?) async throws -> PlaySession {
        // A deliberately uncancellable service response exercises the store's
        // generation check without assuming a CI scheduler's response time.
        await withCheckedContinuation { continuation in
            signInPending = continuation
            signInStarted?.resume(); signInStarted = nil
        }
        return PlaySession(email: "synthetic@example.invalid", bearer: "test", isAnonymous: true)
    }
    func waitForSignIn() async {
        if signInPending != nil { return }
        await withCheckedContinuation { signInStarted = $0 }
    }
    func finishSignIn() { signInPending?.resume(); signInPending = nil }
    func waitForSlowSearch() async {
        if searchPending != nil { return }
        await withCheckedContinuation { searchStarted = $0 }
    }
    func finishSlowSearch() { searchPending?.resume(); searchPending = nil }
    func refresh(_ session: PlaySession) async throws -> PlaySession { refreshes += 1; return session }
    func browse(_ session: PlaySession) async throws -> [PlayAPI.PlayApp] { [Self.app("browse")] }
    func search(_ query: String, session: PlaySession) async throws -> [PlayAPI.PlayApp] {
        if query == "expired", expire { expire = false; throw PlayError("expired", httpStatus: 401) }
        if query == "slow" {
            await withCheckedContinuation { continuation in
                searchPending = continuation
                searchStarted?.resume(); searchStarted = nil
            }
        }
        if query == "error" { throw PlayError("Service failure", httpStatus: 503) }
        return [Self.app(query)]
    }
    func details(_ package: String, session: PlaySession) async throws -> PlayAPI.PlayApp { Self.app(package) }
    func download(_ app: PlayAPI.PlayApp, session: PlaySession,
                  progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> PlayDownloadedFiles { throw PlayError("offline fixture") }
    static func app(_ name: String) -> PlayAPI.PlayApp {
        .init(id: "org.husk.\(name)", title: name, developer: "Husk", summary: "", iconURL: nil,
              screenshotURLs: [], versionCode: 1, versionString: "1", sizeBytes: 1, downloads: "", rating: 0,
              formattedPrice: "Free", isFree: true)
    }
}
private final class FixtureHTTP: URLProtocol, @unchecked Sendable {
    static var directory: URL!
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "play.test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.lastPathComponent
        DispatchQueue.global().asyncAfter(deadline: .now() + (path == "slow" ? 0.2 : 0.005)) { [self] in
            lock.lock(); defer { lock.unlock() }; guard !stopped else { return }
            let data = (try? Data(contentsOf: Self.directory.appendingPathComponent(path == "slow" ? "base-v1.apk" : path))) ?? Data("denied".utf8)
            let status = path == "fail" ? 503 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(data.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
}

@main struct PlaySupportTests {
    @MainActor static func main() async {
        do {
            let args = CommandLine.arguments
            if args.count == 3, args[1] == "--live" {
                let service = GooglePlayService()
                print("Live guest sign-in (credentials remain in memory)")
                let session = try await service.signIn(email: nil, token: nil)
                print("PASS guest session received")
                let results = try await service.search("com.google.android.calculator", session: session)
                print("Live search returned \(results.count) apps")
                let app = try await service.details("com.google.android.calculator", session: session)
                guard app.isFree else { throw PlayError("Live test only downloads a free app") }
                let files = try await service.download(app, session: session) { _ in }
                defer { files.remove() }
                let root = URL(fileURLWithPath: args[2]).appendingPathComponent("PlayLive-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: root) }
                let repository = try LibraryRepository(paths: LibraryPaths(root: root), trustedFixtureHash: "none")
                let game = try await repository.importAPKs(files.apks, package: app.id, version: app.versionCode, title: app.title)
                print("PASS live search, details, download and signed import: \(game.packageName ?? ""), \(game.apkNames.count) APKs")
                return
            }
            if args.count == 3, args[1] == "--verify" {
                let signatures = try APKSignature.verify(URL(fileURLWithPath: args[2]))
                try check(signatures?.isEmpty == false, "real APK signature and complete content digest")
                return
            }
            try await checkPlayLogin()
            let cases = URL(fileURLWithPath: args[1]), root = URL(fileURLWithPath: args[2]).appendingPathComponent("Play-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            func set(_ version: Int) -> [URL] { [cases.appendingPathComponent("base-v\(version).apk")] + (0..<6).map { cases.appendingPathComponent("split\($0)-v\(version).apk") } }
            let base = set(1)[0]
            let signer = try APKSignature.verify(base)
            try check(signer != nil && signer == APKSignature.verify(set(2)[0]), "v2 and v3 cryptographic signatures")
            for name in ["tampered", "short", "overflow"] {
                try await refused("reject \(name) APK") { _ = try APKSignature.verify(cases.appendingPathComponent("\(name).apk")) }
            }
            let paths = LibraryPaths(root: root.appendingPathComponent("Library"))
            let library = try LibraryRepository(paths: paths, trustedFixtureHash: "none")
            let first = try await library.importAPKs(Array(set(1).reversed()), package: "org.husk.playtest", version: 1, title: "Play fixture")
            try check(first.apkNames.count == 7 && first.apkNames.first == "base-v1.apk", "seven APKs form one base-first installation")
            try check(first.signerSHA256 == signer && first.packageName == "org.husk.playtest" && first.versionCode == 1, "persist verified package version and signer")
            try await library.update(first.id, muted: true, pauseWhenInactive: true)
            try FileManager.default.createDirectory(at: paths.save(first.id), withIntermediateDirectories: true)
            let save = paths.save(first.id).appendingPathComponent("world.dat")
            try Data("existing save".utf8).write(to: save)
            for (name, files, version) in [
                ("mixed package", [base, cases.appendingPathComponent("wrong-package.apk")], 1),
                ("mixed signer", [base, cases.appendingPathComponent("wrong-split-key.apk")], 1),
                ("mixed version", [base, set(2)[1]], 1),
                ("no base", Array(set(1).dropFirst()), 1),
                ("changed signer update", [cases.appendingPathComponent("wrong-key.apk")], 2),
                ("tampered delivery", [cases.appendingPathComponent("tampered.apk")], 1)
            ] {
                try await refused(name) { _ = try await library.importAPKs(files, package: "org.husk.playtest", version: version, title: "bad") }
                let current = try await library.games()
                try check(current.count == 1 && current[0].digest == first.digest, "\(name) preserves previous install")
            }
            try await refused("active game update") {
                _ = try await library.importAPKs(set(2), package: "org.husk.playtest", version: 2, title: "update", blockedIDs: [first.id])
            }
            let upgraded = try await library.importAPKs(set(2), package: "org.husk.playtest", version: 2, title: "update")
            try check(upgraded.id == first.id && upgraded.versionCode == 2 && upgraded.settings.muted && upgraded.settings.pauseWhenInactive,
                      "atomic update preserves identity and settings")
            try check(try Data(contentsOf: save) == Data("existing save".utf8), "update preserves save bytes")
            try await refused("downgrade") { _ = try await library.importAPKs(set(1), package: "org.husk.playtest", version: 1, title: "old") }
            let (_, vmFiles, package) = try await library.prepareVMSet(first.id)
            try check(vmFiles.count == 7 && package == "org.husk.playtest", "VM receives the complete verified APK set")
            try check(try FileManager.default.contentsOfDirectory(atPath: paths.root.appendingPathComponent("Staging").path).isEmpty, "imports clean staging")
            // Simulate interruption on each side of the index commit, using only
            // the disposable library. No process crashes or fault signals.
            for committed in [false, true] {
                let recoveryPaths = LibraryPaths(root: root.appendingPathComponent(committed ? "Committed" : "Uncommitted"))
                let recovery = try LibraryRepository(paths: recoveryPaths, trustedFixtureHash: "none")
                let oldGame = try await recovery.importAPKs(set(1), package: "org.husk.playtest", version: 1, title: "old")
                let stageID = UUID().uuidString
                let stage = recoveryPaths.root.appendingPathComponent("Staging/\(stageID)")
                try FileManager.default.copyItem(at: paths.game(first.id), to: stage)
                let journal: [String: Any] = ["id": first.id, "stage": stageID, "newDigest": upgraded.digest, "oldDigest": oldGame.digest]
                try JSONSerialization.data(withJSONObject: journal).write(to: recoveryPaths.root.appendingPathComponent(".install-transaction.json"))
                guard renamex_np(stage.path, recoveryPaths.game(first.id).path, UInt32(RENAME_SWAP)) == 0 else { throw PlayError("test swap failed") }
                if committed { try Data(contentsOf: paths.index).write(to: recoveryPaths.index) }
                let recovered = try await recovery.games()
                try check(recovered[0].digest == (committed ? upgraded.digest : oldGame.digest), "interrupted update recovers \(committed ? "committed" : "previous") index")
                let (_, files, _) = try await recovery.prepareVMSet(first.id)
                try check(files.count == 7 && !FileManager.default.fileExists(atPath: stage.path), "interrupted update recovers matching files and cleans staging")
            }


            FixtureHTTP.directory = cases
            let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureHTTP.self]
            let http = URLSession(configuration: configuration)
            defer { http.invalidateAndCancel() }
            let downloadRoot = root.appendingPathComponent("Downloads")
            try FileManager.default.createDirectory(at: downloadRoot, withIntermediateDirectories: true)
            let downloader = PlayDownload(session: http, root: downloadRoot)
            func delivery(_ baseName: String, splits: [PlayAPI.DeliveryData.SplitFile] = [], size: Int64 = 0) -> PlayAPI.DeliveryData {
                .init(downloadUrl: "https://play.test.invalid/\(baseName)", size: size, splits: splits, downloadAuthCookie: nil)
            }
            var progress: Double = 0
            let downloaded = try await downloader.fetch(delivery("base-v1.apk", splits: (0..<6).map {
                .init(name: "config.test\($0)", size: 0, downloadUrl: "https://play.test.invalid/split\($0)-v1.apk")
            })) { progress = $0 }
            try check(downloaded.apks.count == 7 && progress == 1, "download preserves every split and reports completion")
            downloaded.remove()
            // The same production downloader now streams APKs and OBBs into one
            // disposable installation; the library publishes them together.
            let mainOBB = cases.appendingPathComponent("main.1.org.husk.playtest.obb")
            let patchOBB = cases.appendingPathComponent("patch.1.org.husk.playtest.obb")
            try Data("main expansion payload".utf8).write(to: mainOBB)
            try Data("patch expansion payload".utf8).write(to: patchOBB)
            var expanded = delivery("base-v1.apk")
            expanded.expansions = [mainOBB, patchOBB].enumerated().map { i, url in
                .init(isPatch: i == 1, versionCode: 1, size: 0, downloadUrl: "https://play.test.invalid/\(url.lastPathComponent)")
            }
            let resources = try await downloader.fetch(expanded, package: "org.husk.playtest") { _ in }
            defer { resources.remove(); try? FileManager.default.removeItem(at: mainOBB); try? FileManager.default.removeItem(at: patchOBB) }
            try check(resources.apks.count == 1 && resources.expansions.count == 2, "streamed OBBs stay separate from APK package installer")
            let obbPaths = LibraryPaths(root: root.appendingPathComponent("WithOBB"))
            let obbRepository = try LibraryRepository(paths: obbPaths, trustedFixtureHash: "none")
            let obbGame = try await obbRepository.importAPKs(resources.apks + resources.expansions, package: "org.husk.playtest", version: 1, title: "OBB")
            try check(obbGame.expansions?.count == 2 && obbGame.apkNames.count == 1, "OBB metadata published with the APK installation")
            try check(try Data(contentsOf: obbPaths.game(obbGame.id).appendingPathComponent("obb/\(mainOBB.lastPathComponent)")) == Data(contentsOf: mainOBB), "installed OBB bytes match streamed resource")
            let again = try LibraryRepository(paths: obbPaths, trustedFixtureHash: "none")
            let reopenedOBB = try await again.games()
            try check(reopenedOBB.first?.expansions == obbGame.expansions, "OBB hashes survive repository reopen")
            try await refused("VM never silently drops required OBB resources") { _ = try await again.prepareVMSet(obbGame.id) }
            let archivePaths = LibraryPaths(root: root.appendingPathComponent("ArchivedOBB"))
            let archiveRepository = try LibraryRepository(paths: archivePaths, trustedFixtureHash: "none")
            let archived = try await archiveRepository.importGame(cases.appendingPathComponent("expanded.xapk"))
            try check(archived.expansions?.count == 1 &&
                      (try Data(contentsOf: archivePaths.game(archived.id).appendingPathComponent("obb/main.1.org.husk.playtest.obb"))) == Data("archived main resource".utf8),
                      "XAPK imports its OBB in the same installation transaction")
            let zip64Paths = LibraryPaths(root: root.appendingPathComponent("Zip64OBB"))
            let zip64Repository = try LibraryRepository(paths: zip64Paths, trustedFixtureHash: "none")
            let zip64 = try await zip64Repository.importGame(cases.appendingPathComponent("expanded-zip64.xapk"))
            try check(zip64.expansions == archived.expansions && zip64.digest == archived.digest,
                      "Zip64 deflated APK and OBB import matches ordinary XAPK bytes and metadata")
            let reopenedZip64 = try LibraryRepository(paths: zip64Paths, trustedFixtureHash: "none")
            let zip64Games = try await reopenedZip64.games()
            try check(zip64Games.first?.expansions == archived.expansions, "Zip64 OBB manifest survives repository reopen")
            try await refused("foreign-package archived OBB") { _ = try await archiveRepository.importGame(cases.appendingPathComponent("foreign-obb.xapk")) }
            try await refused("incomplete same-version replacement preserves OBB installation") {
                _ = try await obbRepository.importAPKs(resources.apks, package: "org.husk.playtest", version: 1, title: "missing")
            }
            var invalidExpansion = expanded; invalidExpansion.expansions += [expanded.expansions[0]]
            try await refused("duplicate OBB roles") { _ = try await downloader.fetch(invalidExpansion, package: "org.husk.playtest") { _ in } }
            let fullSet = [cases.appendingPathComponent("base-v1.apk")] + (0..<47).map { cases.appendingPathComponent("split\($0)-v1.apk") }
            let large = try LibraryRepository(paths: LibraryPaths(root: root.appendingPathComponent("48APKs")), trustedFixtureHash: "none")
            let largeGame = try await large.importAPKs(fullSet, package: "org.husk.playtest", version: 1, title: "48 APKs")
            try check(largeGame.apkNames.count == 48, "48 signed APKs import as a single set")
            try await refused("49 APKs refused") { _ = try await large.importAPKs(fullSet + [fullSet[0]], package: "org.husk.playtest", version: 1, title: "too many") }
            for plan in [delivery("fail"), delivery("base-v1.apk", size: 1), delivery("base-v1.apk", splits: [.init(name: "bad", size: 1, downloadUrl: "http://play.test.invalid/split.apk")])] {
                try await refused("failed or incomplete download") { _ = try await downloader.fetch(plan) { _ in } }
                try check(try FileManager.default.contentsOfDirectory(atPath: downloadRoot.path) == [resources.directory.lastPathComponent], "failed download cleans all partial files")
            }
            let cancelled = Task { try await downloader.fetch(delivery("slow")) { _ in } }
            try await Task.sleep(for: .milliseconds(30)); cancelled.cancel()
            try await refused("download cancellation") { _ = try await cancelled.value }
            try check(try FileManager.default.contentsOfDirectory(atPath: downloadRoot.path) == [resources.directory.lastPathComponent], "cancel removes partial download")

            let service = FakeService(), credentials = MemoryCredentials()
            let store = MacPlayStore(service: service, credentials: credentials)
            let cancelledLogin = store.connect()
            await service.waitForSignIn()
            store.signOut()
            await service.finishSignIn(); await cancelledLogin.value
            try check(store.session == nil && credentials.saved == nil, "late sign-in cannot restore a signed-out account")
            let login = store.connect()
            await service.waitForSignIn()
            try check(store.busy && store.session == nil && credentials.saved == nil, "pending login has no persisted session")
            await service.finishSignIn(); await login.value
            try check(store.session != nil && credentials.saved != nil, "login persists through credential storage")
            let old = Task { await store.load(query: "slow") }
            await service.waitForSlowSearch()
            await store.load(query: "new")
            await service.finishSlowSearch(); await old.value
            try check(store.apps.first?.title == "new" && !store.searching, "late search cannot overwrite newer results")
            await store.load(query: "expired")
            let count = await service.refreshes
            try check(store.apps.first?.title == "expired" && count == 1, "expired bearer refreshes once and retries")
            await store.load(query: "error")
            try check(store.error?.contains("Service failure") == true && store.apps.isEmpty, "search error stays visible")
            store.signOut(); try check(credentials.saved == nil && store.session == nil, "sign out clears persisted tokens")
            var offerless = ProtoWriter(); offerless.string(1, "org.husk.price"); offerless.string(5, "No offer")
            try check(PlayAPI.PlayApp.from(doc: ProtoMessage(offerless.data))?.isFree == false, "missing offer cannot trigger free purchase")
            _ = ProtoMessage(Data([0x0b,0x12] + Array(repeating: 0xff, count: 9) + [0x01]))
            print("PASS malformed network protobuf does not overflow")
            print("Play support regression complete")
        } catch { print("FAIL \(error.localizedDescription)"); exit(1) }
    }
}
