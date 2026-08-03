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
    /// 用户切换回调（传入新用户的 ID）。
    @MainActor var onUserSwitched: ((UUID) async -> Void)?

    init(connection: ConnectionManager) { self.connection = connection; loadLocalUsers() }
    private func loadLocalUsers() {
        do {
            let records: [LocalUserRecord] = try db.fetch("SELECT * FROM local_user ORDER BY created_at")
            localUsers = records.map { $0.toLocalUser() }
            if let lastId = UserDefaults.standard.string(forKey: "last_local_user_id"),
               let user = localUsers.first(where: { $0.id.uuidString == lastId }) {
                currentLocalUser = user
            }
        } catch {
            self.error = error.localizedDescription
            logDatabaseError(operation: "加载本地用户", error: error)
        }
    }
    func createLocalUser(name: String) async {
        let u = LocalUser(displayName: name)
        let r = LocalUserRecord.from(u)
        do {
            try db.run(
                "INSERT INTO local_user(id,display_name,avatar_color,created_at,last_active_at) VALUES(?,?,?,?,?)",
                args: [r.id, r.displayName, r.avatarColor, r.createdAt, r.lastActiveAt]
            )
        } catch {
            self.error = error.localizedDescription
            logDatabaseError(operation: "创建本地用户", error: error)
            return
        }
        localUsers.append(u); await switchUser(u)
    }
    func switchUser(_ user: LocalUser) async {
        currentLocalUser = user; user.lastActiveAt = Date()
        do {
            try db.run(
                "UPDATE local_user SET last_active_at = ? WHERE id = ?",
                args: [user.lastActiveAt, user.id.uuidString]
            )
        } catch {
            self.error = error.localizedDescription
            logDatabaseError(operation: "切换本地用户", error: error)
        }
        UserDefaults.standard.set(user.id.uuidString, forKey: "last_local_user_id")

        await onUserSwitched?(user.id)
    }

    /**
     * 删除本地用户并在需要时切换到剩余用户。
     *
     * @param user 待删除的本地用户
     * @throws 本地数据删除异常
     * @author xiangwei
     */
    func deleteLocalUser(_ user: LocalUser) async throws {
        let deletesCurrentUser = currentLocalUser?.id == user.id
        try db.deleteLocalUserData(id: user.id.uuidString)
        localUsers.removeAll { $0.id == user.id }

        guard deletesCurrentUser else { return }

        if let fallbackUser = localUsers.first {
            await switchUser(fallbackUser)
        } else {
            currentLocalUser = nil
            UserDefaults.standard.removeObject(forKey: "last_local_user_id")
        }
    }

    func bindToRemoteUser(_ r: RemoteUser) {
        currentLocalUser?.pcUserId = r.id
        guard let id = currentLocalUser?.id.uuidString else { return }
        do {
            try db.run("UPDATE local_user SET pc_user_id = ? WHERE id = ?", args: [r.id, id])
        } catch {
            self.error = error.localizedDescription
            logDatabaseError(operation: "关联电脑用户", error: error)
        }
    }
    func loadUsers(from pc: PCDevice) async {
        loading = true; defer { loading = false }
        do {
            let req = try connection.authenticatedRequest(path: "api/v1/users")
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(UsersResponse.self, from: data)
            if resp.success { remoteUsers = resp.data ?? [] }
        } catch {
            self.error = error.localizedDescription
            let errorMessage = error.localizedDescription
            Task {
                await AppLogger.shared.log(
                    .error,
                    category: "user",
                    message: "加载电脑用户失败: \(errorMessage)"
                )
            }
        }
    }

    /**
     * 记录用户数据读写异常。
     *
     * @param operation 数据操作名称
     * @param error 原始异常
     * @author xiangwei
     */
    private func logDatabaseError(operation: String, error: Error) {
        let errorMessage = error.localizedDescription
        Task {
            await AppLogger.shared.log(
                .error,
                category: "database",
                message: "\(operation)失败: \(errorMessage)"
            )
        }
    }
}
