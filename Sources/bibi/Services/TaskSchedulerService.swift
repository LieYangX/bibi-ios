import Foundation
import SwiftUI

/**
 * 任务调度服务。
 *
 * 管理待办事项与定时任务，并在应用运行期间按周期检查已到期的定时任务，
 * 通过 AgentService 主动通知智能体执行对应任务。
 *
 * 定时任务面向智能体而非用户：到期后不会直接弹出系统通知，而是让 AI
 * 收到触发原因，由 AI 决定下一步动作（例如查看待办、主动联系用户等）。
 *
 * @author xiangwei
 */
@MainActor
@Observable
final class TaskSchedulerService {
    /// 单例（@MainActor 隔离的 static let 自带隔离）。
    static let shared = TaskSchedulerService()

    /// 前台检查周期（秒）。
    private static let checkInterval: TimeInterval = 60

    /// 最大同时触发的到期任务数量，防止一次性过多调用。
    private static let maxOverdueTasksPerCheck = 5

    private var agent: AgentService?
    private var currentConversationId: UUID?
    private var checkTimer: Timer?
    private var isChecking = false

    /// 当前会话的待办事项列表。
    private(set) var todos: [TodoItem] = []

    /// 当前会话的定时任务列表。
    private(set) var scheduledTasks: [ScheduledTask] = []

    private init() {}

    /**
     * 注入智能体服务依赖。
     *
     * @param agent 智能体服务
     * @author xiangwei
     */
    func configure(agent: AgentService) {
        self.agent = agent
    }

    /**
     * 加载指定会话的任务数据。
     *
     * 进入聊天页面或切换会话时调用，会启动前台定时检查器并立即检查一次到期任务。
     *
     * @param conversationId 对话标识
     * @author xiangwei
     */
    func load(for conversationId: UUID) {
        guard currentConversationId != conversationId else { return }
        currentConversationId = conversationId
        loadFromDatabase()
        startCheckTimer()
        Task {
            await checkOverdueTasks()
        }
    }

    /**
     * 卸载当前会话的任务数据。
     *
     * 切换会话或应用进入后台时调用，停止前台检查器。
     *
     * @author xiangwei
     */
    func unload() {
        currentConversationId = nil
        todos.removeAll()
        scheduledTasks.removeAll()
        stopCheckTimer()
    }

    /**
     * 处理场景生命周期切换。
     *
     * 回到前台时恢复检查；进入后台时暂停前台检查。
     *
     * @param phase 当前场景阶段
     * @author xiangwei
     */
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            guard currentConversationId != nil else { return }
            startCheckTimer()
            Task {
                await checkOverdueTasks()
            }
        case .background:
            stopCheckTimer()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: - 待办事项

    /**
     * 新增待办事项。
     *
     * @param title 待办标题
     * @returns 新创建的待办模型
     * @throws 未加载会话时抛出
     * @author xiangwei
     */
    func addTodo(title: String) throws -> TodoItem {
        guard let conversationId = currentConversationId else {
            throw TaskSchedulerError.notLoaded
        }

        let item = TodoItem(conversationId: conversationId, title: title)
        let record = TodoItemRecord.from(item)
        do {
            try DatabaseManager.shared.run(
                """
                INSERT INTO todo_item(id, conversation_id, title, is_completed, created_at, updated_at)
                VALUES(?,?,?,?,?,?)
                """,
                args: [record.id, record.conversationId, record.title, record.isCompleted, record.createdAt, record.updatedAt]
            )
        } catch {
            throw TaskSchedulerError.databaseError("创建待办失败: \(error.localizedDescription)")
        }
        todos.append(item)
        return item
    }

    /**
     * 列出当前会话的待办事项。
     *
     * @param includeCompleted 是否包含已完成项
     * @returns 待办列表
     * @author xiangwei
     */
    func listTodos(includeCompleted: Bool = false) -> [TodoItem] {
        if includeCompleted {
            return todos.sorted { $0.createdAt < $1.createdAt }
        }
        return todos.filter { !$0.isCompleted }.sorted { $0.createdAt < $1.createdAt }
    }

    /**
     * 标记待办事项为已完成。
     *
     * @param id 待办标识
     * @returns 是否成功
     * @author xiangwei
     */
    func completeTodo(id: UUID) -> Bool {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return false }
        let now = Date()
        todos[index].isCompleted = true
        todos[index].updatedAt = now
        do {
            try DatabaseManager.shared.run(
                "UPDATE todo_item SET is_completed = ?, updated_at = ? WHERE id = ?",
                args: [true, now, id.uuidString]
            )
        } catch {
            return false
        }
        return true
    }

    /**
     * 删除待办事项。
     *
     * @param id 待办标识
     * @returns 是否成功
     * @author xiangwei
     */
    func deleteTodo(id: UUID) -> Bool {
        guard todos.firstIndex(where: { $0.id == id }) != nil else { return false }
        do {
            try DatabaseManager.shared.run(
                "DELETE FROM todo_item WHERE id = ?",
                args: [id.uuidString]
            )
        } catch {
            return false
        }
        todos.removeAll { $0.id == id }
        return true
    }

    // MARK: - 定时任务

    /**
     * 新增定时任务。
     *
     * @param title 任务标题（提醒 AI 做什么）
     * @param scheduledAt 计划触发时间
     * @param isRecurring 是否重复触发
     * @param recurrenceRule 重复规则描述（如 daily、weekly、weekdays）
     * @returns 新创建的定时任务模型
     * @throws 未加载会话或参数无效时抛出
     * @author xiangwei
     */
    func addScheduledTask(
        title: String,
        scheduledAt: Date,
        isRecurring: Bool = false,
        recurrenceRule: String? = nil
    ) throws -> ScheduledTask {
        guard let conversationId = currentConversationId else {
            throw TaskSchedulerError.notLoaded
        }
        guard scheduledAt > Date() else {
            throw TaskSchedulerError.invalidTime("定时任务必须设置在将来")
        }

        let task = ScheduledTask(
            conversationId: conversationId,
            title: title,
            scheduledAt: scheduledAt,
            isRecurring: isRecurring,
            recurrenceRule: recurrenceRule
        )
        let record = ScheduledTaskRecord.from(task)
        do {
            try DatabaseManager.shared.run(
                """
                INSERT INTO scheduled_task(
                    id, conversation_id, title, scheduled_at, is_recurring, recurrence_rule,
                    is_enabled, created_at, updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?)
                """,
                args: [
                    record.id, record.conversationId, record.title, record.scheduledAt,
                    record.isRecurring, record.recurrenceRule ?? "",
                    record.isEnabled, record.createdAt, record.updatedAt
                ]
            )
        } catch {
            throw TaskSchedulerError.databaseError("创建定时任务失败: \(error.localizedDescription)")
        }
        scheduledTasks.append(task)
        return task
    }

    /**
     * 列出当前会话的定时任务。
     *
     * @param includeDisabled 是否包含已禁用任务
     * @returns 定时任务列表
     * @author xiangwei
     */
    func listScheduledTasks(includeDisabled: Bool = false) -> [ScheduledTask] {
        if includeDisabled {
            return scheduledTasks.sorted { $0.scheduledAt < $1.scheduledAt }
        }
        return scheduledTasks.filter { $0.isEnabled }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /**
     * 删除定时任务。
     *
     * @param id 任务标识
     * @returns 是否成功
     * @author xiangwei
     */
    func deleteScheduledTask(id: UUID) -> Bool {
        guard scheduledTasks.firstIndex(where: { $0.id == id }) != nil else { return false }
        do {
            try DatabaseManager.shared.run(
                "DELETE FROM scheduled_task WHERE id = ?",
                args: [id.uuidString]
            )
        } catch {
            return false
        }
        scheduledTasks.removeAll { $0.id == id }
        return true
    }

    /**
     * 检查并触发已到期的定时任务。
     *
     * 对每一个到期且启用的任务，构造触发原因并调用 AgentService 主动通知智能体。
     * 一次性任务触发后删除；重复任务计算下一次时间并更新。
     *
     * @author xiangwei
     */
    func checkOverdueTasks() async {
        guard !isChecking else { return }
        guard let agent, let conversationId = currentConversationId else { return }

        let now = Date()
        let dueTasks = scheduledTasks
            .filter { $0.isEnabled && $0.scheduledAt <= now }
            .prefix(Self.maxOverdueTasksPerCheck)
            .sorted { $0.scheduledAt < $1.scheduledAt }

        guard !dueTasks.isEmpty else { return }

        isChecking = true
        defer { isChecking = false }

        for task in dueTasks {
            let reason = buildTriggerReason(for: task)

            await AppLogger.shared.log(
                .info,
                category: "scheduler",
                message: "定时任务到期，通知智能体",
                metadata: [
                    "task_id": task.id.uuidString,
                    "task_title": task.title,
                    "conversation_id": conversationId.uuidString
                ]
            )

            _ = await agent.sendProactiveMessage(reason: reason)

            if task.isRecurring {
                updateRecurringTask(task, now: now)
            } else {
                _ = deleteScheduledTask(id: task.id)
            }
        }
    }

    // MARK: - 私有方法

    /**
     * 从数据库加载当前会话的任务数据。
     *
     * @author xiangwei
     */
    private func loadFromDatabase() {
        guard let conversationId = currentConversationId else { return }
        let conversationIdString = conversationId.uuidString

        do {
            let todoRecords: [TodoItemRecord] = try DatabaseManager.shared.fetch(
                "SELECT * FROM todo_item WHERE conversation_id = ? ORDER BY created_at",
                args: [conversationIdString]
            )
            todos = todoRecords.map { $0.toTodoItem() }
        } catch {
            todos = []
            logDatabaseError(operation: "加载待办事项", error: error)
        }

        do {
            let taskRecords: [ScheduledTaskRecord] = try DatabaseManager.shared.fetch(
                """
                SELECT * FROM scheduled_task
                WHERE conversation_id = ?
                ORDER BY scheduled_at
                """,
                args: [conversationIdString]
            )
            scheduledTasks = taskRecords.map { $0.toScheduledTask() }
        } catch {
            scheduledTasks = []
            logDatabaseError(operation: "加载定时任务", error: error)
        }
    }

    /**
     * 启动前台检查定时器。
     *
     * @author xiangwei
     */
    private func startCheckTimer() {
        stopCheckTimer()
        checkTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkOverdueTasks()
            }
        }
    }

    /**
     * 停止前台检查定时器。
     *
     * @author xiangwei
     */
    private func stopCheckTimer() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /**
     * 构造触发智能体的理由文本。
     *
     * 注入当前待办列表，让 AI 可以配合待办工具一起处理。
     *
     * @param task 到期的定时任务
     * @returns 给智能体的触发原因
     * @author xiangwei
     */
    private func buildTriggerReason(for task: ScheduledTask) -> String {
        let pendingTodos = listTodos(includeCompleted: false)
            .map { "- \($0.title)" }
            .joined(separator: "\n")
        let todoSection = pendingTodos.isEmpty ? "当前没有待办事项。" : "当前待办事项：\n\(pendingTodos)"

        return """
            【定时任务触发】
            你之前设置了一个定时任务，现在到了该执行的时间。
            任务内容：\(task.title)
            \(todoSection)

            请根据任务内容和当前待办，决定下一步该做什么。
            如果需要操办事项，请使用 manage_todo 工具。
            """
    }

    /**
     * 更新重复任务到下一次触发时间。
     *
     * @param task 重复任务
     * @param now 当前时间
     * @author xiangwei
     */
    private func updateRecurringTask(_ task: ScheduledTask, now: Date) {
        guard let nextDate = nextOccurrence(for: task, after: now) else { return }
        task.scheduledAt = nextDate
        task.updatedAt = now

        do {
            try DatabaseManager.shared.run(
                "UPDATE scheduled_task SET scheduled_at = ?, updated_at = ? WHERE id = ?",
                args: [nextDate, now, task.id.uuidString]
            )
        } catch {
            logDatabaseError(operation: "更新重复任务", error: error)
        }
    }

    /**
     * 根据重复规则计算下一次触发时间。
     *
     * @param task 重复任务
     * @param after 参考时间
     * @returns 下一次触发时间，无法计算时返回空
     * @author xiangwei
     */
    private func nextOccurrence(for task: ScheduledTask, after: Date) -> Date? {
        let calendar = Calendar.current
        let rule = task.recurrenceRule?.lowercased() ?? "daily"

        switch rule {
        case "daily":
            return calendar.date(byAdding: .day, value: 1, to: task.scheduledAt)
        case "weekly":
            return calendar.date(byAdding: .day, value: 7, to: task.scheduledAt)
        case "weekdays":
            var date = task.scheduledAt
            for _ in 0..<7 {
                guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
                date = next
                let weekday = calendar.component(.weekday, from: date)
                if weekday != 1 && weekday != 7 {
                    return date
                }
            }
            return nil
        default:
            return calendar.date(byAdding: .day, value: 1, to: task.scheduledAt)
        }
    }

    /**
     * 记录任务调度数据读写异常。
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
                category: "scheduler",
                message: "\(operation)失败: \(errorMessage)"
            )
        }
    }
}

/**
 * 任务调度服务异常。
 *
 * @author xiangwei
 */
enum TaskSchedulerError: LocalizedError {
    /// 服务未加载当前会话。
    case notLoaded

    /// 时间参数无效。
    case invalidTime(String)

    /// 数据库操作失败。
    case databaseError(String)

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "任务调度服务尚未加载当前会话"
        case .invalidTime(let detail):
            return "时间无效: \(detail)"
        case .databaseError(let detail):
            return detail
        }
    }
}
