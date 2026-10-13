// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SharedLibrary
import Darwin

@main struct SessionDiagnosticsTests {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        if args.contains("--session") {
            func argument(_ key: String) -> String { args[args.firstIndex(of: key)! + 1] }
            let title = argument("--title")
            try! FileHandle.standardError.write(contentsOf: Data("INITIAL DIAGNOSTIC\n".utf8))
            if title == "flood" {
                let chunk = Data(repeating: 65, count: 65536)
                for _ in 0..<144 { try! FileHandle.standardError.write(contentsOf: chunk) }
            }
            try! FileHandle.standardError.write(contentsOf: Data("\nFINAL FAILURE EVIDENCE\n".utf8))
            let event: [String: Any] = ["protocol": 1, "session": argument("--session"), "seq": 1, "pid": getpid(),
                                       "state": "failed", "event": "failed", "reason": "fixture load failure"]
            try! FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: event) + Data([10]))
            exit(23)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HuskLogTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = SessionController()
        func check(_ ok: Bool, _ message: String) throws {
            guard ok else { throw LibraryFailure(message) }; print("PASS \(message)")
        }
        do {
            for title in ["flood", "short"] {
                let object: [String: Any] = ["id": String(repeating: "a", count: 64), "title": title, "importedAt": 0,
                    "sourceName": "test.apk", "apkNames": ["test.apk"], "digest": "test", "engine": "NativeActivity",
                    "abis": ["arm64-v8a"], "settings": ["muted": true]]
                let game = try JSONDecoder().decode(LibraryGame.self, from: JSONSerialization.data(withJSONObject: object))
                try session.start(executable: URL(fileURLWithPath: args[0]), game: game, apk: root.appendingPathComponent("test.apk"),
                                  checkpoint: root.appendingPathComponent("checkpoint.json"), logs: root, headless: true)
                try await session.wait(until: { !session.active }, timeout: 10)
                let log = root.appendingPathComponent(session.sessionID!)
                let tail = try Data(contentsOf: log.appendingPathComponent("stderr.log"))
                let first = try String(contentsOf: log.appendingPathComponent("stderr.first.log"), encoding: .utf8)
                let status = try JSONSerialization.jsonObject(with: Data(contentsOf: log.appendingPathComponent("supervisor.json"))) as! [String: Any]
                try check(String(decoding: tail, as: UTF8.self).contains("FINAL FAILURE EVIDENCE") && first.hasPrefix("INITIAL DIAGNOSTIC"), "\(title)-preserves-first-and-final-diagnostics")
                try check(status["exitStatus"] as? Int == 23 && status["terminationReason"] as? String == "exit" &&
                          status["phase"] as? String == "finished" && status["storageClosed"] as? Bool == false &&
                          session.error == "fixture load failure", "\(title)-persists-real-exit-without-storage-success")
                let files = try FileManager.default.contentsOfDirectory(at: log, includingPropertiesForKeys: [.fileSizeKey])
                let size = try files.filter { $0.lastPathComponent.hasPrefix("stderr") }.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
                try check(size <= (4 << 20) + (512 << 10), "\(title)-retained-output-is-bounded")
                try check(status["stderrMiddleDiscarded"] as? Bool == (title == "flood"), "\(title)-records-diagnostic-coverage")
            }
        } catch { print("FAIL \(error)"); exit(1) }
    }
}
