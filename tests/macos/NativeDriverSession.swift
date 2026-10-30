// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SharedLibrary
@main struct NativeDriverSession {
    @MainActor static func main() async {
        let args=CommandLine.arguments
        guard args.count==5 || (args.count==6 && args[5]=="jitless") else { exit(64) }
        let jitless=args.count==6
        let app=URL(fileURLWithPath:args[1]), fixture=URL(fileURLWithPath:args[2]), engine=args[3]
        let paths=LibraryPaths(root:URL(fileURLWithPath:args[4]).appendingPathComponent("Native-\(UUID().uuidString)"))
        let session=SessionController()
        func check(_ value:Bool,_ why:String) throws { if !value { throw LibraryFailure(why) }; print("PASS \(why)") }
        do {
            let repository=try LibraryRepository(paths:paths,trustedFixtureHash:"")
            let imported=try await repository.importGame(fixture)
            let profile=engine=="geode" ? "cocos" : engine=="sdl-luajit" ? "sdl" : engine
            try check(imported.runtime==profile,"\(engine) import selects production profile")
            if engine=="geode" {
                let apk=paths.game(imported.id).appendingPathComponent(imported.apkNames[0])
                try FileManager.default.copyItem(at:fixture.deletingLastPathComponent().appendingPathComponent("geode"),to:Geode.directory(apk:apk))
                try await repository.update(imported.id,geode:true)
            }
            if jitless { try await repository.update(imported.id, jitless: true) }
            let (game,files,checkpoint)=try await repository.prepare(imported.id)
            try session.start(executable:app.appendingPathComponent("Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner"),
                game:game,apk:files[0],checkpoint:checkpoint,logs:paths.logs,headless:true,automation:true)
            try await session.wait(until:{session.state=="running" || !session.active},timeout:180)
            try check(session.state=="running",session.error ?? "first frame")
            if jitless {
                try check(game.settings.jitless, "per-game JIT-less setting persists")
                try check(session.events.contains{$0["event"] as? String=="aot-ready"}, "packaged Runner prepares signed AOT code")
                session.send("status")
                try await session.wait(until:{session.events.contains{$0["jitless"] as? Bool==true && $0["executableRegionBytes"] as? Int==0}},timeout:5)
            }
            if engine=="sdl" {
                session.send("keyboard")
                try await session.wait(until:{session.events.contains{$0["event"] as? String=="text-input" && $0["active"] as? Bool==true}},timeout:5)
                session.send("input",values:["source":"text","text":"A!?\n"])
                session.send("keyboard")
            }
            for phase in [0,2] { session.send("input",values:["source":"touch","phase":phase,"x":100,"y":100]) }
            for down in [true,false] { session.send("input",values:["source":"key","code":53,"down":down]) }
            try await Task.sleep(for:.milliseconds(100))
            session.togglePause();try await session.wait(until:{session.state=="paused" || !session.active},timeout:10)
            try check(session.state=="paused",session.error ?? "pause acknowledged")
            session.togglePause();try await session.wait(until:{session.state=="running" || !session.active},timeout:10)
            try check(session.state=="running",session.error ?? "resume acknowledged")
            session.send("input",values:["source":"touch","phase":0,"x":100,"y":100])
            try await Task.sleep(for:.milliseconds(100))
            session.stop();try await session.wait(until:{!session.active},timeout:35)
            try check(session.state=="exited" && session.error==nil,session.error ?? "normal close and reap")
            try check(session.events.filter{$0["event"] as? String=="storage-closed"}.count==1,"one storage receipt")
            let data=try Data(contentsOf:checkpoint.deletingLastPathComponent().appendingPathComponent("data/callbacks.bin"))
            try check(data.count==8,"native callback record persisted")
            let mask=data.withUnsafeBytes{$0.loadUnaligned(as:UInt32.self)}
            let wrong=data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:4,as:UInt32.self)}
            try check(mask&127==127 && wrong==0,"real input, pause and stop callbacks on owner thread")
            if engine=="sdl" { try check(mask&512 != 0,"manual SDL keyboard delivered Android key events to the ELF") }
            if engine=="unity" { try check(mask&768==768,"main Looper before JNI_OnLoad, three-argument init and plugin JNI_OnLoad exactly once") }
            if engine=="minecraft" { try check(mask&256 != 0,"V8 interpreter flag and main Looper precede GameActivity initialization") }
            if engine=="sdl-luajit" { try check(mask&256 != 0,"LuaJIT ABI switches to interpreter before SDL application code") }
            if profile != "cocos" { try check(mask&128 != 0,"native destruction acknowledged") }
            if engine=="geode" {
                let data=checkpoint.deletingLastPathComponent().appendingPathComponent("data")
                try check(try String(contentsOf:data.appendingPathComponent("files/game_version.txt"),encoding:.utf8)=="39","Geode receives game version")
                try check(try String(contentsOf:data.appendingPathComponent("geode/game/geode/resources/geode.loader/loader.txt"),encoding:.utf8)=="new!","Geode resources extracted in isolated save")
            }
        } catch {
            if session.active {session.stop();try? await session.wait(until:{!session.active},timeout:35)}
            print("FAIL \(error.localizedDescription); logs: \(paths.logs.path)");exit(1)
        }
    }
}
