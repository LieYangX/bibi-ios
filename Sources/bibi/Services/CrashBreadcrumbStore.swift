import Foundation

/**
 * 进程异常中断面包屑。
 *
 * 关键操作开始前同步保存最后执行阶段；正常结束时删除。若进程意外退出，
 * 下次启动可恢复这条记录并写入应用错误日志。
 *
 * @author xiangwei
 */
struct CrashBreadcrumb: Codable, Sendable {
    /// 调用链标识。
    let traceId: String

    /// 操作分类。
    let operation: String

    /// 最后执行阶段。
    let stage: String

    /// 工具名称。
    let toolName: String?

    /// 更新时间。
    let updatedAt: Date
}

/**
 * 异常中断面包屑存储器。
 *
 * @author xiangwei
 */
enum CrashBreadcrumbStore {
    /// 面包屑文件名。
    private static let fileName = "pending-operation.json"

    /**
     * 保存当前关键操作阶段。
     *
     * @param traceId 调用链标识
     * @param operation 操作分类
     * @param stage 执行阶段
     * @param toolName 工具名称
     * @author xiangwei
     */
    static func mark(
        traceId: String,
        operation: String,
        stage: String,
        toolName: String? = nil
    ) {
        let breadcrumb = CrashBreadcrumb(
            traceId: traceId,
            operation: operation,
            stage: stage,
            toolName: toolName,
            updatedAt: Date()
        )

        do {
            let url = try breadcrumbURL()
            let data = try JSONEncoder().encode(breadcrumb)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Bibi 异常面包屑写入失败: %@", error.localizedDescription)
        }
    }

    /**
     * 清除指定调用链的面包屑。
     *
     * @param traceId 调用链标识
     * @author xiangwei
     */
    static func clear(traceId: String) {
        guard let breadcrumb = read(), breadcrumb.traceId == traceId else { return }
        removeFile()
    }

    /**
     * 读取并消费上次未完成的操作。
     *
     * @returns 上次未完成的操作记录
     * @author xiangwei
     */
    static func consumePending() -> CrashBreadcrumb? {
        guard let breadcrumb = read() else { return nil }
        removeFile()
        return breadcrumb
    }

    /**
     * 读取当前面包屑。
     *
     * @returns 当前面包屑
     * @author xiangwei
     */
    private static func read() -> CrashBreadcrumb? {
        guard let url = try? breadcrumbURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(CrashBreadcrumb.self, from: data)
    }

    /**
     * 删除面包屑文件。
     *
     * @author xiangwei
     */
    private static func removeFile() {
        guard let url = try? breadcrumbURL(), FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    /**
     * 获取面包屑文件地址并确保目录存在。
     *
     * @returns 面包屑文件地址
     * @throws 目录创建异常
     * @author xiangwei
     */
    private static func breadcrumbURL() throws -> URL {
        let fileManager = FileManager.default
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = supportURL.appending(path: "Bibi/Diagnostics", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appending(path: fileName)
    }
}
