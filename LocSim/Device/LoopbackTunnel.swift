import Foundation
import NetworkExtension

/// Starts and stops LocSim's own tunnel extension. It only runs while a connection needs it.
@MainActor
final class LoopbackTunnel {
    private static var providerID: String { (Bundle.main.bundleIdentifier ?? "") + ".tunnel" }
    // A Stop that loads the configuration must not end a tunnel started in the meantime.
    private var wanted = false

    func start() async throws {
        wanted = true
        let connection: NEVPNConnection
        do {
            connection = try await enabledManager().connection
            _ = await wait(seconds: 5) { connection.status != .disconnecting }
            switch connection.status {
            case .connected: return
            case .connecting, .reasserting: break
            default: try connection.startVPNTunnel()
            }
        } catch {
            throw DeviceError(.localTunnel, "Local tunnel: \(error.localizedDescription)")
        }
        guard await wait(seconds: 10, until: { connection.status == .connected }) else {
            var reason = "timed out"
            do {
                try await connection.fetchLastDisconnectError()
            } catch {
                reason = error.localizedDescription
            }
            throw DeviceError(.localTunnel, "Local tunnel: \(reason)")
        }
    }

    func stop() async {
        wanted = false
        guard let manager = await existingManager(), !wanted else { return }
        switch manager.connection.status {
        case .connected, .connecting, .reasserting: manager.connection.stopVPNTunnel()
        default: break
        }
    }

    private func existingManager() async -> NETunnelProviderManager? {
        let managers = try? await NETunnelProviderManager.loadAllFromPreferences()
        return managers?.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerID
        }
    }

    // Saving a new configuration is what makes iOS ask for permission.
    private func enabledManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let existing = managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerID
        }
        if let existing, existing.isEnabled { return existing }

        let manager = existing ?? NETunnelProviderManager()
        if existing == nil {
            let configuration = NETunnelProviderProtocol()
            configuration.providerBundleIdentifier = Self.providerID
            configuration.serverAddress = "This iPhone"
            manager.protocolConfiguration = configuration
            manager.localizedDescription = "LocSim"
        }
        manager.isEnabled = true
        try await manager.saveToPreferences()
        // A manager cannot start until it has been reloaded after saving.
        try await manager.loadFromPreferences()
        return manager
    }

    private func wait(seconds: Double, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return true
    }
}
