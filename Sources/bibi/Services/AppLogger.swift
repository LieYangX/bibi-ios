import Foundation

/**
 * 应用结构化日志服务。
 *
 * 日志以 JSONL 格式保存在 Application Support 目录，并按大小滚动保留最近两份文件。
 *
 * @author xiangwei
 */
actor AppLogger {
    /// 全局日志服务。
    static let shared = AppLogger()

    /// 单个日志文件最大字节数。
    private static let maximumFileSize = 2 * 1_024 * 1_024

    /// 日志目录。
    private let logDirectoryURL: URL

    /// 当前日志文件。
    private let currentLogURL: URL

    /// 上一份日志文件。
    private let archivedLogURL: URL

    /// JSON 编码器。
    private let encoder: JSONEncoder

    /// JSON 解码器。
    private let decoder: JSONDecoder

    /**
     * 初始化日志服务。
     */
    private init() {
        let fileManager = FileManager.default
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        logDirectoryURL = supportURL.appending(path: "Bibi/Logs", directoryHint: .isDirectory)
        currentLogURL = logDirectoryURL.appending(path: "bibi.jsonl")
        archivedLogURL = logDirectoryURL.appending(path: "bibi-previous.jsonl")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /**
     * 记录一条结构化日志。
     *
     * @param level 日志等级
     * @param category 功能分类
     * @param message 日志内容
     * @param traceId 调用链标识
     * @param metadata 补充信息
     */
    func log(
        _ level: AppLogLevel,
        category: String,
        message: String,
        traceId: String? = nil,
        metadata: [String: String] = [:]
    ) {
        let entry = AppLogEntry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            category: sanitize(category, maximumLength: 64),
            message: sanitize(message, maximumLength: 2_000),
            traceId: traceId,
            metadata: metadata.mapValues { sanitize($0, maximumLength: 500) }
        )

        do {
            try prepareDirectory()
            try rotateIfNeeded()
            try append(entry)
        } catch {
            // 日志服务自身失败时不能递归记录，保留系统控制台作为最后兜底。
            NSLog("Bibi 日志写入失败: %@", error.localizedDescription)
        }
    }

    /**
     * 读取最近的日志记录。
     *
     * @param limit 最大返回数量
     * @returns 按时间倒序排列的日志记录
     */
    func loadEntries(limit: Int = 1_000) throws -> [AppLogEntry] {
        try prepareDirectory()
        let urls = [archivedLogURL, currentLogURL]
        let entries = try urls.flatMap { try readEntries(from: $0) }
        return Array(entries.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /**
     * 清空应用日志。
     *
     * @throws 文件删除异常
     */
    func clear() throws {
        for url in [currentLogURL, archivedLogURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /**
     * 生成可分享的日志文件。
     *
     * @returns 导出文件地址
     * @throws 日志读取或文件写入异常
     */
    func makeExportFile() throws -> URL {
        try prepareDirectory()
        let exportURL = FileManager.default.temporaryDirectory.appending(path: "bibi-logs.jsonl")
        var exportData = Data()

        for url in [archivedLogURL, currentLogURL] where FileManager.default.fileExists(atPath: url.path) {
            exportData.append(try Data(contentsOf: url))
        }

        try exportData.write(to: exportURL, options: .atomic)
        return exportURL
    }

    /**
     * 准备日志目录。
     *
     * @throws 目录创建异常
     */
    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: logDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    /**
     * 在日志超出大小限制时执行滚动。
     *
     * @throws 文件操作异常
     */
    private func rotateIfNeeded() throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: currentLogURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue >= Self.maximumFileSize else {
            return
        }

        if FileManager.default.fileExists(atPath: archivedLogURL.path) {
            try FileManager.default.removeItem(at: archivedLogURL)
        }
        try FileManager.default.moveItem(at: currentLogURL, to: archivedLogURL)
    }

    /**
     * 追加单条日志。
     *
     * @param entry 日志记录
     * @throws 编码或文件写入异常
     */
    private func append(_ entry: AppLogEntry) throws {
        var data = try encoder.encode(entry)
        data.append(0x0A)

        if !FileManager.default.fileExists(atPath: currentLogURL.path) {
            try data.write(to: currentLogURL, options: .atomic)
            return
        }

        let handle = try FileHandle(forWritingTo: currentLogURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    /**
     * 读取单个 JSONL 文件。
     *
     * @param url 日志文件地址
     * @returns 可解析的日志记录
     */
    private func readEntries(from url: URL) throws -> [AppLogEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.split(whereSeparator: \.isNewline).compactMap { line in
            try? decoder.decode(AppLogEntry.self, from: Data(line.utf8))
        }
    }

    /**
     * 清理日志文本，避免换行破坏 JSONL 结构并限制敏感内容扩散范围。
     *
     * @param value 原始文本
     * @param maximumLength 最大字符数
     * @returns 清理后的文本
     */
    private func sanitize(_ value: String, maximumLength: Int) -> String {
        let flattened = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return String(flattened.prefix(maximumLength))
    }
}
