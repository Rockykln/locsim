import Darwin
import Foundation
import IDevice
import LocSimCore

struct LinkConfig {
    var host: String
    var port: UInt16
    var hostname: String
    var pairing: Data
}

/// Owns the RPPairing tunnel and the DVT location channel. The simulated
/// location is reset by iOS as soon as this channel closes.
final class DeviceLink: @unchecked Sendable {
    // Below idevice's runtime QoS to avoid priority inversion.
    private let queue = DispatchQueue(label: "locsim.device", qos: .utility)
    private let stateLock = NSLock()
    private var openFlag = false
    private var tunnelFlag = false
    private var stuckFlag = false

    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private var server: OpaquePointer?
    private var location: OpaquePointer?

    var isOpen: Bool { stateLock.withLock { openFlag } }
    var hasTunnel: Bool { stateLock.withLock { tunnelFlag } }
    /// A call did not return in time and still blocks the queue; the link must be replaced.
    var isStuck: Bool { stateLock.withLock { stuckFlag } }

    private enum Timeout {
        static let tunnel: TimeInterval = 30
        static let query: TimeInterval = 30
        static let mount: TimeInterval = 180
        static let location: TimeInterval = 20
        static let send: TimeInterval = 15
    }

    func openTunnel(_ config: LinkConfig) async throws {
        try await run(Timeout.tunnel) { try self.openTunnelLocked(config) }
    }

    func isDDIMounted() async throws -> Bool {
        try await run(Timeout.query) { try self.ddiMountedLocked() }
    }

    func mountDDI(from directory: URL, method: DDIMethod) async throws {
        try await run(Timeout.mount) { try self.mountDDILocked(directory, method) }
    }

    func openLocation() async throws {
        try await run(Timeout.location) { try self.openLocationLocked() }
    }

    func set(latitude: Double, longitude: Double) async throws {
        try await run(Timeout.send) {
            guard let location = self.location else { throw DeviceError(.notConnected, "Not connected") }
            do {
                try Self.check(location_simulation_set(location, latitude, longitude), .setLocation, "Set location")
            } catch {
                self.closeLocationLocked()
                throw error
            }
        }
    }

    func clear() async throws {
        try await run(Timeout.send) {
            defer { self.closeLocked() }
            guard let location = self.location else { return }
            try Self.check(location_simulation_clear(location), .clearLocation, "Clear location")
        }
    }

    func close() async {
        _ = try? await run(Timeout.send) { self.closeLocked() }
    }

    // idevice calls can block on a dead connection without returning, so each one has a deadline.
    private func run<T>(_ timeout: TimeInterval, _ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            let gate = ResumeGate()
            // A timer source, not asyncAfter: cancelling it once the call returns also removes the wakeup.
            let deadline = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            deadline.schedule(deadline: .now() + timeout, leeway: .milliseconds(500))
            deadline.setEventHandler {
                deadline.cancel()
                guard gate.claim() else { return }
                if gate.didBegin {
                    self.stateLock.withLock {
                        self.stuckFlag = true
                        self.openFlag = false
                        self.tunnelFlag = false
                    }
                }
                cont.resume(throwing: DeviceError(.notConnected, "Device did not respond within \(Int(timeout)) s"))
            }
            // Started before the call, which may finish and cancel it right away.
            deadline.resume()
            queue.async(qos: .utility, flags: .enforceQoS) {
                // Timed out while waiting behind another call: that call is the stuck one.
                guard gate.begin() else { return }
                let result = Result { try body() }
                self.publishState()
                if gate.claim() {
                    deadline.cancel()
                    cont.resume(with: result)
                }
            }
        }
    }

    private func publishState() {
        let open = location != nil
        let tunnel = adapter != nil
        stateLock.withLock {
            openFlag = open
            tunnelFlag = tunnel
        }
    }

    private func openTunnelLocked(_ config: LinkConfig) throws {
        closeLocked()

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = config.port.bigEndian
        guard inet_pton(AF_INET, config.host, &addr.sin_addr) == 1 else {
            throw DeviceError(.other, "Invalid address \(config.host)")
        }

        var pairing: OpaquePointer?
        try Self.check(config.pairing.withUnsafeBytes { raw in
            rp_pairing_file_from_bytes(raw.bindMemory(to: UInt8.self).baseAddress, UInt(raw.count), &pairing)
        }, .pairingInvalid, "Pairing file")
        defer { rp_pairing_file_free(pairing) }

        var newAdapter: OpaquePointer?
        var newHandshake: OpaquePointer?
        let err = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0, socklen_t(MemoryLayout<sockaddr_in>.size), config.hostname, pairing,
                    nil, nil, &newAdapter, &newHandshake)
            }
        }
        adapter = newAdapter
        handshake = newHandshake
        do {
            try Self.check(err, .tunnel, "Tunnel to \(config.host):\(config.port)")
        } catch {
            closeLocked()
            throw error
        }
    }

    private func ddiMountedLocked() throws -> Bool {
        let (adapter, handshake) = try tunnel()

        var cryptexError: Error?
        var installed: UnsafeMutablePointer<InstalledCryptexC>?
        do {
            try Self.check(cryptexd_installed_ddi(adapter, handshake, &installed), .ddiQuery, "Cryptex DDI query")
            if installed != nil {
                cryptexd_free_installed_cryptex(installed)
                return true
            }
        } catch {
            cryptexError = error
        }

        do {
            var mounter: OpaquePointer?
            try Self.check(image_mounter_connect_rsd(adapter, handshake, &mounter), .ddiQuery, "Image mounter")
            defer { image_mounter_free(mounter) }
            var devices: UnsafeMutablePointer<plist_t?>?
            var count = 0
            try Self.check(image_mounter_copy_devices(mounter, &devices, &count), .ddiQuery, "Mounted images")
            if let devices { idevice_plist_array_free(devices, UInt(count)) }
            return count > 0
        } catch {
            if let cryptexError { throw cryptexError }
            return false
        }
    }

    private func mountDDILocked(_ directory: URL, _ method: DDIMethod) throws {
        let (adapter, handshake) = try tunnel()

        switch method {
        case .cryptex:
            var assets: OpaquePointer?
            try Self.check(cryptex1_assets_load(directory.path, &assets), .ddiInstall, "Load DDI assets")
            defer { cryptex1_assets_free(assets) }
            try Self.check(cryptexd_install_ddi(adapter, handshake, assets, nil), .ddiInstall, "Install DDI cryptex")

        case .personalized:
            func file(_ name: String) throws -> Data {
                do {
                    return try Data(contentsOf: directory.appendingPathComponent(name), options: .mappedIfSafe)
                } catch {
                    throw DeviceError(.ddiInstall, "Cannot read \(name): \(error.localizedDescription)")
                }
            }
            let image = try file("Image.dmg")
            let trustcache = try file("Image.dmg.trustcache")
            let manifest = try file("BuildManifest.plist")

            var lockdown: OpaquePointer?
            try Self.check(lockdownd_connect_rsd(adapter, handshake, &lockdown), .ddiInstall, "Lockdown")
            defer { lockdownd_client_free(lockdown) }
            var value: plist_t?
            try Self.check(lockdownd_get_value(lockdown, "UniqueChipID", nil, &value), .ddiInstall, "UniqueChipID")
            defer { plist_free(value) }
            var chipID: UInt64 = 0
            plist_get_uint_val(value, &chipID)
            guard chipID != 0 else { throw DeviceError(.ddiInstall, "UniqueChipID missing") }

            var mounter: OpaquePointer?
            try Self.check(image_mounter_connect_rsd(adapter, handshake, &mounter), .ddiInstall, "Image mounter")
            defer { image_mounter_free(mounter) }
            let err = image.withUnsafeBytes { img in
                trustcache.withUnsafeBytes { tc in
                    manifest.withUnsafeBytes { bm in
                        image_mounter_mount_personalized_rsd(
                            mounter, adapter, handshake,
                            img.bindMemory(to: UInt8.self).baseAddress, img.count,
                            tc.bindMemory(to: UInt8.self).baseAddress, tc.count,
                            bm.bindMemory(to: UInt8.self).baseAddress, bm.count,
                            nil, chipID)
                    }
                }
            }
            try Self.check(err, .ddiInstall, "Mount personalized DDI")
        }
    }

    private func openLocationLocked() throws {
        closeLocationLocked()
        let (adapter, handshake) = try tunnel()
        do {
            var newServer: OpaquePointer?
            try Self.check(
                remote_server_connect_rsd(adapter, handshake, &newServer), .locationService, "DVT remote server")
            server = newServer

            var newLocation: OpaquePointer?
            try Self.check(location_simulation_new(server, &newLocation), .locationService, "Location service")
            location = newLocation
        } catch {
            closeLocationLocked()
            throw error
        }
    }

    private func tunnel() throws -> (OpaquePointer, OpaquePointer) {
        guard let adapter, let handshake else { throw DeviceError(.notConnected, "No tunnel") }
        return (adapter, handshake)
    }

    // The location client borrows the remote server, so free in reverse order.
    private func closeLocationLocked() {
        if let location { location_simulation_free(location) }
        if let server { remote_server_free(server) }
        location = nil
        server = nil
    }

    // Releasing the tunnel can block inside idevice, so it happens off the device
    // queue; the handles are detached first and never reused.
    private func closeLocked() {
        let (location, server, handshake, adapter) = (self.location, self.server, self.handshake, self.adapter)
        self.location = nil
        self.server = nil
        self.handshake = nil
        self.adapter = nil
        DispatchQueue.global(qos: .utility).async {
            if let location { location_simulation_free(location) }
            if let server { remote_server_free(server) }
            if let handshake { rsd_handshake_free(handshake) }
            if let adapter { adapter_free(adapter) }
        }
    }

    private static func check(
        _ err: UnsafeMutablePointer<IdeviceFfiError>?, _ kind: DeviceError.Kind, _ step: String
    ) throws {
        guard let err else { return }
        let message = err.pointee.message.map { String(cString: $0) } ?? "unknown error"
        let code = err.pointee.code
        let subCode = err.pointee.sub_code
        idevice_error_free(err)
        throw DeviceError(kind, "\(step): \(message) (\(code))", code: code, subCode: subCode)
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var began = false

    var didBegin: Bool { lock.withLock { began } }

    /// False if the deadline passed before the call could start.
    func begin() -> Bool {
        lock.withLock {
            began = !done
            return began
        }
    }

    func claim() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}
