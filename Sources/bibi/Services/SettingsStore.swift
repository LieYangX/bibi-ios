import Foundation

@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard
    func get(_ key: SettingKey) -> String? { defaults.string(forKey: key.rawValue) }
    func set(_ key: SettingKey, value: String) { defaults.set(value, forKey: key.rawValue) }
}
