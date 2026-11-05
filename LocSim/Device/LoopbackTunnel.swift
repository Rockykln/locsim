import Foundation
import LocSimCore
@preconcurrency import NetworkExtension

/// Starts and stops LocSim's own tunnel extension. It only runs while a connection needs it.
@MainActor
final class LoopbackTunnel {
    private static var providerID: String { (Bundle.main.bundleIdentifier ?? "") + ".tunnel" }
    // A Stop that loads the configuration must not end a tunnel started in the meantime.
    private var wanted = false
    private var heartbeat: Task<Void, Never>?
    private var session: NETunnelProviderSession?
    private var observer: NSObjectProtocol?
    // Concurrent first starts would otherwise each save a configuration.
    private var loading: Task<NETunnelProviderManager, Error>?
    /// Set once the user agreed to replace another selected VPN; cleared after the next start.
    var allowTakeover = false
    /// Called when the tunnel stops while it is still wanted, e.g. another VPN took over.
    var onDrop: (() -> Void)?

    /// Counts starts, so a stop requested before one of them can step aside.
    private(set) var startCount = 0

    func start() async throws {
        wanted = true
        startCount += 1
        let token = startCount
        let previous = session
        // A late status change from the previous run must not count as a drop of this one.
        stopWatching()
        let connection: NEVPNConnection
        do {
            // Agreement to replace another VPN is for this attempt only.
            defer { allowTakeover = false }
            do {
                connection = try await enabledManager().connection
            } catch {
                // The previous tunnel may still be up; without its heartbeat the extension ends itself.
                if let previous, previous.status == .connected, wanted, startCount == token, session == nil {
                    watch(previous)
                }
                throw error
            }
            _ = await wait(seconds: 5) { connection.status != .disconnecting }
            switch connection.status {
            case .connected:
                watch(connection)
                return
            case .connecting, .reasserting: break
            default: try connection.startVPNTunnel()
            }
        } catch let error as DeviceError {
            throw error
        } catch {
            throw DeviceError(.localTunnel, "Local tunnel: \(error.localizedDescription)")
        }
        var seenConnecting = false
        let up = await wait(seconds: 10) {
            if connection.status == .connecting { seenConnecting = true }
            // A provider that fails right away goes back to disconnected; no need to wait it out.
            return connection.status == .connected
                || (seenConnecting && [.disconnected, .invalid].contains(connection.status))
        }
        guard up, connection.status == .connected else {
            var reason = up ? "stopped while starting" : "timed out"
            do {
                try await connection.fetchLastDisconnectError()
            } catch {
                reason = error.localizedDescription
            }
            throw DeviceError(.localTunnel, "Local tunnel: \(reason)")
        }
        watch(connection)
    }

    /// Stops a tunnel left over from an earlier run, unless LocSim started one since `token`.
    func stopLeftover(since token: Int) async {
        guard startCount == token else { return }
        await stop()
    }

    func stop() async {
        wanted = false
        stopWatching()
        guard let manager = await existingManager(), !wanted else { return }
        switch manager.connection.status {
        case .connected, .connecting, .reasserting: manager.connection.stopVPNTunnel()
        default: break
        }
    }

    // The extension ends itself once the heartbeat stops, also when LocSim is closed or suspended.
    private func watch(_ connection: NEVPNConnection) {
        stopWatching()
        session = connection as? NETunnelProviderSession
        sendBeat()
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: connection, queue: .main
        ) { [weak self] note in
            // Read from the notification, so the closure does not hold on to the connection.
            let status = (note.object as? NEVPNConnection)?.status
            MainActor.assumeIsolated {
                guard let self, self.wanted, let status, [.disconnected, .invalid].contains(status) else { return }
                self.stopWatching()
                self.onDrop?()
            }
        }
    }

    /// Tells the extension LocSim still needs it. Called with every resend, so one wakeup does both.
    func beat() {
        // A recent beat is enough. The pending timer is anchored to that beat, so the gap the
        // extension sees stays at most heartbeatInterval + tolerance (90 s of the 120 s timeout).
        if let lastBeat, heartbeat != nil, ContinuousClock.now - lastBeat < Self.beatSkipWindow { return }
        sendBeat()
    }

    private static let beatSkipWindow: Duration = .seconds(30)
    private var lastBeat: ContinuousClock.Instant?

    private func sendBeat() {
        guard let session, wanted else { return }
        do {
            try session.sendProviderMessage(TunnelAddress.heartbeat) { _ in }
            lastBeat = .now
        } catch {
            lastBeat = nil
        }
        // Starts over with every sent beat, so a resend that beat in between saves the wakeup.
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .seconds(TunnelAddress.heartbeatInterval),
                    tolerance: .seconds(TunnelAddress.heartbeatTolerance))
            } catch {
                return
            }
            self?.sendBeat()
        }
    }

    private func stopWatching() {
        heartbeat?.cancel()
        heartbeat = nil
        lastBeat = nil
        session = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func existingManager() async -> NETunnelProviderManager? {
        let managers = try? await NETunnelProviderManager.loadAllFromPreferences()
        return managers?.first(where: Self.isOwn)
    }

    private static func isOwn(_ manager: NETunnelProviderManager) -> Bool {
        (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID
    }

    private func enabledManager() async throws -> NETunnelProviderManager {
        if let loading { return try await loading.value }
        let task = Task { try await self.loadEnabledManager() }
        loading = task
        defer { loading = nil }
        return try await task.value
    }

    // Saving a new configuration is what makes iOS ask for permission.
    private func loadEnabledManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let own = managers.filter(Self.isOwn)
        // Left over from concurrent first starts in earlier versions.
        for extra in own.dropFirst() { try? await extra.removeFromPreferences() }
        let existing = own.first
        if let existing, existing.isEnabled { return existing }
        // iOS disables LocSim's configuration when the user selects another VPN. Enabling it
        // again would switch that VPN off, so only do it once the user agreed.
        if existing != nil, !allowTakeover {
            throw DeviceError(.otherVPN, "Another VPN configuration is selected")
        }

        let manager = existing ?? NETunnelProviderManager()
        if existing == nil {
            let configuration = NETunnelProviderProtocol()
            configuration.providerBundleIdentifier = Self.providerID
            // Shown in Settings > VPN; set once, in the language of that moment.
            configuration.serverAddress = String(localized: "This iPhone", comment: "VPN settings: where the tunnel goes")
            manager.protocolConfiguration = configuration
            manager.localizedDescription = "LocSim"
        }
        manager.isOnDemandEnabled = false
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
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                return condition()
            }
        }
        return true
    }
}
