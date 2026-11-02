import CoreLocation
import Foundation
import UIKit

@MainActor
final class SpoofSession: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case active
        /// The location channel dropped; the session keeps retrying with a growing delay.
        case reconnecting(AppError)
        case failed(AppError)

        var error: AppError? {
            switch self {
            case .reconnecting(let error), .failed(let error): return error
            default: return nil
            }
        }

        var isFailure: Bool { error != nil }

        var isReconnecting: Bool {
            if case .reconnecting = self { return true }
            return false
        }

        var label: String {
            switch self {
            case .idle: return "idle"
            case .connecting: return "connecting"
            case .active: return "active"
            case .reconnecting(let error): return "reconnecting \(error.code)"
            case .failed(let error): return "error \(error.code)"
            }
        }
    }

    enum PairingCheck: Equatable {
        case notChecked
        case checking
        case valid
        case rejected(AppError)
        case unreachable(AppError)
    }

    @Published var target: CLLocationCoordinate2D = LastCoordinate.load()
    @Published var targetName: String?
    @Published private(set) var active: CLLocationCoordinate2D?
    @Published private(set) var state: State = .idle
    @Published private(set) var port: UInt16?
    @Published private(set) var lastSent: Date?
    @Published private(set) var log: [String] = []
    /// The location is active, but without location access iOS suspends the app in the background.
    @Published private(set) var backgroundDenied = false
    @Published private(set) var pairingCheck = PairingCheck.notChecked

    private let link = DeviceLink()
    private let keepAlive = KeepAlive()
    private var resendTask: Task<Void, Never>?
    private var busy = false
    private var pending: CLLocationCoordinate2D?
    // Incremented by clear/disconnect so that work started earlier is discarded.
    private var generation = 0
    var hasBeenActive = false
    private var lastPort: UInt16?
    private var failedResends = 0
    private var backgroundFailures = 0
    private static let backgroundRetries = 3

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init() {
        keepAlive.onStatus = { [weak self] message in
            Task { @MainActor in self?.write(message) }
        }
        keepAlive.onDeniedChange = { [weak self] denied in
            Task { @MainActor in self?.backgroundDenied = denied }
        }
        if Demo.isOn {
            target = Demo.place.coordinate
            targetName = Demo.place.name
            simulate(target)
            return
        }
        // Quit launches the user never opened, e.g. a location resume after reboot.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !self.hasBeenActive, self.active == nil,
                  UIApplication.shared.applicationState == .background else { return }
            exit(0)
        }
    }

    var hasPairing: Bool { Demo.isOn || PairingStore.exists }
    func requestLocationPermission() { keepAlive.requestPermission() }
    var canClear: Bool { active != nil || state == .connecting || link.hasTunnel }

    func apply() async {
        await apply(target)
    }

    func apply(_ coordinate: CLLocationCoordinate2D) async {
        if Demo.isOn {
            target = coordinate
            return simulate(coordinate)
        }
        guard !busy else {
            pending = coordinate
            write("queued \(CoordinateParser.format(coordinate))")
            return
        }
        busy = true
        // A direct Set replaces anything still queued.
        pending = nil
        defer {
            busy = false
            runPending()
            releaseIfIdleInBackground()
        }

        target = coordinate
        LastCoordinate.save(coordinate)
        let started = generation
        // When-In-Use updates only start from the foreground, and the user may leave right after tapping.
        if UserDefaults.standard.bool(forKey: SettingsKey.keepAlive) { keepAlive.start() }
        do {
            try await send(coordinate, reconnect: true, started: started)
            guard started == generation else { return await discard() }
            active = coordinate
            state = .active
            failedResends = 0
            backgroundFailures = 0
            write("set \(CoordinateParser.format(coordinate))")
            if UserDefaults.standard.bool(forKey: SettingsKey.keepAlive) { keepAlive.start() }
            startResend()
        } catch {
            guard started == generation else { return await discard() }
            // A failed Set must not fall back to the previous location later.
            resendTask?.cancel()
            resendTask = nil
            active = nil
            keepAlive.stop()
            fail(error)
        }
    }

    func clear() async {
        generation += 1
        pending = nil
        failedResends = 0
        backgroundFailures = 0
        resendTask?.cancel()
        resendTask = nil
        keepAlive.stop()
        let finished = await clearLink()
        active = nil
        if finished {
            state = .idle
            releaseIfIdleInBackground()
        } else {
            fail(DeviceError(.clearLocation, "Clearing the location did not finish"))
        }
    }

    // Releasing the connection can block inside idevice, so Clear must not wait for it forever.
    private func clearLink() async -> Bool {
        let started = generation
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { @MainActor in
                do {
                    try await self.link.clear()
                    self.write("cleared")
                } catch {
                    self.write(error.localizedDescription)
                    await self.link.close()
                }
                once.finish(true)
                self.recoverFromLateClear(started)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                once.finish(false)
            }
        }
    }

    // The clear only came through after the timeout, so its error no longer applies.
    private func recoverFromLateClear(_ started: Int) {
        guard started == generation, state.error?.code == AppError.clearFailedCode else { return }
        state = .idle
        releaseIfIdleInBackground()
    }

    func disconnect() async {
        generation += 1
        pending = nil
        failedResends = 0
        backgroundFailures = 0
        resendTask?.cancel()
        resendTask = nil
        keepAlive.stop()
        active = nil
        state = .idle
        write("disconnected")
        await link.close()
    }

    func clearLog() { log.removeAll() }

    /// Applies the Keep Alive setting to a running session.
    func keepAliveChanged(_ on: Bool) {
        guard active != nil, !Demo.isOn else { return }
        if on { keepAlive.start() } else { keepAlive.stop() }
    }

    // Covers Clear or a failed Set that finished after the app went to the background.
    private func releaseIfIdleInBackground() {
        guard UIApplication.shared.applicationState == .background else { return }
        Task { await enteredBackground() }
    }

    // Release location updates and any idle tunnel while nothing is simulated.
    func enteredBackground() async {
        guard active == nil, state != .connecting, !busy else { return }
        keepAlive.stop()
        if link.hasTunnel {
            await link.close()
            write("idle in background, connection closed")
        }
    }

    private func send(_ c: CLLocationCoordinate2D, reconnect: Bool, started: Int) async throws {
        if !link.isOpen {
            try await reopen(started)
        }
        do {
            try await link.set(latitude: c.latitude, longitude: c.longitude)
        } catch let error where reconnect && !(error is CancellationError) {
            try ensureCurrent(started)
            write("send failed: \(error.localizedDescription)")
            try await reopen(started)
            try await link.set(latitude: c.latitude, longitude: c.longitude)
        }
        lastSent = Date()
    }

    /// Stops a connection attempt that was started before the last Clear.
    private func ensureCurrent(_ started: Int) throws {
        guard started == generation else { throw CancellationError() }
    }

    // A tunnel survives a switch to cellular but cannot be rebuilt without Wi-Fi.
    private func reopen(_ started: Int) async throws {
        try ensureCurrent(started)
        if link.hasTunnel {
            do {
                try await link.openLocation()
                try ensureCurrent(started)
                write("location channel reopened")
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                write("reopen failed: \(error.localizedDescription)")
            }
        }
        try await connect(started)
    }

    private func connect(_ started: Int) async throws {
        try ensureCurrent(started)
        if !state.isReconnecting { state = .connecting }
        let defaults = UserDefaults.standard
        let pairing = try PairingStore.load()
        let host = Self.setting(SettingsKey.host, default: Defaults.host)
        let hostname = Self.setting(SettingsKey.hostname, default: Defaults.hostname)
        let portText = Self.setting(SettingsKey.port, default: "")
        let manual = UInt16(portText).flatMap { $0 > 0 ? $0 : nil }
        if manual == nil, !portText.isEmpty { write("ignoring invalid port \"\(portText)\"") }
        var lastError: Error = DeviceError(.tunnel, "No port to try")
        var tried: UInt16?

        // The port is usually 49152 but can differ, so try the last known or default
        // port first and only browse when that fails.
        if manual == nil {
            let first = lastPort ?? PortResolver.fallbackPort
            write("tunnel \(host):\(first) (\(lastPort == nil ? "default" : "last used"))")
            do {
                try await link.openTunnel(LinkConfig(host: host, port: first, hostname: hostname, pairing: pairing))
                try ensureCurrent(started)
                port = first
                lastPort = first
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                write(error.localizedDescription)
                lastError = error
                lastPort = nil
                tried = first
            }
            if tried == nil {
                // Failures after the tunnel is up are not port problems; report them as they are.
                try await finishConnect(defaults, started)
                return
            }
        }

        let ports: [UInt16]
        if let manual {
            ports = [manual]
            write("port \(manual) (manual)")
        } else {
            let services = await PortResolver().browse()
            try ensureCurrent(started)
            // Names and addresses of other devices on the network stay out of the log.
            for s in services { write("bonjour port \(s.port) \(s.isLocal ? "local" : "remote")") }
            if services.isEmpty {
                write("bonjour: no _remotepairing._tcp service found")
            } else if !services.contains(where: { $0.isLocal }) {
                write("no local service, join any Wi-Fi to connect; cellular works once the tunnel is up")
            }
            ports = PortResolver.candidatePorts(services).filter { $0 != tried }
        }

        var connected = false
        for candidate in ports {
            write("tunnel \(host):\(candidate)")
            do {
                try await link.openTunnel(LinkConfig(host: host, port: candidate, hostname: hostname, pairing: pairing))
                try ensureCurrent(started)
                port = candidate
                lastPort = candidate
                connected = true
                break
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep the most telling error; "socket io" from other ports says little.
                if AppError(lastError).code == "LS-202" || tried == nil { lastError = error }
                write(error.localizedDescription)
            }
        }
        guard connected else { throw lastError }
        try await finishConnect(defaults, started)
    }

    private static func setting(_ key: String, default value: String) -> String {
        let stored = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? ""
        return stored.isEmpty ? value : stored
    }

    private func finishConnect(_ defaults: UserDefaults, _ started: Int) async throws {
        write("tunnel up on port \(port ?? 0)")
        if defaults.bool(forKey: SettingsKey.autoMount) {
            try await ensureDDI(started)
        }
        try await link.openLocation()
        try ensureCurrent(started)
        write("location service ready")
    }

    private func ensureDDI(_ started: Int) async throws {
        let mounted = try await link.isDDIMounted()
        try ensureCurrent(started)
        if mounted {
            write("DDI mounted")
            return
        }
        let method = DDIMethod.current
        write("DDI not mounted, installing (\(method.rawValue))")
        let dir = try await DDIStore.prepare(method) { [weak self] line in self?.write(line) }
        try ensureCurrent(started)
        try await link.mountDDI(from: dir, method: method)
        try ensureCurrent(started)
        write("DDI installed")
    }

    private func startResend() {
        resendTask?.cancel()
        resendTask = Task { [weak self] in
            while !Task.isCancelled {
                let base = max(UserDefaults.standard.integer(forKey: SettingsKey.resend), 3)
                // While reconnecting the delay doubles per failure, up to a minute.
                let failures = min(self?.failedResends ?? 0, 4)
                let seconds = failures == 0 ? base : min(base << failures, 60)
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.resend()
            }
        }
    }

    private func resend() async {
        guard let active, !busy else { return }
        busy = true
        defer {
            busy = false
            runPending()
        }
        let started = generation
        do {
            try await send(active, reconnect: true, started: started)
            guard started == generation else { return await discard() }
            if failedResends > 0 { write("reconnected") }
            failedResends = 0
            backgroundFailures = 0
            if state != .active { state = .active }
        } catch {
            guard started == generation else { return await discard() }
            failedResends += 1
            let appError = AppError(error)
            write("\(appError.code) \(appError.detail), retry \(failedResends)")
            // In the background, give up after a few attempts instead of retrying for hours.
            let inBackground = UIApplication.shared.applicationState == .background
            backgroundFailures = inBackground ? backgroundFailures + 1 : 0
            if backgroundFailures >= Self.backgroundRetries {
                await giveUp(error)
            } else {
                state = .reconnecting(appError)
            }
        }
    }

    private func giveUp(_ error: Error) async {
        resendTask?.cancel()
        resendTask = nil
        keepAlive.stop()
        active = nil
        failedResends = 0
        backgroundFailures = 0
        await link.close()
        fail(error)
        write("stopped reconnecting")
    }

    private func runPending() {
        guard pending != nil else { return }
        // Read the queue when the task runs, so a Set made in between is not overridden.
        Task { [weak self] in
            guard let self, let next = self.pending else { return }
            self.pending = nil
            await self.apply(next)
        }
    }

    // Undoes a send that completed after Clear.
    private func discard() async {
        try? await link.clear()
        await link.close()
        if active == nil, state == .connecting { state = .idle }
        write("discarded work started before clear")
    }

    /// Tries the pairing file against the device, unless a connection is in use.
    func checkPairing() async {
        guard !Demo.isOn else { return }
        // A running simulation already proves that the device accepts the file.
        if active != nil, state == .active {
            pairingCheck = .valid
            return
        }
        guard !busy, active == nil else { return }
        busy = true
        defer {
            busy = false
            runPending()
        }
        pairingCheck = .checking
        do {
            let port = UInt16(Self.setting(SettingsKey.port, default: "")).flatMap { $0 > 0 ? $0 : nil }
            try await link.openTunnel(LinkConfig(
                host: Self.setting(SettingsKey.host, default: Defaults.host),
                port: port ?? lastPort ?? PortResolver.fallbackPort,
                hostname: Self.setting(SettingsKey.hostname, default: Defaults.hostname),
                pairing: PairingStore.load()))
            await link.close()
            pairingCheck = .valid
            write("pairing file valid")
        } catch {
            let appError = AppError(error)
            pairingCheck = appError.rejectsPairing ? .rejected(appError) : .unreachable(appError)
            write("pairing check: \(appError.code) \(appError.detail)")
        }
    }

    func resetPairingCheck() { pairingCheck = .notChecked }

    private func simulate(_ coordinate: CLLocationCoordinate2D) {
        active = coordinate
        state = .active
        port = PortResolver.fallbackPort
        lastSent = Demo.sentTime
        write("set \(CoordinateParser.format(coordinate)) (demo)")
    }

    private func fail(_ error: Error) {
        let appError = AppError(error)
        state = .failed(appError)
        write("\(appError.code) \(appError.detail)")
    }

    private func write(_ line: String) {
        log.append("\(Self.timeFormat.string(from: Date())) \(line)")
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }
}

@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
