import BlithCore
import Foundation
import Security

/// Hands the latest `WidgetSnapshot` from the app to the widget extension.
///
/// Uses a shared Keychain access group (`<TeamID>.com.blith.health.shared`) instead of an App
/// Group: Keychain groups under the team prefix need no Developer-portal registration, so
/// signing stays fully automatic. The item is readable after first unlock, so widgets refresh
/// while the phone is locked.
enum WidgetStore {
    static let service = "com.blith.health.widget"
    static let account = "snapshot"
    static let groupSuffix = "com.blith.health.shared"
    static let widgetKind = "BlithReadiness"
    static let movementKind = "BlithMovement"

    /// App side: write with the shared group spelled out (the app's default group is its own).
    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        var query = baseQuery
        if let group = sharedGroup { query[kSecAttrAccessGroup as String] = group }
        let update: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(update) { _, new in new } as CFDictionary, nil)
        }
    }

    /// Widget side: the extension's only (and so default) group is the shared one.
    static func load() -> WidgetSnapshot? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    static func clear() {
        var query = baseQuery
        if let group = sharedGroup { query[kSecAttrAccessGroup as String] = group }
        SecItemDelete(query as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// `<TeamID>.com.blith.health.shared`, with the team ID read from the access group the
    /// Keychain assigns to a probe item. Nil on unsigned simulator builds.
    private static var sharedGroup: String? {
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.blith.health.probe",
                                    kSecAttrAccount as String: "team",
                                    kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(probe as CFDictionary, &result)
        if status == errSecItemNotFound {
            var add = probe
            add[kSecValueData as String] = Data()
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, &result)
        }
        guard status == errSecSuccess, let attrs = result as? [String: Any],
              let group = attrs[kSecAttrAccessGroup as String] as? String,
              let team = group.split(separator: ".").first, team.count == 10 else { return nil }
        return "\(team).\(groupSuffix)"
    }
}
