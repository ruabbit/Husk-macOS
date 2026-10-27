// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// An application preference. Never changes the system language or a running guest.
public enum AppLanguage {
    public static let key = "husk.guest.language"
    public static let supported = ["system", "en", "zh-Hans"]
    public static func selected(_ defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: key) ?? "system"
        return supported.contains(value) ? value : "system"
    }
    public static func set(_ value: String, defaults: UserDefaults = .standard) {
        guard supported.contains(value) else { return }
        defaults.set(value, forKey: key)
        if value == "system" { defaults.removeObject(forKey: "AppleLanguages") }
        else { defaults.set([value], forKey: "AppleLanguages") }
    }
    public static func runnerEnvironment(_ defaults: UserDefaults = .standard) -> [String: String] {
        let language = selected(defaults)
        return language == "system" ? [:] : ["HUSK_APP_LANGUAGE": language]
    }
    public static func applyRunnerEnvironment() {
        guard let language = ProcessInfo.processInfo.environment["HUSK_APP_LANGUAGE"],
              supported.contains(language), language != "system" else { return }
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleLanguages"] = [language]
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}
