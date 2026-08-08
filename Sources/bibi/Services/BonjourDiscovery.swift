import Foundation

/**
 * Bonjour 发现委托
 *
 * 使用 NetServiceBrowser 在局域网内搜索 _bibi-tools._tcp 服务。
 *
 * @author xiangwei
 */
final class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    /// Bonjour 浏览器
    private let browser = NetServiceBrowser()

    /// 发现结果回调
    var onDeviceFound: ((PCDevice) -> Void)?

    /// 设备下线回调（按服务名匹配）
    var onDeviceRemoved: ((String) -> Void)?

    /// 搜索失败回调（如 Bonjour 权限受限）
    var onSearchFailed: ((Error?) -> Void)?

    /// 已解析的服务（避免重复委托）
    private var resolvingServices: Set<NetService> = []

    /// 当前是否允许接收发现结果。
    private var isSearching = false

    /**
     * 开始搜索 PC 服务。
     *
     * @author xiangwei
     */
    func start() {
        stop()
        isSearching = true
        browser.delegate = self
        browser.searchForServices(ofType: "_bibi-tools._tcp", inDomain: "local.")
    }

    /**
     * 停止搜索。
     *
     * @author xiangwei
     */
    func stop() {
        isSearching = false
        browser.stop()
        resolvingServices.forEach { service in
            service.stop()
            service.delegate = nil
        }
        resolvingServices.removeAll()
    }

    // MARK: - Bonjour 浏览器代理

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard isSearching else { return }
        service.delegate = self
        resolvingServices.insert(service)
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        // 服务下线，按服务名通知上层移除
        onDeviceRemoved?(service.name)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        isSearching = false
        onSearchFailed?(nil)
    }

    // MARK: - Bonjour 服务代理

    func netServiceDidResolveAddress(_ service: NetService) {
        defer {
            resolvingServices.remove(service)
            service.delegate = nil
        }

        guard isSearching else { return }

        let txt = service.txtRecordData().flatMap { NetService.dictionary(fromTXTRecord: $0) }
        let httpPortString = txt?["http_port"].flatMap { String(data: $0, encoding: .utf8) }
        let httpPort = Int(httpPortString ?? "19878") ?? 19878

        // 优先使用解析出的 IP 直连（IPv4 优先），hostName 仅作为回退
        let ipAddress = firstUsableIP(from: service.addresses)

        let pc = PCDevice(
            id: service.name,
            name: service.name.replacingOccurrences(of: "bibi-", with: ""),
            hostName: service.hostName ?? ipAddress ?? service.name,
            ipAddress: ipAddress,
            port: httpPort,
            bonjourPort: service.port,
            currentUser: txt?["user"].flatMap { String(data: $0, encoding: .utf8) },
            version: txt?["version"].flatMap { String(data: $0, encoding: .utf8) }
        )

        onDeviceFound?(pc)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolvingServices.remove(sender)
    }

    // MARK: - 地址解析

    /**
     * 从解析出的 socket 地址数组中提取可直连的 IP 字符串。
     *
     * 优先 IPv4；无 IPv4 时回退 IPv6（跳过链路本地地址）；均失败返回 nil（由调用方回退 hostName）。
     *
     * @param addresses NetService 解析出的原始地址数据
     * @returns IP 字符串
     */
    private func firstUsableIP(from addresses: [Data]?) -> String? {
        guard let addresses else { return nil }
        let ips = addresses.compactMap { ipAddress(from: $0) }
        return ips.first { isIPv4($0) } ?? ips.first { !$0.hasPrefix("fe80:") }
    }

    /**
     * 从单个 socket 地址数据中提取 IP 字符串。
     *
     * @param address 原始 socket 地址数据
     * @returns IP 字符串
     */
    private func ipAddress(from address: Data) -> String? {
        var host = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let result = address.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) -> String? in
            guard let base = rawPtr.baseAddress else { return nil }
            let sockAddr = base.assumingMemoryBound(to: sockaddr.self)

            switch sockAddr.pointee.sa_family {
            case sa_family_t(AF_INET):
                let addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee
                var addrBytes = addr.sin_addr
                guard let cString = inet_ntop(AF_INET, &addrBytes, &host, socklen_t(host.count)) else {
                    return nil
                }
                return String(cString: cString)
            case sa_family_t(AF_INET6):
                let addr = base.assumingMemoryBound(to: sockaddr_in6.self).pointee
                var addrBytes = addr.sin6_addr
                guard let cString = inet_ntop(AF_INET6, &addrBytes, &host, socklen_t(host.count)) else {
                    return nil
                }
                return String(cString: cString)
            default:
                return nil
            }
        }

        return result
    }

    /**
     * 判断 IP 字符串是否为 IPv4 格式。
     *
     * @param ip IP 字符串
     * @returns 是否为 IPv4
     */
    private func isIPv4(_ ip: String) -> Bool {
        ip.split(separator: ":").count == 1
    }
}
