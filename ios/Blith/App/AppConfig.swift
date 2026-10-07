import BlithCore
import Foundation
import Security

/// Build-time configuration from Info.plist (populated by xcconfig / CI), plus an optional
/// user-supplied key in the Keychain (debug builds only).
enum AppConfig {
    static func plist(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty || v.hasPrefix("$(") ? nil : v
    }

    static var openRouterKey: String? { Keychain.read("openrouter.apiKey") ?? plist("OPENROUTER_API_KEY") }
    static var model: String { plist("OPENROUTER_MODEL") ?? OpenRouterClient.defaultModel }
    /// The fast model behind "Quick". The default ("Deep") stays `model`.
    static var quickModel: String { plist("OPENROUTER_MODEL_QUICK") ?? "anthropic/claude-haiku-4.5" }
    static var aiConfigured: Bool { openRouterKey != nil }
    static var privacyPolicyURL: URL {
        URL(string: plist("PRIVACY_POLICY_URL") ?? "https://github.com/pixelbuyte/blith-health/blob/main/docs/PRIVACY.md")!
    }

    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// The app's notion of "now". Always the real time, except when CI screenshots of sample data
/// pin the demo to a fixed time of day (`-BlithClockHour 15.5`).
enum AppClock {
    nonisolated(unsafe) static var offset: TimeInterval = 0
    static func now() -> Date { Date().addingTimeInterval(offset) }
}

enum Keychain {
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.blith.health",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        let s = String(decoding: data, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    static func write(_ value: String?, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.blith.health",
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
