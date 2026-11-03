import LocSimCore
import NetworkExtension

/// Connects LocSim to this device's own services. It routes nothing but the peer address,
/// talks to no server and ends itself shortly after LocSim stops sending its heartbeat.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let queue = DispatchQueue(label: "locsim.tunnel.heartbeat")
    // Uptime instead of the wall clock, which jumps when the time or time zone changes.
    private var lastHeartbeat = ProcessInfo.processInfo.systemUptime
    private var watchdog: DispatchSourceTimer?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: TunnelAddress.device)
        let ipv4 = NEIPv4Settings(addresses: [TunnelAddress.device], subnetMasks: [TunnelAddress.hostMask])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: TunnelAddress.peer, subnetMask: TunnelAddress.hostMask)]
        ipv4.excludedRoutes = [.default()]
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { error in
            guard error == nil else { return completionHandler(error) }
            self.startWatchdog()
            self.readPackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        queue.async {
            self.watchdog?.cancel()
            self.watchdog = nil
        }
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if messageData == TunnelAddress.heartbeat {
            queue.async { self.lastHeartbeat = ProcessInfo.processInfo.systemUptime }
        }
        completionHandler?(nil)
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            var reflected: [Data] = []
            var families: [NSNumber] = []
            for (packet, family) in zip(packets, protocols) where family.int32Value == AF_INET {
                if let result = LoopbackPacket.reflected(packet) {
                    reflected.append(result)
                    families.append(family)
                }
            }
            if !reflected.isEmpty {
                self.packetFlow.writePackets(reflected, withProtocols: families)
            }
            self.readPackets()
        }
    }

    // iOS keeps a tunnel running after its app was closed or suspended.
    private func startWatchdog() {
        queue.async { [weak self] in
            guard let self else { return }
            lastHeartbeat = ProcessInfo.processInfo.systemUptime
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(10))
            timer.setEventHandler { [weak self] in self?.checkHeartbeat() }
            timer.resume()
            watchdog = timer
        }
    }

    // Runs on `queue`.
    private func checkHeartbeat() {
        guard ProcessInfo.processInfo.systemUptime - lastHeartbeat > TunnelAddress.heartbeatTimeout else { return }
        watchdog?.cancel()
        watchdog = nil
        // Not on `queue`, which stopTunnel uses.
        DispatchQueue.global().async { [weak self] in self?.cancelTunnelWithError(nil) }
    }
}
