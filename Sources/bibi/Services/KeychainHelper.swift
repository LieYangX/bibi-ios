import Foundation
import Security

final class KeychainHelper {
    nonisolated(unsafe) static let shared = KeychainHelper()
    private let service = "com.bibi.ios"
    func readAPIKey() -> String? { read(key: "deepseek_api_key") }
    func saveAPIKey(_ v: String) { save(key: "deepseek_api_key", value: v) }
    func readPairingToken() -> String? { read(key: "pc_pairing_token") }
    func savePairingToken(_ v: String) { save(key: "pc_pairing_token", value: v) }
    private func save(key: String, value: String) {
        let d = Data(value.utf8)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary); var a = q; a[kSecValueData as String] = d; SecItemAdd(a as CFDictionary, nil)
    }
    private func read(key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?; SecItemCopyMatching(q as CFDictionary, &item)
        guard let data = item as? Data else { return nil }; return String(data: data, encoding: .utf8)
    }
}
