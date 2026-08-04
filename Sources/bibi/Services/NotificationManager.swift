import Foundation
import UserNotifications

/**
 * 通知管理器。
 *
 * 负责通知授权申请与本地通知调度。AI 主动消息在后台生成后，
 * 通过本地通知提示用户查看。
 *
 * @author xiangwei
 */
@MainActor
@Observable
final class NotificationManager {
    /// 单例（@MainActor 隔离的 static let 自带隔离）。
    static let shared = NotificationManager()

    /// 是否已获得通知授权。
    private(set) var isAuthorized = false

    /// 最近一次授权错误描述。
    private(set) var authorizationError: String?

    private init() {}

    /**
     * 申请通知授权。
     *
     * @returns 是否获得授权
     * @author xiangwei
     */
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return isAuthorized
        } catch {
            authorizationError = error.localizedDescription
            isAuthorized = false
            return false
        }
    }

    /**
     * 发送一条立即展示的本地通知。
     *
     * 发送前实时查询授权状态，而非依赖内存缓存：
     * - 已授权：直接发送
     * - 尚未决定：先请求授权（会弹系统弹窗）
     * - 被拒绝：静默返回
     * 该策略保证后台 BGTask 唤醒等"视图 task 未执行"的场景也能正常发通知。
     *
     * @param title 通知标题
     * @param body 通知正文
     * @param userInfo 附带数据（如会话 ID）
     * @author xiangwei
     */
    func sendImmediateNotification(title: String, body: String, userInfo: [String: Any] = [:]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            // 从未询问过：请求授权后按结果决定
            guard await requestAuthorization() else { return }
        case .denied:
            // 用户已拒绝，无法展示通知
            return
        @unknown default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    /**
     * 清理已展示或待展示的通知。
     *
     * @param identifiers 通知标识列表，为空时清理全部
     * @author xiangwei
     */
    func clearNotifications(identifiers: [String] = []) async {
        let center = UNUserNotificationCenter.current()
        if identifiers.isEmpty {
            center.removeAllDeliveredNotifications()
            center.removeAllPendingNotificationRequests()
        } else {
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
}
