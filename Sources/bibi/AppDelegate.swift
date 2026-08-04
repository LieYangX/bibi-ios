import UIKit
import UserNotifications

/**
 * 应用代理。
 *
 * 负责注册后台刷新任务与通知代理，在 app 启动早期完成系统级能力挂载。
 *
 * @author xiangwei
 */
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /**
     * app 启动完成回调。
     *
     * 注册后台刷新任务，避免 BGTaskScheduler 在启动后重复注册。
     *
     * @param application 应用实例
     * @param launchOptions 启动参数
     * @returns 是否继续启动
     * @author xiangwei
     */
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 注册后台刷新任务
        ProactiveMessageService.registerBackgroundTasks()
        // 设置通知中心代理（前台收到通知时也能展示横幅）
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /**
     * app 在前台时收到通知的处理。
     *
     * 允许前台直接展示通知横幅并保留在通知中心，
     * 而不是静默丢弃（.list 确保通知中心有记录，.banner 弹横幅，.sound 播放声音）。
     *
     * @param center 通知中心
     * @param notification 收到的通知
     * @param completionHandler 展示回调
     * @author xiangwei
     */
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
