import NetworkExtension

/// Connects LocSim to this device's own services. It routes nothing but the tunnel subnet,
/// talks to no server and ends itself when LocSim is gone.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    // Long enough for a Developer Disk Image download, during which the tunnel is quiet.
    private static let idleLimit: TimeInterval = 180

    private let queue = DispatchQueue(label: "locsim.tunnel.idle")
    private var lastPacket = Date()
    private var watchdog: DispatchSourceTimer?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: TunnelAddress.device)
        let ipv4 = NEIPv4Settings(addresses: [TunnelAddress.device], subnetMasks: [TunnelAddress.subnetMask])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: TunnelAddress.device, subnetMask: TunnelAddress.subnetMask)]
        ipv4.excludedRoutes = [.default()]
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self, error == nil else { return completionHandler(error) }
            self.startWatchdog()
            self.readPackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        queue.sync {
            watchdog?.cancel()
            watchdog = nil
        }
        completionHandler()
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
                self.queue.async { self.lastPacket = Date() }
                self.packetFlow.writePackets(reflected, withProtocols: families)
            }
            self.readPackets()
        }
    }

    // iOS keeps a tunnel running after its app was closed.
    private func startWatchdog() {
        queue.sync {
            lastPacket = Date()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 30, repeating: 30)
            timer.setEventHandler { [weak self] in
                guard let self, Date().timeIntervalSince(self.lastPacket) > Self.idleLimit else { return }
                self.cancelTunnelWithError(nil)
            }
            timer.resume()
            watchdog = timer
        }
    }
}
