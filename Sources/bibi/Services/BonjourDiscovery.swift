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

    /// 已解析的服务（避免重复委托）
    private var resolvingServices: Set<NetService> = []

    /**
     * 开始搜索 PC 服务
     */
    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_bibi-tools._tcp", inDomain: "local.")
    }

    /**
     * 停止搜索
     */
    func stop() {
        browser.stop()
    }

    // MARK: - NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolvingServices.insert(service)
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        // 服务移除时可在此处理
    }

    // MARK: - NetServiceDelegate

    func netServiceDidResolveAddress(_ service: NetService) {
        guard let hostName = service.hostName else { return }

        let txt = service.txtRecordData().flatMap { NetService.dictionary(fromTXTRecord: $0) }
        let httpPortString = txt?["http_port"].flatMap { String(data: $0, encoding: .utf8) }
        let httpPort = Int(httpPortString ?? "19878") ?? 19878

        let pc = PCDevice(
            id: service.name,
            name: service.name.replacingOccurrences(of: "bibi-", with: ""),
            hostName: hostName,
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
}
