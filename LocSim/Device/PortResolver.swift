import Darwin
import Foundation

struct PairingService {
    let name: String
    let port: UInt16
    let addresses: [String]
    let isLocal: Bool
}

/// Discovers `_remotepairing._tcp` ports for when the default port fails. Other
/// devices on the network advertise the service too, so local results come first.
final class PortResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let fallbackPort: UInt16 = 49152

    private var browser: NetServiceBrowser?
    private var pending: [NetService] = []
    private var found: [PairingService] = []
    private var continuation: CheckedContinuation<[PairingService], Never>?

    @MainActor
    func browse(timeout: TimeInterval = 4) async -> [PairingService] {
        await withCheckedContinuation { cont in
            continuation = cont
            let browser = NetServiceBrowser()
            browser.delegate = self
            self.browser = browser
            browser.searchForServices(ofType: "_remotepairing._tcp.", inDomain: "local.")
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish()
            }
        }
    }

    /// Local ports first, at most two from other devices.
    static func candidatePorts(_ services: [PairingService]) -> [UInt16] {
        var ports: [UInt16] = []
        let remote = services.filter { !$0.isLocal }.prefix(2)
        for service in services.filter(\.isLocal) + remote where !ports.contains(service.port) {
            ports.append(service.port)
        }
        if !ports.contains(fallbackPort) { ports.append(fallbackPort) }
        return ports
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        pending.append(service)
        service.delegate = self
        service.resolve(withTimeout: 3)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard (1...65535).contains(sender.port) else { return }
        let addresses = Array(Set((sender.addresses ?? []).compactMap(Self.ipString))).sorted()
        let local = Self.localAddresses()
        found.removeAll { $0.name == sender.name && $0.port == UInt16(sender.port) }
        found.append(PairingService(
            name: sender.name,
            port: UInt16(sender.port),
            addresses: addresses,
            isLocal: addresses.contains { local.contains($0) }))
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        browser?.stop()
        browser = nil
        pending.forEach { $0.stop() }
        pending.removeAll()
        let result = found
        found.removeAll()
        continuation.resume(returning: result)
    }

    private static func ipString(_ data: Data) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard let sa = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return nil }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(sa, socklen_t(data.count), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            return rc == 0 ? normalize(String(cString: host)) : nil
        }
    }

    static func localAddresses() -> Set<String> {
        var result = Set<String>()
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return result }
        defer { freeifaddrs(head) }
        var cursor = head
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let sa = ifa.pointee.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            let len = family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.insert(normalize(String(cString: host)))
            }
        }
        return result
    }

    private static func normalize(_ ip: String) -> String {
        ip.split(separator: "%").first.map(String.init)?.lowercased() ?? ip
    }
}
