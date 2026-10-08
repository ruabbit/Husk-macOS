// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SharedLibrary

@main struct VMControllerTests {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 3 else { exit(64) }
        let root = URL(fileURLWithPath: args[2]).appendingPathComponent("VMExit-\(UUID().uuidString)")
        let executable = root.appendingPathComponent("Fixture.app/Contents/MacOS/VMRunner")
        let plist = root.appendingPathComponent("Fixture.app/Contents/Info.plist")
        let controller = VMController()
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw LibraryFailure(message) }; print("PASS \(message)")
        }
        func metadata(_ version: String?) throws {
            let info = version.map { ["LSMinimumSystemVersion": $0] } ?? [:]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        }
        do {
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: args[1]), to: executable)
            try metadata("27.1.2")
            let old = VMController.availability(executable: executable, systemVersion: .init(majorVersion: 14, minorVersion: 0, patchVersion: 0))
            let same = VMController.availability(executable: executable, systemVersion: .init(majorVersion: 27, minorVersion: 1, patchVersion: 2))
            let patch = VMController.availability(executable: executable, systemVersion: .init(majorVersion: 27, minorVersion: 1, patchVersion: 1))
            try check(old.installed && !old.available && old.unavailableReason?.contains("27.1.2") == true && same.available && !patch.available,
                      "availability-enforces-packaged-version-including-patch")
            try metadata(nil)
            try check(!VMController.availability(executable: executable).available, "missing-platform-metadata-fails-closed")
            try metadata("27.invalid")
            try check(!VMController.availability(executable: executable).available, "invalid-platform-metadata-fails-closed")
            let absent = VMController.availability(executable: root.appendingPathComponent("missing"))
            try check(!absent.installed && !absent.available, "optional-vm-absence-is-distinct-from-old-system")

            let guest = root.appendingPathComponent("guest")
            try FileManager.default.createDirectory(at: guest, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: guest.appendingPathComponent("guest.json"))
            try metadata("999.0")
            var refused = false
            do { try controller.start(executable: executable, guest: guest, logs: root, headless: true) }
            catch { refused = error.localizedDescription.contains("999.0") }
            try check(refused && !controller.active && controller.pid == 0, "unsupported-host-rejected-before-process-start")
            try metadata("14.0")
            for mode in ["delayed", "stderr-first", "stdout-first", "missing", "partial", "failure", "nonzero", "stalled", "normal"] {
                try Data(mode.utf8).write(to: guest.appendingPathComponent("mode"))
                let start = Date()
                try controller.start(executable: executable, guest: guest, logs: root, headless: true)
                let session = controller.sessionID!
                while controller.active && Date().timeIntervalSince(start) < 6 {
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                try check(!controller.active && controller.pid == 0, "\(mode)-reaped-with-readers-finished")
                let success = ["delayed", "stderr-first", "stdout-first", "normal"].contains(mode)
                try check(controller.state == (success ? "exited" : "failed") && (controller.error == nil) == success,
                          "\(mode)-terminal-result")
                let log = root.appendingPathComponent(session)
                let events = try String(contentsOf: log.appendingPathComponent("events.jsonl"), encoding: .utf8)
                let diagnostics = try String(contentsOf: log.appendingPathComponent("stderr.log"), encoding: .utf8)
                if success {
                    try check(events.contains("storage-closed"), "\(mode)-final-event-preserved")
                    if mode != "normal" { try check(diagnostics.contains("diagnostic"), "\(mode)-stderr-drained") }
                }
                if mode == "failure" { try check(controller.error == "fixture failure evidence", "failure-evidence-retained-after-clean-event") }
                if mode == "stalled" {
                    try check(Date().timeIntervalSince(start) < 2.9 && controller.error?.contains("输出通道") == true,
                              "inherited-pipe-timeout-is-bounded-and-explicit")
                }
            }
            // The finite stalled writer exits while the same controller has
            // already reopened. No old EOF callback may change the new result.
            try await Task.sleep(nanoseconds: 1_200_000_000)
            try check(!controller.active && controller.state == "exited" && controller.error == nil,
                      "same-controller-reopens-without-stale-session-events")
            print("VM controller process regressions passed; no Android runtime launched")
        } catch {
            if controller.active { controller.stop() }
            print("FAIL \(error.localizedDescription)"); exit(1)
        }
    }
}
