// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

@main struct NativeLaunchTests {
    static func main() {
        // Compiled Android XML, including a splash activity and launcher alias.
        func manifest(_ orientation: UInt32, alias: Bool) -> Data {
            let strings = ["manifest", "package", "org.husk.test", "activity", "name", ".Splash", ".Game",
                           "screenOrientation", "category", "android.intent.category.LAUNCHER", "activity-alias", "targetActivity", "org.husk.test.Game"]
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
            var elements = element(0, attr(1, 2))
            elements += element(3, attr(4, 5) + attr(7, 1, integer: true))
            elements += element(3, attr(4, 6) + attr(7, orientation, integer: true))
            if alias { elements += element(10, attr(11, 12)) }
            elements += element(8, attr(4, 9))
            let body = pool + elements
            return u16(3) + u16(8) + u32(UInt32(body.count + 8)) + body
        }
        for orientation: UInt32 in [0, 1, 6, 7, 8, 9, 11, 12] {
            for alias in [false, true] {
                let args = NativeLaunch.unityArguments(manifest: manifest(orientation, alias: alias), package: nil)
                guard args.prefix(2) == ["--package", "org.husk.test"],
                      args.contains("--portrait") == [1, 7, 9, 12].contains(orientation) else {
                    print("FAIL launcher orientation \(orientation), alias=\(alias)"); exit(1)
                }
            }
        }
        guard NativeLaunch.unityArguments(manifest: Data(), package: "org.husk.old") == ["--package", "org.husk.old"] else { exit(1) }
        print("PASS launcher orientation, alias resolution, splash exclusion and old-import fallback")
    }
}
