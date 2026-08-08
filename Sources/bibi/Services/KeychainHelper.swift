import Foundation
import Security

/**
 * 密钥存储服务。
 *
 * 使用系统 Keychain 安全存储 DeepSeek API Key 和 PC 配对 Token。
 *
 * @author xiangwei
 */
final class KeychainHelper {
    nonisolated(unsafe) static let shared = KeychainHelper()
    private let service = "com.lieyang.starnexus"
    private let accessibilityMigratedKey = "keychain_accessibility_migrated"

    func readAPIKey() -> String? { read(key: "deepseek_api_key") }
    func saveAPIKey(_ v: String) { save(key: "deepseek_api_key", value: v) }
    func readPairingToken() -> String? { read(key: "pc_pairing_token") }
    func savePairingToken(_ v: String) { save(key: "pc_pairing_token", value: v) }

    /**
     * 迁移历史 Keychain 项的可访问性级别。
     *
     * 旧版本保存时未指定 kSecAttrAccessible，默认在设备锁定时不可读，
     * 导致后台主动消息等场景读取不到 API Key。启动时重新写入一次，
     * 将已有数据迁移为 AfterFirstUnlockThisDeviceOnly。
     *
     * @author xiangwei
     */
    func migrateAccessibilityIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: accessibilityMigratedKey) else { return }

        // 若设备仍锁定导致无法读取，则暂不置位，下次启动再次尝试迁移
        let apiKeyMigrated = migrateItemIfPossible(key: "deepseek_api_key", save: saveAPIKey)
        let tokenMigrated = migrateItemIfPossible(key: "pc_pairing_token", save: savePairingToken)
        if apiKeyMigrated && tokenMigrated {
            UserDefaults.standard.set(true, forKey: accessibilityMigratedKey)
        }
    }

    /**
     * 尝试迁移单个 Keychain 项的可访问性。
     *
     * @param key 项标识
     * @param save 保存闭包
     * @return 是否已成功处理（迁移成功或原本就不存在）
     * @author xiangwei
     */
    private func migrateItemIfPossible(key: String, save: (String) -> Void) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            save(value)
            return true
        }
        if status == errSecItemNotFound {
            return true
        }
        return false
    }

    private func save(key: String, value: String) {
        let d = Data(value.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
        var a = q
        a[kSecValueData as String] = d
        // 允许在设备首次解锁后、即使锁屏状态下也能读取，供后台任务使用
        a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(a as CFDictionary, nil)
    }

    private func read(key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        SecItemCopyMatching(q as CFDictionary, &item)
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
