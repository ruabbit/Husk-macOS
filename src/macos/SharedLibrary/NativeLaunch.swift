// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import HuskCore

/// Launch metadata is read again for old imports which predate packageName.
/// The fixed guest canvas follows the launcher Activity, never the window size.
enum NativeLaunch {
    static func unityArguments(apk: URL, package: String?) -> [String] {
        var count = 0
        guard let bytes = husk_tl_read_entry(apk.path, "AndroidManifest.xml", 4 << 20, &count) else {
            return ["--package", package ?? "com.unity.game"]
        }
        defer { husk_tl_free(bytes) }
        return unityArguments(manifest: Data(bytes: bytes, count: count), package: package)
    }

    static func unityArguments(manifest: Data, package: String?) -> [String] {
        let packageName = ApkMetadata.packageName(manifest) ?? package ?? "com.unity.game"
        var arguments = ["--package", packageName]
        func qualified(_ name: String?) -> String? {
            guard let name else { return nil }
            if name.hasPrefix(".") { return packageName + name }
            return name.contains(".") ? name : packageName + "." + name
        }
        let elements = ApkMetadata.elements(manifest)
        var activity: ApkMetadata.Element?
        var launcher: ApkMetadata.Element?
        for element in elements {
            if element.name == "activity" || element.name == "activity-alias" { activity = element }
            if element.name == "category", element.attributes.contains(where: {
                $0.name == "name" && $0.value == "android.intent.category.LAUNCHER"
            }) { launcher = activity; break }
        }
        if launcher?.name == "activity-alias",
           let target = launcher?.attributes.first(where: { $0.name == "targetActivity" })?.value {
            launcher = elements.first { $0.name == "activity" && $0.attributes.contains { $0.name == "name" && qualified($0.value) == qualified(target) } }
        }
        if let orientation = launcher?.attributes.first(where: { $0.name == "screenOrientation" }),
           (orientation.dataType == 0x10 || orientation.dataType == 0x11),
           [1, 7, 9, 12].contains(orientation.data) { arguments.append("--portrait") }
        return arguments
    }
}
