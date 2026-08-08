import Foundation
import SwiftUI
import UIKit

// 系统框架的 BGTaskScheduler 回调闭包跨隔离域捕获任务对象，
// 使用 @preconcurrency 降低框架边界处的并发告警。
@preconcurrency import BackgroundTasks

/**
 * 主动消息服务。
 *
 * 负责调度 AI 主动发消息：
 * - 前台：定时器按配置间隔触发；若用户正在使用 app（applicationState == .active），
 *   则跳过本次并顺延到下一周期，避免打扰正在交互的用户。
 * - 后台：通过 BGTaskScheduler 注册后台刷新任务，系统唤醒后生成主动消息并发送本地通知。
 *
 * @author xiangwei
 */
@MainActor
@Observable
final class ProactiveMessageService {
    /// 单例（@MainActor 隔离的 static let 自带隔离）。
    static let shared = ProactiveMessageService()

    /// 主动消息触发原因文案。
    private static let triggerReason = "定时主动联系"

    /// 用户活跃（前台）时跳过发送后的重查间隔（秒）。
    private static let retryCheckInterval: TimeInterval = 60

    /// 后台刷新任务标识（与 Info.plist 中 BGTaskSchedulerPermittedIdentifiers 保持一致）。
    /// 用 nonisolated 常量，便于非隔离上下文中注册后台任务时引用。
    nonisolated static let taskIdentifier = "com.lieyang.starnexus.proactiveMessage"

    private var agent: AgentService?
    private var settings: SettingsStore?
    private let notifications = NotificationManager.shared

    /// 前台定时器。
    private var foregroundTimer: Timer?

    /// 是否正在生成主动消息（防止重入）。
    private var isGenerating = false

    /// 用户当前是否停留在聊天窗口（由 AgentChatView 上报）。
    private(set) var isChatVisible = false

    private init() {}

    /**
     * 注入依赖。
     *
     * @param agent 智能体服务
     * @param settings 设置存储
     * @author xiangwei
     */
    func configure(agent: AgentService, settings: SettingsStore) {
        self.agent = agent
        self.settings = settings
    }

    /**
     * 上报聊天窗口可见状态。
     *
     * @param visible 是否在聊天窗口
     * @author xiangwei
     */
    func setChatVisible(_ visible: Bool) {
        isChatVisible = visible
    }

    /**
     * 启动主动消息调度。
     *
     * 应在 app 启动完成依赖注入后调用。
     * @author xiangwei
     */
    func start() {
        scheduleForegroundTimer()
    }

    /**
     * 设置变更后重新调度。
     *
     * 设置页修改开关或触发间隔后调用，让调度立即生效。
     * @author xiangwei
     */
    func settingsDidChange() {
        if UIApplication.shared.applicationState == .background {
            scheduleBackgroundTask()
        } else {
            scheduleForegroundTimer()
        }
    }

    /**
     * 处理场景生命周期切换。
     *
     * @param phase 当前场景阶段
     * @author xiangwei
     */
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // 回到前台：恢复定时器
            scheduleForegroundTimer()
        case .background:
            // 进入后台：停止定时器，改由系统后台任务接管
            foregroundTimer?.invalidate()
            foregroundTimer = nil
            scheduleBackgroundTask()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    /**
     * 注册后台刷新任务。
     *
     * 必须在 app 启动早期（AppDelegate didFinishLaunching）调用一次。
     * @author xiangwei
     */
    nonisolated static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // 系统即将终止任务前的清理
            refreshTask.expirationHandler = {
                refreshTask.setTaskCompleted(success: false)
            }
            Task { @MainActor in
                await Self.shared.handleBackgroundRefresh(refreshTask)
            }
        }
    }

    /**
     * 手动触发一次主动消息（供调试或设置页按钮使用）。
     *
     * 强制发送，不受"用户正在使用"与启用开关限制，便于验证链路。
     * @author xiangwei
     */
    func triggerNow() async {
        await performProactiveSend(force: true)
    }

    // MARK: - 私有方法

    /**
     * 处理后台刷新任务。
     *
     * 生成主动消息后重新调度下一次后台任务。
     *
     * @param task 后台刷新任务
     * @author xiangwei
     */
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        defer { task.setTaskCompleted(success: true) }
        await performProactiveSend()
        scheduleBackgroundTask()
    }

    /**
     * 执行主动消息发送。
     *
     * - 自动触发（force == false）：用户正停留在聊天窗口时跳过本次并返回 true，
     *   由调用方按短间隔重查（消息会直接显示在对话里，无需通知打扰）；
     *   只要不在聊天窗口——无论前台其他页面还是后台——都生成消息并弹系统通知。
     * - 手动触发（force == true）：直接生成，不受窗口状态与开关限制。
     *
     * @param force 是否强制发送（手动测试用）
     * @returns 是否因停留在聊天窗口而跳过本次发送
     * @author xiangwei
     */
    @discardableResult
    private func performProactiveSend(force: Bool = false) async -> Bool {
        guard !isGenerating else { return false }
        guard force || settings?.proactiveEnabled == true else { return false }
        guard let agent, let settings else { return false }

        // 用户正停留在聊天窗口时不主动打扰：返回跳过标记，由调用方短间隔重查
        if !force, isChatVisible, UIApplication.shared.applicationState == .active {
            return true
        }

        isGenerating = true
        defer { isGenerating = false }

        settings.lastProactiveAt = Date()
        let generatedText = await agent.sendProactiveMessage(reason: Self.triggerReason)

        // 只要不在聊天窗口（其他页面或后台）就弹系统通知，正文显示生成内容
        if !(isChatVisible && UIApplication.shared.applicationState == .active) {
            let body = generatedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "星枢给你发了一条新消息"
            await notifications.sendImmediateNotification(
                title: "星枢",
                body: body,
                userInfo: ["source": "proactive"]
            )
        }
        return false
    }

    /**
     * 调度前台定时器。
     *
     * 根据上次触发时间计算剩余等待时长，到点后触发一次。
     *
     * @param shortCheck 是否使用短重查间隔（用户活跃跳过时）
     * @author xiangwei
     */
    private func scheduleForegroundTimer(shortCheck: Bool = false) {
        foregroundTimer?.invalidate()
        guard settings?.proactiveEnabled == true else {
            foregroundTimer = nil
            return
        }

        let remaining = shortCheck ? Self.retryCheckInterval : remainingInterval()
        foregroundTimer = Timer.scheduledTimer(
            withTimeInterval: remaining,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.foregroundTimerFired()
            }
        }
    }

    /**
     * 前台定时器到点回调。
     *
     * 若因用户活跃跳过，按短间隔重查；否则按正常间隔等待下一周期。
     * @author xiangwei
     */
    private func foregroundTimerFired() async {
        let skipped = await performProactiveSend()
        scheduleForegroundTimer(shortCheck: skipped)
    }

    /**
     * 调度后台刷新任务。
     *
     * 注册下一次系统唤醒的最早时间。
     * @author xiangwei
     */
    private func scheduleBackgroundTask() {
        guard settings?.proactiveEnabled == true else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: remainingInterval())
        try? BGTaskScheduler.shared.submit(request)
    }

    /**
     * 计算距下次触发还需等待的时长。
     *
     * @returns 剩余秒数（不小于 10 秒）
     * @author xiangwei
     */
    private func remainingInterval() -> TimeInterval {
        let interval = Double(settings?.proactiveIntervalMinutes ?? 120) * 60
        guard let lastTrigger = settings?.lastProactiveAt else { return interval }
        let elapsed = Date().timeIntervalSince(lastTrigger)
        return max(10, interval - elapsed)
    }
}
