import Foundation

@MainActor
@Observable
final class UserManager {
    private(set) var localUsers: [LocalUser] = []
    private(set) var currentLocalUser: LocalUser?
    private(set) var remoteUsers: [RemoteUser] = []
    private(set) var loading = false; private(set) var error: String?
    private let db = DatabaseManager.shared
    private let connection: ConnectionManager
    init(connection: ConnectionManager) { self.connection = connection; loadLocalUsers() }
    private func loadLocalUsers() {
        guard let records: [LocalUserRecord] = try? db.fetch("SELECT * FROM local_user ORDER BY created_at") else { return }
        localUsers = records.map { $0.toLocalUser() }
        if let lastId = UserDefaults.standard.string(forKey: "last_local_user_id"),
           let user = localUsers.first(where: { $0.id.uuidString == lastId }) { currentLocalUser = user }
    }
    func createLocalUser(name: String) async {
        let u = LocalUser(displayName: name)
        let r = LocalUserRecord.from(u)
        try? db.run("INSERT INTO local_user(id,display_name,avatar_color,created_at,last_active_at) VALUES(?,?,?,?,?)", args: [r.id, r.displayName, r.avatarColor, r.createdAt, r.lastActiveAt])
        localUsers.append(u); await switchUser(u)
    }
    func switchUser(_ user: LocalUser) async {
        currentLocalUser = user; user.lastActiveAt = Date()
        try? db.run("UPDATE local_user SET last_active_at = ? WHERE id = ?", args: [user.lastActiveAt, user.id.uuidString])
        UserDefaults.standard.set(user.id.uuidString, forKey: "last_local_user_id")
    }
    func bindToRemoteUser(_ r: RemoteUser) {
        currentLocalUser?.pcUserId = r.id
        if let id = currentLocalUser?.id.uuidString { try? db.run("UPDATE local_user SET pc_user_id = ? WHERE id = ?", args: [r.id, id]) }
    }
    func loadUsers(from pc: PCDevice) async {
        loading = true; defer { loading = false }
        do {
            let req = try connection.authenticatedRequest(path: "api/v1/users")
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(UsersResponse.self, from: data)
            if resp.success { remoteUsers = resp.data ?? [] }
        } catch { self.error = error.localizedDescription }
    }
}
