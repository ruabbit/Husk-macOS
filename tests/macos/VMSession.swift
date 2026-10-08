// SPDX-License-Identifier: GPL-2.0-or-later
// Opt-in real guest acceptance through the product controller; always silent.
import Foundation
import SharedLibrary
import Darwin

@main struct VMSession {
    @MainActor static func waitForExit(_ vm: VMController, pid: Int32) async throws {
        let deadline = Date().addingTimeInterval(65)
        while vm.active && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        guard !vm.active, vm.state == "exited", kill(pid, 0) == -1, errno == ESRCH else {
            throw LibraryFailure(vm.error ?? "VM did not shut down and reap its process")
        }
    }
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 7, args[4] == "--seconds", let seconds = Int(args[5]),
              (60...1800).contains(seconds), ["hvf", "tcg"].contains(args[6]) else {
            print("usage: MacVMSession APP GUEST OUTPUT --seconds SECONDS hvf|tcg"); exit(64)
        }
        let app = URL(fileURLWithPath: args[1]), guest = URL(fileURLWithPath: args[2])
        let output = URL(fileURLWithPath: args[3]), vm = VMController()
        var checks = [String](), failure: String?, pids = [Int32]()
        let started = Date()
        do {
            guard !FileManager.default.fileExists(atPath: output.path) else { throw LibraryFailure("Output already exists") }
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let control = output.appendingPathComponent("control.jsonl")
            try Data().write(to: control)
            let responses = output.appendingPathComponent("responses.jsonl")
            try Data().write(to: responses)
            let handle = try FileHandle(forWritingTo: responses)
            defer { try? handle.close() }
            func start() throws {
                try vm.start(executable: VMController.helper(in: app), guest: guest,
                    logs: output.appendingPathComponent("sessions"), accelerator: args[6],
                    headless: true, muted: true, automation: true, maxRunSeconds: seconds + 60)
                pids.append(vm.pid)
                try JSONSerialization.data(withJSONObject: ["pid": vm.pid, "session": vm.sessionID ?? ""],
                    options: [.prettyPrinted]).write(to: output.appendingPathComponent("session.json"))
            }
            try start()
            try await vm.waitUntilReady()
            checks.append("product-controller-android-ready")
            let deadline = Date().addingTimeInterval(TimeInterval(seconds))
            var consumed = 0, requestedStop = false
            while vm.active && Date() < deadline && !requestedStop {
                let data = try Data(contentsOf: control)
                if data.count > consumed {
                    let bytes = data.dropFirst(consumed)
                    if let last = bytes.lastIndex(of: 10) {
                        for line in bytes[...last].split(separator: 10) {
                            guard let command = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                                  let action = command["command"] as? String else { continue }
                            var response: [String: Any] = ["command": action, "time": Date().timeIntervalSince1970]
                            do {
                                if action == "shutdown" { vm.stop(); requestedStop = true }
                                else if action == "reopen" {
                                    let pid = vm.pid; vm.stop(); try await waitForExit(vm, pid: pid)
                                    checks.append("clean-shutdown-pid-gone-before-reopen")
                                    try start(); try await vm.waitUntilReady()
                                    checks.append("same-controller-cold-reopen")
                                } else {
                                    response["result"] = try await vm.request(action, values: command,
                                        timeout: action == "install" ? 4200 : 90)
                                }
                            } catch { response["error"] = error.localizedDescription }
                            try handle.write(contentsOf: JSONSerialization.data(withJSONObject: response) + Data([10]))
                        }
                        consumed = last + 1
                    }
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            let pid = pids.last!; vm.stop(); try await waitForExit(vm, pid: pid)
            checks.append("clean-shutdown-pid-gone")
        } catch {
            failure = error.localizedDescription
            if vm.active { let pid = vm.pid; vm.stop(); try? await waitForExit(vm, pid: pid) }
        }
        let result: [String: Any] = ["checks": checks, "pids": pids, "state": vm.state,
            "elapsed": Date().timeIntervalSince(started), "error": failure ?? vm.error as Any? ?? NSNull()]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output.appendingPathComponent("result.json"))
        }
        print("VM session: \(vm.state); checks=\(checks); error=\(failure ?? vm.error ?? "none")")
        exit(failure == nil && vm.error == nil ? 0 : 1)
    }
}
