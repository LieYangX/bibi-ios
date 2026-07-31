import Foundation
import UIKit

/**
 * PC 连接管理器
 *
 * 负责 Bonjour 设备发现、配对认证、心跳检测和连接状态管理。
 *
 * @author xiangwei
 */
@MainActor
@Observable
final class ConnectionManager {
    /// 单次搜索持续时间。
    private static let searchDuration: Duration = .seconds(30)

    /// 当前连接状态
    private(set) var state: ConnectionState = .searching

    /// 已发现的 PC 设备列表
    private(set) var discoveredPCs: [PCDevice] = []

    /// 当前已连接的 PC 设备
    private(set) var connectedPC: PCDevice?

    /// 当前配对 token
    private(set) var authToken: String?

    /// Bonjour 发现器
    private let bonjourDiscovery = BonjourDiscovery()

    /// 心跳定时器
    private var healthCheckTimer: Timer?

    /// 重连任务
    private var reconnectTask: Task<Void, Never>?

    /// 搜索超时任务。
    private var searchTimeoutTask: Task<Void, Never>?

    /// 最后连接的 PC 设备 ID（用于自动重连）
    private var lastConnectedDeviceId: String?

    /**
     * 初始化
     */
    init() {
        bonjourDiscovery.onDeviceFound = { [weak self] device in
            self?.handleDeviceFound(device)
        }
    }

    // MARK: - Bonjour 发现

    /**
     * 开始搜索 PC 设备
     */
    func startSearching() {
        cancelSearch()
        state = .searching
        discoveredPCs.removeAll()
        bonjourDiscovery.start()

        searchTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.searchDuration)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self?.stopSearching()
        }
    }

    /**
     * 停止搜索 PC 设备
     */
    func stopSearching() {
        cancelSearch()

        if state == .searching {
            state = discoveredPCs.isEmpty ? .disconnected : .found
        }
    }

    /**
     * 取消当前搜索和超时计时。
     */
    private func cancelSearch() {
        searchTimeoutTask?.cancel()
        searchTimeoutTask = nil
        bonjourDiscovery.stop()
    }

    /**
     * 处理发现的设备
     */
    private func handleDeviceFound(_ device: PCDevice) {
        if !discoveredPCs.contains(where: { $0.id == device.id }) {
            discoveredPCs.append(device)
        }

        // 如果是上次连接的设备，尝试自动重连
        if device.id == lastConnectedDeviceId,
           let token = authToken,
           state != .connected {
            Task {
                await reconnect(to: device, token: token)
            }
        }
    }

    // MARK: - 连接与认证

    /**
     * 使用配对码连接 PC
     *
     * @param pc 目标 PC 设备
     * @param pairingCode 6 位配对码
     */
    func connect(to pc: PCDevice, pairingCode: String) async throws {
        guard let baseURL = baseURL(for: pc) else {
            throw PcError.notConnected
        }

        let url = baseURL.appending(path: "api/v1/pair")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let deviceName = await UIDevice.current.name

        let body: [String: Any] = [
            "code": pairingCode,
            "deviceName": deviceName
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PcError.toolFailed("配对失败")
        }

        let result = try JSONDecoder().decode(PairResponse.self, from: data)
        guard result.success, let token = result.data?.token else {
            throw PcError.toolFailed(result.error?.message ?? "配对失败")
        }

        authToken = token
        connectedPC = pc
        lastConnectedDeviceId = pc.id
        cancelSearch()
        state = .connected

        KeychainHelper.shared.savePairingToken(token)
        startHealthCheck()
    }

    /**
     * 使用已保存的 token 自动重连
     *
     * @param pc 目标 PC 设备
     */
    func reconnect(to pc: PCDevice) async throws {
        guard let token = authToken ?? KeychainHelper.shared.readPairingToken() else {
            throw PcError.notAuthenticated
        }

        await reconnect(to: pc, token: token)
    }

    /**
     * 使用指定 token 重连
     */
    private func reconnect(to pc: PCDevice, token: String) async {
        authToken = token

        if await ping() {
            connectedPC = pc
            lastConnectedDeviceId = pc.id
            cancelSearch()
            state = .connected
            startHealthCheck()
        } else {
            state = .disconnected
        }
    }

    /**
     * 断开 PC 连接
     */
    func disconnect() {
        stopHealthCheck()
        connectedPC = nil
        authToken = nil
        state = .disconnected
    }

    // MARK: - 心跳检测

    /**
     * 启动心跳检测
     */
    func startHealthCheck() {
        stopHealthCheck()

        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performHealthCheck()
            }
        }
    }

    /**
     * 停止心跳检测
     */
    func stopHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    /**
     * 执行一次心跳检测
     */
    private func performHealthCheck() async {
        let isHealthy = await ping()

        if !isHealthy {
            handleDisconnect()
        }
    }

    /**
     * 处理断线
     */
    private func handleDisconnect() {
        let deviceName = connectedPC?.name ?? "unknown"
        state = .disconnected
        connectedPC = nil
        stopHealthCheck()
        startReconnect()
        Task {
            await AppLogger.shared.log(
                .warning,
                category: "connection",
                message: "电脑连接中断，已开始自动重连",
                metadata: ["device_name": deviceName]
            )
        }
    }

    /**
     * 指数退避重连
     */
    private func startReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            var delay: UInt64 = 1_000_000_000
            let maxDelay: UInt64 = 30_000_000_000

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delay)

                guard let lastId = lastConnectedDeviceId,
                      let pc = discoveredPCs.first(where: { $0.id == lastId }),
                      let token = authToken ?? KeychainHelper.shared.readPairingToken() else {
                    continue
                }

                await reconnect(to: pc, token: token)

                if state == .connected {
                    return
                }

                delay = min(delay * 2, maxDelay)
            }
        }
    }

    // MARK: - 请求构建

    /**
     * PC 的 HTTP base URL
     */
    private func baseURL(for pc: PCDevice) -> URL? {
        URL(string: "http://\(pc.hostName):\(pc.port)")
    }

    /**
     * 当前连接 PC 的 HTTP base URL
     */
    var baseURL: URL? {
        connectedPC.flatMap { baseURL(for: $0) }
    }

    /**
     * 构建带认证 header 的 URLRequest
     *
     * @param path 请求路径
     * @param method HTTP 方法
     * @returns 已配置认证信息的 URLRequest
     */
    func authenticatedRequest(path: String, method: String = "GET") throws -> URLRequest {
        guard let baseURL = baseURL else {
            throw PcError.notConnected
        }

        guard let authToken = authToken else {
            throw PcError.notAuthenticated
        }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return request
    }

    /**
     * 健康检查 ping
     */
    func ping() async -> Bool {
        guard let request = try? authenticatedRequest(path: "api/v1/ping") else {
            return false
        }

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }
}

/**
 * 配对响应
 */
private struct PairResponse: Decodable {
    let success: Bool
    let data: PairData?
    let error: PcToolError?
}

/**
 * 配对数据
 */
private struct PairData: Decodable {
    let token: String
    let deviceName: String
}
