// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit opt-in real APK acceptance. Never launches a visible window.
import Foundation
import SharedLibrary
import Darwin

@main struct MinecraftSession {
    @MainActor static func main() async {
        let args=CommandLine.arguments
        guard args.count == 7 || args.count == 8, let seconds=Double(args[6]), seconds > 0, seconds <= 3600 else {
            print("usage: MacMinecraftSession APP APK LIBRARY OUTPUT CONTROL_SECONDS [--hidden-window]"); exit(64)
        }
        // Keep the CLI's explicit label for safety when running from scripts.
        guard args[5] == "--seconds" else { exit(64) }
        let app=URL(fileURLWithPath:args[1]), apk=URL(fileURLWithPath:args[2])
        let paths=LibraryPaths(root:URL(fileURLWithPath:args[3])), output=URL(fileURLWithPath:args[4])
        let session=SessionController(), fm=FileManager.default
        var checks=[String](), failure: String?
        do {
            try fm.createDirectory(at:output,withIntermediateDirectories:true)
            let catalog=try JSONSerialization.jsonObject(with:Data(contentsOf:app.appendingPathComponent("Contents/Resources/fixture-catalog.json"))) as! [String:Any]
            let repository=try LibraryRepository(paths:paths,trustedFixtureHash:catalog["sha256"] as! String)
            let imported=try await repository.importGame(apk)
            guard imported.playable, imported.runtime == "minecraft" else { throw LibraryFailure("Minecraft sample was not accepted") }
            checks.append("exact-apk-imported")
            try await repository.update(imported.id,muted:true,pauseWhenInactive:false)
            let (game,files,checkpoint)=try await repository.prepare(imported.id)
            let control=output.appendingPathComponent("control.jsonl")
            try Data().write(to:control)
            let hiddenWindow = args.count == 8 && args[7] == "--hidden-window"
            // Frame diagnostics select an EGL pbuffer. Omit them for the
            // separate, unordered CAMetalLayer acceptance path.
            try session.start(executable:app.appendingPathComponent("Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner"),
                game:game,apk:files[0],checkpoint:checkpoint,logs:paths.logs,headless:true,automation:true,
                diagnostics:hiddenWindow ? nil : output,hiddenWindow:hiddenWindow)
            try await session.wait(until:{session.state == "running" || !session.active},timeout:90)
            guard session.state == "running" else {throw LibraryFailure(session.error ?? "No running state")}
            checks.append("gameactivity-first-frame")
            try JSONSerialization.data(withJSONObject:["pid":session.pid,"session":session.sessionID ?? "", "game":game.id,
                "checkpoint":checkpoint.path,"logs":paths.logs.path],options:[.sortedKeys,.prettyPrinted]).write(to:output.appendingPathComponent("session.json"))
            var consumed=0
            let deadline=Date().addingTimeInterval(seconds)
            while session.active && Date() < deadline {
                let data=try Data(contentsOf:control)
                if data.count>consumed {
                    let bytes=data.dropFirst(consumed)
                    if let last=bytes.lastIndex(of:10) {
                        for line in bytes[...last].split(separator:10) {
                            if let object=try JSONSerialization.jsonObject(with:Data(line)) as? [String:Any], let command=object["command"] as? String {
                                if command == "stop" { session.stop() }
                                else {session.send(command,values:object)}
                            }
                        }
                        consumed=last+1
                    }
                }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            if session.active {session.stop();try await session.wait(until:{!session.active},timeout:35)}
            guard session.state == "exited" else {throw LibraryFailure(session.error ?? "Session did not exit cleanly")}
            checks.append("destroy-ack-and-process-reaped")
            guard kill(session.pid,0) == -1 && errno == ESRCH else {throw LibraryFailure("Runner survived its terminal state")}
            checks.append("pid-gone")
        } catch {
            failure=error.localizedDescription
            if session.active {session.stop();try? await session.wait(until:{!session.active},timeout:35)}
        }
        let result: [String:Any]=["checks":checks,"state":session.state,"error":failure ?? session.error as Any? ?? NSNull(),
            "pid":session.pid,"session":session.sessionID ?? "","events":session.events]
        if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {
            try? data.write(to:output.appendingPathComponent("result.json"))
        }
        print("Minecraft session: \(session.state), checks=\(checks.count), error=\(failure ?? session.error ?? "none")")
        exit(failure == nil && session.error == nil ? 0:1)
    }
}
