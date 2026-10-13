// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import HuskCore

/// Launch metadata is read again for old imports which predate packageName.
/// The fixed guest canvas follows the launcher Activity, never the window size.
enum NativeLaunch {
    static func arguments(apk: URL, package: String?, nativeActivity: Bool = false) -> [String] {
        var count = 0
        guard let bytes = husk_tl_read_entry(apk.path, "AndroidManifest.xml", 4 << 20, &count) else {
            return ["--package", package ?? (nativeActivity ? "org.husk.game" : "com.unity.game")]
        }
        defer { husk_tl_free(bytes) }
        return arguments(manifest: Data(bytes: bytes, count: count), package: package, nativeActivity: nativeActivity)
    }

    static func arguments(manifest: Data, package: String?, nativeActivity: Bool = false) -> [String] {
        let packageName = ApkMetadata.packageName(manifest) ?? package ?? (nativeActivity ? "org.husk.game" : "com.unity.game")
        var arguments = ["--package", packageName]
        func qualified(_ name: String?) -> String? {
            guard let name else { return nil }
            if name.hasPrefix(".") { return packageName + name }
            return name.contains(".") ? name : packageName + "." + name
        }
        let elements = ApkMetadata.elements(manifest)
        var activityIndex: Int?
        var launcherIndex: Int?
        for (index, element) in elements.enumerated() {
            if let current = activityIndex, element.depth <= elements[current].depth { activityIndex = nil }
            if element.name == "activity" || element.name == "activity-alias" { activityIndex = index }
            if element.name == "category", element.attributes.contains(where: {
                $0.name == "name" && $0.value == "android.intent.category.LAUNCHER"
            }) { launcherIndex = activityIndex; break }
        }
        if let index = launcherIndex, elements[index].name == "activity-alias",
           let target = elements[index].attributes.first(where: { $0.name == "targetActivity" })?.value {
            launcherIndex = elements.firstIndex { $0.name == "activity" && $0.attributes.contains { $0.name == "name" && qualified($0.value) == qualified(target) } }
        }
        let launcher = launcherIndex.map { elements[$0] }
        if let name = qualified(launcher?.attributes.first(where: { $0.name == "name" })?.value) {
            arguments += ["--activity", name.replacingOccurrences(of: ".", with: "/")]
        }
        if let orientation = launcher?.attributes.first(where: { $0.name == "screenOrientation" }),
           (orientation.dataType == 0x10 || orientation.dataType == 0x11),
           [1, 7, 9, 12].contains(orientation.data) { arguments.append("--portrait") }
        // Only metadata under the chosen Activity belongs to its native entry.
        let activityElements = launcherIndex.map { index in
            elements.dropFirst(index + 1).prefix { $0.depth > elements[index].depth }
                .filter { $0.depth == elements[index].depth + 1 }
        }
        if nativeActivity,
           let metadata = activityElements?.first(where: { $0.name == "meta-data" && $0.attributes.contains { $0.name == "name" && $0.value == "android.app.lib_name" } }),
           let value = metadata.attributes.first(where: { $0.name == "value" }), value.dataType == 3,
           let library = value.value,
           !library.isEmpty, library.utf8.count <= 56,
           library.range(of: "^[A-Za-z0-9_+.-]+$", options: .regularExpression) != nil {
            arguments += ["--native-library", library]
        }
        return arguments
    }
}
