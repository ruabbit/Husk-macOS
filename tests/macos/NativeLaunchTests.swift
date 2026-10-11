// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

@main struct NativeLaunchTests {
    static func main() {
        // Compiled Android XML, including a splash activity and launcher alias.
        func manifest(_ orientation: UInt32, alias: Bool, library: String? = "egginc") -> Data {
            let strings = ["manifest", "package", "org.husk.test", "activity", "name", ".Splash", ".Game",
                           "screenOrientation", "category", "android.intent.category.LAUNCHER", "activity-alias", "targetActivity", "org.husk.test.Game",
                           "meta-data", "android.app.lib_name", "value", library ?? "unused", "application", "intent-filter"]
            func u16(_ value: Int) -> Data { var v = UInt16(value).littleEndian; return withUnsafeBytes(of: &v) { Data($0) } }
            func u32(_ value: UInt32) -> Data { var v = value.littleEndian; return withUnsafeBytes(of: &v) { Data($0) } }
            var offsets = Data(), text = Data()
            for string in strings {
                offsets += u32(UInt32(text.count)); text += Data([UInt8(string.count), UInt8(string.utf8.count)])
                text += Data(string.utf8) + Data([0])
            }
            while text.count % 4 != 0 { text.append(0) }
            let start = 28 + offsets.count
            let pool = u16(1) + u16(28) + u32(UInt32(start + text.count)) + u32(UInt32(strings.count)) + u32(0) + u32(0x100) + u32(UInt32(start)) + u32(0) + offsets + text
            func attr(_ name: UInt32, _ value: UInt32, integer: Bool = false) -> Data {
                u32(.max) + u32(name) + u32(integer ? .max : value) + u16(8) + Data([0, integer ? 0x10 : 3]) + u32(value)
            }
            func element(_ name: UInt32, _ attrs: Data) -> Data {
                var data = u16(0x102) + u16(16) + u32(UInt32(36 + attrs.count))
                for word: UInt32 in [1, .max, .max, name] { data += u32(word) }
                for half in [20, 20, attrs.count / 20, 0, 0, 0] { data += u16(half) }
                data += attrs
                return data
            }
            func end(_ name: UInt32) -> Data {
                u16(0x103) + u16(16) + u32(24) + u32(1) + u32(.max) + u32(.max) + u32(name)
            }
            let launcher = element(18, Data()) + element(8, attr(4, 9)) + end(8) + end(18)
            var elements = element(0, attr(1, 2)) + element(17, Data())
            elements += element(3, attr(4, 5) + attr(7, 1, integer: true))
            // A different Activity's library must never win selection.
            elements += element(13, attr(4, 14) + attr(15, 5)) + end(13) + end(3)
            elements += element(3, attr(4, 6) + attr(7, orientation, integer: true))
            if library != nil { elements += element(13, attr(4, 14) + attr(15, 16)) + end(13) }
            if !alias { elements += launcher }
            elements += end(3)
            // Application metadata after the last Activity is not its entry.
            elements += element(13, attr(4, 14) + attr(15, 5)) + end(13)
            if alias { elements += element(10, attr(11, 12)) + launcher + end(10) }
            elements += end(17) + end(0)
            let body = pool + elements
            return u16(3) + u16(8) + u32(UInt32(body.count + 8)) + body
        }
        for orientation: UInt32 in [0, 1, 6, 7, 8, 9, 11, 12] {
            for alias in [false, true] {
                let args = NativeLaunch.arguments(manifest: manifest(orientation, alias: alias), package: nil)
                guard args.prefix(2) == ["--package", "org.husk.test"],
                      args.contains("--portrait") == [1, 7, 9, 12].contains(orientation) else {
                    print("FAIL launcher orientation \(orientation), alias=\(alias)"); exit(1)
                }
                let native = NativeLaunch.arguments(manifest: manifest(orientation, alias: alias), package: nil, nativeActivity: true)
                guard native == args + ["--native-library", "egginc"] else { exit(1) }
            }
        }
        for alias in [false, true] {
            for library: String? in [nil, "../wrong", "", String(repeating: "x", count: 57)] {
                let args = NativeLaunch.arguments(manifest: manifest(0, alias: alias, library: library), package: nil, nativeActivity: true)
                guard args == ["--package", "org.husk.test"] else {
                    print("FAIL invalid or non-Activity library escaped manifest scope"); exit(1)
                }
            }
        }
        guard NativeLaunch.arguments(manifest: Data(), package: "org.husk.old") == ["--package", "org.husk.old"] else { exit(1) }
        print("PASS launcher orientation, alias, native library scope/validation and old-import fallback")
    }
}
