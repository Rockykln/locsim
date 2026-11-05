import CoreLocation
import Foundation
import LocSimCore
import UIKit

@MainActor
final class SimulationSession: ObservableObject {
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
    @Published var targetName: String? = LastCoordinate.loadName()
    @Published private(set) var active: CLLocationCoordinate2D? {
        didSet { syncActivity() }
    }
    @Published private(set) var state: State = .idle {
        didSet { syncActivity() }
    }
    /// Name of the place that is simulated, kept apart from the pin, which may have moved since.
    private var activeName: String?
    // When the active location was set, and by which Set; the Live Activity shows both.
    private var setAt = Date()
    private var activeSet = 0
    private var setNumber = 0
    // The Set the Live Activity shows while it connects.
    private var connectingTo: (coordinate: CLLocationCoordinate2D, name: String?, set: Int, since: Date)?
    private let liveActivity = LiveActivityController(freshFor: Timing.freshWhileKeptAlive)
    @Published private(set) var port: UInt16?
    @Published private(set) var lastSent: Date?
    // Published only in the foreground: each change redraws views nobody sees in the background.
    private var sentAt: Date? {
        didSet {
            if sentAt == nil || UIApplication.shared.applicationState != .background { lastSent = sentAt }
        }
    }
    /// Separate from the session, so a new line only redraws the log, not the map.
    let log = LogStore()
    /// The location is active, but without location access iOS suspends the app in the background.
    @Published private(set) var backgroundDenied = false
    @Published private(set) var pairingCheck = PairingCheck.notChecked
    /// Shows the app without a device connection; the location of the device does not change.
    @Published private(set) var isPreview = false
    /// Mirrors the device link, which is not observable, so Clear updates when it opens or closes.
    @Published private(set) var linkOpen = false
    /// Counts successful Sets, so the UI can confirm each one, not only the first.
    @Published private(set) var setCount = 0
    let recents = RecentList()

    private var link = DeviceLink()
    private let tunnel = LoopbackTunnel()
    private let keepAlive = KeepAlive()
    private var resendTask: Task<Void, Never>?
    private var busy = false
    // Set while Clear waits for the device, so no resend or Set can bring the location back.
    private var clearing = false {
        didSet { if isClearing != clearing { isClearing = clearing } }
    }
    /// Clear is waiting for the device; the location is no longer shown as active.
    @Published private(set) var isClearing = false
    // The name travels with the queued Set, so a pin moved in the meantime cannot rename it.
    private var pending: Pending?
    private struct Pending {
        let coordinate: CLLocationCoordinate2D
        let name: String?
        let takeover: Bool
        let request: Int?
        let set: Int
    }
    // The question (other VPN, DDI download) the last failed Set asked; only the user answers it.
    private var askedCode: String?
    // Shortcuts wait for the outcome of their own Set.
    private var requests = 0
    private var outcomes: [Int: SetOutcome] = [:]
    private var resendAfterWork = false
    private var pendingCheck = false
    // Incremented by clear/disconnect so that work started earlier is discarded.
    private var generation = 0
    private var lastPort: UInt16?
    private var failedResends = 0
    private var backgroundFailures = 0

    private enum Timing {
        static let backgroundRetries = 3
        static let clearTimeout: UInt64 = 3
        static let minResend = ResendPolicy.minimum
        static let logLines = 300
        static let freshWhileKeptAlive: TimeInterval = 600
        // Connecting can take minutes: port timeouts, a DDI download and mount.
        static let setWait: TimeInterval = 600
    }

    enum SetOutcome {
        case set
        case failed(AppError)
        /// Replaced by a newer Set or dropped by Clear.
        case notSet
    }

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static let shared: SimulationSession = {
        Defaults.register()
        return SimulationSession()
    }()

    private init() {
        keepAlive.onStatus = { [weak self] message in
            Task { @MainActor in self?.write(message) }
        }
        keepAlive.onDeniedChange = { [weak self] denied in
            Task { @MainActor in self?.backgroundDenied = denied }
        }
        keepAlive.onFix = { [weak self] fix in
            let coordinate = fix.coordinate
            Task { @MainActor in self?.checkFix(coordinate) }
        }
        if Demo.isOn {
            target = Demo.place.coordinate
            targetName = Demo.place.name
            simulate(target)
            #if DEBUG
            if Demo.screen == .live {
                // Shortly after launch, once the stale activities of earlier runs are gone.
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self else { return }
                    self.liveActivity.showDemo(
                        name: Demo.place.name, coordinate: CoordinateParser.format(Demo.place.coordinate),
                        startedAt: Demo.activityStart)
                }
            }
            #endif
            return
        }
        tunnel.onDrop = { [weak self] in
            Task { await self?.tunnelDropped() }
        }
        // iOS can keep the tunnel running after the app was closed. A Shortcut that launched the
        // app may already be starting it; that start wins.
        let token = tunnel.startCount
        Task { [weak self] in await self?.tunnel.stopLeftover(since: token) }
    }

    private var isSimulated: Bool { Demo.isOn || isPreview }
    var hasPairing: Bool { isSimulated || PairingStore.exists }
    func requestLocationPermission() { keepAlive.requestPermission() }
    var canClear: Bool { active != nil || state == .connecting || linkOpen }
    /// A Set, a Clear or a queued Set has not finished yet.
    var isWorking: Bool { busy || clearing || pending != nil }

    /// `consent` is true only when the user answered the question of the last failed Set
    /// (replace the other VPN, download the DDI) with Continue or Download.
    func apply(consent: Bool = false) async {
        let takeover = consent && answerQuestion()
        await apply(target, name: targetName, takeover: takeover)
    }

    func apply(_ coordinate: CLLocationCoordinate2D) async {
        await apply(coordinate, name: targetName)
    }

    /// For Shortcuts: sets the location and waits for this Set to end, also when it was queued.
    func setAndWait(_ coordinate: CLLocationCoordinate2D, name: String?) async -> SetOutcome {
        requests += 1
        let request = requests
        target = coordinate
        targetName = name
        await apply(coordinate, name: name, request: request)
        let deadline = Date().addingTimeInterval(Timing.setWait)
        while outcomes[request] == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return outcomes.removeValue(forKey: request) ?? .notSet
    }

    // Returns whether the answer allows replacing the other VPN; the DDI consent is stored.
    private func answerQuestion() -> Bool {
        defer { askedCode = nil }
        switch askedCode {
        case AppError.otherVPNCode: return true
        case AppError.ddiConsentCode: allowDDIDownload()
        default: break
        }
        return false
    }

    private func resolve(_ request: Int?, _ outcome: SetOutcome) {
        guard let request else { return }
        outcomes[request] = outcome
    }

    private func apply(
        _ coordinate: CLLocationCoordinate2D, name: String?, takeover: Bool = false, request: Int? = nil,
        set: Int? = nil
    ) async {
        if isSimulated {
            target = coordinate
            simulate(coordinate)
            return resolve(request, .set)
        }
        let set = set ?? nextSet()
        guard !busy, !clearing else {
            resolve(pending?.request, .notSet)
            pending = Pending(coordinate: coordinate, name: name, takeover: takeover, request: request, set: set)
            if active == nil {
                connectingTo = (coordinate, name, set, Date())
                state = .connecting
            }
            write("queued \(CoordinateParser.format(coordinate))")
            return
        }
        busy = true
        // A direct Set replaces anything still queued.
        resolve(pending?.request, .notSet)
        pending = nil
        var outcome = SetOutcome.notSet
        defer {
            resolve(request, outcome)
            finishWork()
            releaseIfIdleInBackground()
        }

        target = coordinate
        LastCoordinate.save(coordinate, name: name)
        // Shown as connecting while LocSim is still in the foreground: iOS refuses new activities later.
        connectingTo = (coordinate, name, set, Date())
        // Each Set decides on its own; a queued Set never inherits the answer.
        tunnel.allowTakeover = takeover
        let started = generation
        // When-In-Use updates only start from the foreground, and the user may leave right after tapping.
        if UserDefaults.standard.bool(forKey: SettingsKey.keepAlive) { keepAlive.start() }
        do {
            try await send(coordinate, reconnect: true, started: started)
            guard started == generation else { return await discard() }
            // Counted first: the Live Activity reads it when active and state change.
            setCount += 1
            setAt = Date()
            activeSet = set
            activeName = name
            askedCode = nil
            active = coordinate
            state = .active
            outcome = .set
            keepActivityFresh()
            failedResends = 0
            backgroundFailures = 0
            write("set \(CoordinateParser.format(coordinate))")
            recents.add(coordinate, name: name)
            if UserDefaults.standard.bool(forKey: SettingsKey.keepAlive) { keepAlive.start() }
            startResend()
        } catch {
            guard started == generation else { return await discard() }
            // A failed Set must not fall back to the previous location later.
            stopResending()
            active = nil
            // The device side may still be open (e.g. DDI not mounted); the next Set starts fresh.
            await link.close()
            syncLink()
            // A Clear made while the link closed has the last word.
            guard started == generation else { return }
            fail(error)
            outcome = .failed(AppError(error))
        }
    }

    private func nextSet() -> Int {
        setNumber += 1
        return setNumber
    }

    func clear() async {
        if isPreview {
            endSimulation()
            return
        }
        // A Clear already waits for the device and its generation drops older work. A new generation
        // would keep its late answer from lifting the error. Waiting lets a Shortcut report how it ended.
        if clearing {
            stopResending()
            while clearing { try? await Task.sleep(nanoseconds: 100_000_000) }
            return
        }
        generation += 1
        stopResending()
        // Nothing was set yet, so there is nothing to clear on the device.
        if active == nil, state == .connecting {
            // The attempt still running sees the new generation and closes the link itself.
            state = .idle
            write("connection cancelled")
            await releaseTunnelIfIdle()
            await liveActivity.waitForEnd()
            return
        }
        // Nothing may resend or set while the device clears; a Set made meanwhile runs afterwards.
        clearing = true
        active = nil
        let finished = await clearLink()
        // The state is written before anything else can run, so a Set made next is not overwritten.
        if finished {
            state = .idle
        } else {
            fail(DeviceError(.clearLocation, "Clearing the location did not finish"))
        }
        clearing = false
        await releaseTunnelIfIdle()
        if finished { releaseIfIdleInBackground() }
        runPending()
        // iOS may suspend LocSim right after a Clear from a Shortcut.
        await liveActivity.waitForEnd()
    }

    // Releasing the connection can block inside idevice, so Clear must not wait for it forever.
    private func clearLink() async -> Bool {
        // A resend or reconnect holds the device queue for up to 30 s, so a clear behind it would
        // time out. Dropping the link and stopping the tunnel ends the simulation on the device.
        if busy || state.isReconnecting || link.isStuck {
            replaceLink(link.isStuck ? "device did not respond, connection replaced" : "connection dropped to clear")
            await tunnel.stop()
            write("cleared, tunnel stopped")
            return true
        }
        let started = generation
        // After the timeout a newer Set may replace the link; a late answer must not close that one.
        let link = self.link
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { @MainActor in
                do {
                    try await link.clear()
                    self.write("cleared")
                } catch {
                    self.write(error.localizedDescription)
                    await link.close()
                }
                once.finish(true)
                self.syncLink()
                self.recoverFromLateClear(started)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: Timing.clearTimeout * 1_000_000_000)
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
        if isPreview { return endPreview() }
        generation += 1
        stopResending()
        active = nil
        state = .idle
        write("disconnected")
        await link.close()
        syncLink()
        await releaseTunnelIfIdle()
    }

    /// Pairing file removed or replaced: the running connection still uses the old one.
    func pairingChanged() async {
        setPairingCheck(.notChecked)
        PairingStore.clearRejection()
        if case .failed = state { state = .idle }
        guard !isSimulated, active != nil || linkOpen || state == .connecting else { return }
        await disconnect()
        write("pairing file changed, connection closed")
    }

    private func stopResending() {
        resolve(pending?.request, .notSet)
        pending = nil
        resendAfterWork = false
        failedResends = 0
        backgroundFailures = 0
        resendTask?.cancel()
        resendTask = nil
        keepAlive.stop()
    }

    // Assigning a @Published value redraws its views even when it did not change.
    private func syncLink() {
        let open = link.hasTunnel
        if linkOpen != open { linkOpen = open }
    }

    private func setPairingCheck(_ check: PairingCheck) {
        if pairingCheck != check { pairingCheck = check }
    }

    /// Replaces a link whose last call never returned. Its queue stays blocked, so the old
    /// link is closed once that call comes back, e.g. after the tunnel was stopped.
    @discardableResult
    private func renewLinkIfStuck() -> Bool {
        guard link.isStuck else { return false }
        replaceLink("device did not respond, connection replaced")
        return true
    }

    private func replaceLink(_ reason: String) {
        let old = link
        link = DeviceLink()
        write(reason)
        old.release()
        syncLink()
    }

    /// The tunnel extension stopped, e.g. another VPN was turned on or iOS ended it.
    private func tunnelDropped() async {
        write("local tunnel stopped")
        guard !clearing else { return }
        // Work in progress may just have rebuilt the link; resend once it is done.
        // The first Set may be about to succeed, so this does not depend on `active`.
        if busy {
            resendAfterWork = true
            return
        }
        await link.close()
        syncLink()
        guard active != nil else { return }
        await resend()
    }

    /// Sends right away after returning to the app instead of waiting for the next interval.
    func becameActive() async {
        lastSent = sentAt
        if active != nil {
            liveActivity.markStale(after: Timing.freshWhileKeptAlive)
            // Brings back an activity that could not be started or was ended while in the background.
            syncActivity()
        }
        guard active != nil, !isSimulated, !busy, !clearing else { return }
        if let sentAt, Date().timeIntervalSince(sentAt) < Double(Timing.minResend) { return }
        await resend()
    }

    func clearLog() { log.clear() }

    /// Applies the Live Activity setting to a running session.
    func liveActivityChanged() { syncActivity() }

    /// Applies a new resend interval now instead of after the current wait.
    func resendIntervalChanged() {
        guard resendTask != nil else { return }
        startResend()
    }

    // Not in the preview, where the location of the device does not change.
    private func syncActivity() {
        guard !isSimulated else { return liveActivity.end() }
        if let active {
            guard state == .active || state.isReconnecting else { return }
            liveActivity.show(
                name: activeName ?? String(localized: "Dropped pin"),
                coordinate: CoordinateParser.format(active),
                connecting: false,
                reconnecting: state.isReconnecting,
                set: activeSet,
                startedAt: setAt)
        } else if state == .connecting, let next = connectingTo {
            liveActivity.show(
                name: next.name ?? String(localized: "Dropped pin"),
                coordinate: CoordinateParser.format(next.coordinate),
                connecting: true,
                reconnecting: false,
                set: next.set,
                startedAt: next.since)
        } else {
            liveActivity.end()
        }
    }

    // Without Keep Alive iOS suspends LocSim soon in the background; the activity must turn outdated then.
    private func keepActivityFresh() {
        let background = UIApplication.shared.applicationState == .background
        if !background || (keepAlive.isRunning && !backgroundDenied) { liveActivity.keepFresh() }
    }

    /// Applies the Keep Alive setting to a running session.
    func keepAliveChanged(_ on: Bool) {
        guard active != nil, !isSimulated else { return }
        if on { keepAlive.start() } else { keepAlive.stop() }
    }

    // Covers Clear or a failed Set that finished after the app went to the background.
    private func releaseIfIdleInBackground() {
        guard UIApplication.shared.applicationState == .background else { return }
        Task { await enteredBackground() }
    }

    // Release location updates and any idle tunnel while nothing is simulated.
    func enteredBackground() async {
        if active != nil {
            // Without Keep Alive iOS suspends LocSim and the simulation ends with the tunnel. With it,
            // resends keep moving the date on, so it only passes if iOS ended LocSim.
            let keptAlive = keepAlive.isRunning && !backgroundDenied
            liveActivity.markStale(after: keptAlive ? Timing.freshWhileKeptAlive : TunnelAddress.heartbeatTimeout)
        }
        guard active == nil, state != .connecting, !busy else { return }
        keepAlive.stop()
        if link.hasTunnel {
            await link.close()
            write("idle in background, connection closed")
        }
        await releaseTunnelIfIdle()
    }

    private func finishWork() {
        busy = false
        syncLink()
        if resendAfterWork, pending == nil {
            resendAfterWork = false
            Task { [weak self] in await self?.resend() }
        }
        runPending()
        Task { await releaseTunnelIfIdle() }
    }

    private func releaseTunnelIfIdle() async {
        guard active == nil, !busy, !clearing, pending == nil else { return }
        await tunnel.stop()
    }

    private func send(_ c: CLLocationCoordinate2D, reconnect: Bool, started: Int) async throws {
        renewLinkIfStuck()
        if !link.isOpen {
            try await reopen(started)
        }
        do {
            try await link.set(latitude: c.latitude, longitude: c.longitude)
        } catch let error where reconnect && !(error is CancellationError) {
            try ensureCurrent(started)
            write("send failed: \(error.localizedDescription)")
            renewLinkIfStuck()
            try await reopen(started)
            try await link.set(latitude: c.latitude, longitude: c.longitude)
        }
        sentAt = Date()
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
                renewLinkIfStuck()
            }
        }
        try await connect(started)
    }

    private func connect(_ started: Int) async throws {
        try ensureCurrent(started)
        // While a location is active the state stays as it is until a resend fails.
        if active == nil { state = .connecting }
        try await openTunnel(started)
        try await finishConnect(started)
    }

    /// Opens the RPPairing tunnel: last known or default port first, Bonjour only when that fails.
    private func openTunnel(_ started: Int) async throws {
        let pairing = try PairingStore.load()
        let host = TunnelAddress.peer
        try await tunnel.start()
        try ensureCurrent(started)
        let hostname = Self.setting(SettingsKey.hostname, default: Defaults.hostname)
        let portText = Self.setting(SettingsKey.port, default: "")
        let manual = PairingPorts.manual(portText)
        if manual == nil, !portText.isEmpty { write("ignoring invalid port \"\(portText)\"") }
        var lastError: Error = DeviceError(.tunnel, "No port to try")
        var tried: UInt16?

        func attempt(_ candidate: UInt16) async throws -> Bool {
            do {
                try await link.openTunnel(LinkConfig(host: host, port: candidate, hostname: hostname, pairing: pairing))
                try ensureCurrent(started)
                if port != candidate { port = candidate }
                lastPort = candidate
                return true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                write(error.localizedDescription)
                renewLinkIfStuck()
                if tried == nil || Self.rank(error) >= Self.rank(lastError) { lastError = error }
                return false
            }
        }

        if manual == nil {
            let first = lastPort ?? PortResolver.fallbackPort
            write("tunnel \(host):\(first) (\(lastPort == nil ? "default" : "last used"))")
            if try await attempt(first) {
                write("tunnel up on port \(first)")
                return
            }
            lastPort = nil
            tried = first
        }

        let ports: [UInt16]
        var refused = false
        if let manual {
            ports = [manual]
            write("port \(manual) (manual)")
        } else {
            let resolver = PortResolver()
            let services = await resolver.browse()
            try ensureCurrent(started)
            refused = resolver.searchRefused
            // Names and addresses of other devices on the network stay out of the log.
            for s in services { write("bonjour port \(s.port) \(s.isLocal ? "local" : "remote")") }
            if refused {
                write("bonjour: search refused, Local Network access may be off")
            } else if services.isEmpty {
                write("bonjour: no _remotepairing._tcp service found")
            } else if !services.contains(where: { $0.isLocal }) {
                write("no local service, join any Wi-Fi to connect; cellular works once the tunnel is up")
            }
            ports = PairingPorts.candidates(services).filter { $0 != tried }
        }

        for candidate in ports {
            write("tunnel \(host):\(candidate)")
            if try await attempt(candidate) {
                write("tunnel up on port \(candidate)")
                return
            }
        }
        if refused, Self.rank(lastError) < 3 {
            throw DeviceError(.localNetwork, "Bonjour search refused; last error: \(lastError.localizedDescription)")
        }
        throw lastError
    }

    // Which failure to report when several ports fail: a refusal says the most, "socket io" the least.
    private static func rank(_ error: Error) -> Int {
        switch AppError(error).code {
        case "LS-203": return 3
        case "LS-201", "LS-206": return 2
        case "LS-202": return 0
        default: return 1
        }
    }

    private static func setting(_ key: String, default value: String) -> String {
        let stored = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? ""
        return stored.isEmpty ? value : stored
    }

    private func finishConnect(_ started: Int) async throws {
        if UserDefaults.standard.bool(forKey: SettingsKey.autoMount) {
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
        guard DDIStore.isDownloaded(method) || UserDefaults.standard.bool(forKey: SettingsKey.ddiDownloadAllowed) else {
            throw DeviceError(.ddiConsent, "DDI not mounted and not downloaded")
        }
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
                let seconds = ResendPolicy.delay(
                    base: UserDefaults.standard.integer(forKey: SettingsKey.resend), failures: self?.failedResends ?? 0)
                // A wide tolerance lets iOS bundle the wakeup with others; the heartbeat timeout allows it.
                try? await Task.sleep(for: .seconds(seconds), tolerance: .seconds(Double(seconds) / 3))
                guard !Task.isCancelled else { return }
                await self?.resend()
            }
        }
    }

    /// iOS can drop the simulation, e.g. when another device of the same Apple Account shares
    /// its real location. A fix far from the simulated place means that happened: send again
    /// right away instead of waiting for the next interval.
    private func checkFix(_ fix: CLLocationCoordinate2D) {
        guard let active, !isSimulated, state == .active else { return }
        let distance = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
            .distance(from: CLLocation(latitude: active.latitude, longitude: active.longitude))
        guard distance > KeepAlive.jump else { return }
        // A reset that keeps coming back must not turn into a send loop.
        if let sentAt, Date().timeIntervalSince(sentAt) < Double(Timing.minResend) { return }
        write("location reset by iOS, sending again")
        Task { await resend() }
    }

    private func resend() async {
        guard let active, !busy, !clearing else { return }
        busy = true
        defer { finishWork() }
        let started = generation
        do {
            try await send(active, reconnect: true, started: started)
            guard started == generation else { return await discard() }
            tunnel.beat()
            keepActivityFresh()
            if failedResends > 0 { write("reconnected") }
            failedResends = 0
            backgroundFailures = 0
            if state != .active, self.active != nil { state = .active }
        } catch {
            guard started == generation else { return await discard() }
            failedResends += 1
            let appError = AppError(error)
            write("\(appError.code) \(appError.detail), retry \(failedResends)")
            // In the background, give up after a few attempts instead of retrying for hours.
            let inBackground = UIApplication.shared.applicationState == .background
            backgroundFailures = inBackground ? backgroundFailures + 1 : 0
            if backgroundFailures >= Timing.backgroundRetries {
                await giveUp(error)
            } else {
                state = .reconnecting(appError)
            }
        }
    }

    private func giveUp(_ error: Error) async {
        let started = generation
        stopResending()
        active = nil
        await link.close()
        syncLink()
        guard started == generation else { return }
        fail(error)
        write("stopped reconnecting")
        // In the background iOS may suspend LocSim soon; the activity must be gone by then.
        await liveActivity.waitForEnd()
    }

    private func runPending() {
        if pendingCheck, pending == nil {
            pendingCheck = false
            Task { [weak self] in await self?.checkPairing() }
            return
        }
        guard pending != nil else { return }
        // Read the queue when the task runs, so a Set made in between is not overridden.
        Task { [weak self] in
            guard let self, let next = self.pending else { return }
            self.pending = nil
            await self.apply(
                next.coordinate, name: next.name, takeover: next.takeover, request: next.request, set: next.set)
        }
    }

    // Undoes a send that completed after Clear.
    private func discard() async {
        // Stopping the tunnel ends the simulation; a stuck link would only delay that.
        // A Set queued after the Clear is still connecting.
        if renewLinkIfStuck() {
            if active == nil, state == .connecting, pending == nil { state = .idle }
            return
        }
        try? await link.clear()
        await link.close()
        syncLink()
        if active == nil, state == .connecting, pending == nil { state = .idle }
        write("discarded work started before clear")
    }

    /// Tries the pairing file against the device, unless a connection is in use.
    func checkPairing() async {
        guard !isSimulated else { return }
        // A running simulation already proves that the device accepts the file.
        if active != nil, state == .active {
            setPairingCheck(.valid)
            return
        }
        guard active == nil else { return }
        // Picked up once the current work is done.
        guard !busy else {
            setPairingCheck(.checking)
            pendingCheck = true
            return
        }
        busy = true
        defer { finishWork() }
        setPairingCheck(.checking)
        let started = generation
        do {
            renewLinkIfStuck()
            try await openTunnel(started)
            await link.close()
            setPairingCheck(.valid)
            write("pairing file valid")
        } catch is CancellationError {
            // A Clear stopped the check; the device side must not stay open.
            await link.close()
            setPairingCheck(.notChecked)
        } catch {
            let appError = AppError(error)
            setPairingCheck(appError.rejectsPairing ? .rejected(appError) : .unreachable(appError))
            write("pairing check: \(appError.code) \(appError.detail)")
        }
    }

    /// Downloads the DDI ahead of time, e.g. on cellular, so that connecting later only mounts it.
    func downloadDDI() async throws {
        allowDDIDownload()
        _ = try await DDIStore.prepare(DDIMethod.current) { [weak self] line in self?.write(line) }
        write("DDI downloaded")
    }

    func allowDDIDownload() {
        UserDefaults.standard.set(true, forKey: SettingsKey.ddiDownloadAllowed)
    }

    func resetPairingCheck() { setPairingCheck(.notChecked) }

    func startPreview() {
        guard active == nil else { return }
        isPreview = true
        write("preview started")
    }

    func endPreview() {
        endSimulation()
        isPreview = false
    }

    private func endSimulation() {
        active = nil
        state = .idle
        sentAt = nil
        if port != nil { port = nil }
        write("preview cleared")
    }

    private func simulate(_ coordinate: CLLocationCoordinate2D) {
        setAt = Date()
        activeName = targetName
        active = coordinate
        state = .active
        port = Demo.isOn ? PortResolver.fallbackPort : nil
        sentAt = Demo.isOn ? Demo.sentTime : Date()
        setCount += 1
        if !Demo.isOn { recents.add(coordinate, name: targetName) }
        write("set \(CoordinateParser.format(coordinate)) (demo)")
    }

    private func fail(_ error: Error) {
        let appError = AppError(error)
        if [AppError.otherVPNCode, AppError.ddiConsentCode].contains(appError.code) { askedCode = appError.code }
        state = .failed(appError)
        write("\(appError.code) \(appError.detail)")
    }

    private func write(_ line: String) {
        log.add("\(Self.timeFormat.string(from: Date())) \(line)", limit: Timing.logLines)
    }
}

@MainActor
final class LogStore: ObservableObject {
    struct Line: Identifiable {
        let id: Int
        let text: String
    }

    @Published private(set) var lines: [Line] = []
    private var next = 0

    var text: String { lines.map(\.text).joined(separator: "\n") }

    func add(_ text: String, limit: Int) {
        lines.append(Line(id: next, text: text))
        next += 1
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
    }

    func clear() { lines.removeAll() }
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
