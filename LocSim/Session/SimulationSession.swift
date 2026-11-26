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
        didSet {
            syncActivity()
            if active?.latitude != oldValue?.latitude || active?.longitude != oldValue?.longitude {
                // The preview changes nothing on the device, so it counts as no use.
                FavoriteUsage.activeChanged(to: isSimulated ? nil : active)
            }
            // The preview does not move the device, so its time zone stays.
            if (active == nil) != (oldValue == nil), !isSimulated {
                if active == nil { TimeZoneWatch.shared.stopped() } else { TimeZoneWatch.shared.started() }
            }
        }
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

    /// A typed or pasted coordinate that is a favorite or a named recent place gets that name, in the
    /// app and in Shortcuts. Matched to about a meter, so a pin dropped next to it does not count.
    func knownName(for c: CLLocationCoordinate2D) -> String? {
        func same(_ other: CLLocationCoordinate2D) -> Bool {
            abs(other.latitude - c.latitude) < 1e-5 && abs(other.longitude - c.longitude) < 1e-5
        }
        if let favorite = FavoriteList.shared.items.first(where: { same($0.coordinate) }) { return favorite.name }
        return recents.items.first { $0.name != nil && same($0.coordinate) }?.name
    }

    private var link = DeviceLink()
    private let tunnel = LoopbackTunnel()
    private let keepAlive = KeepAlive()
    private var resendTask: Task<Void, Never>?
    private var busy = false
    // Set while Clear waits for the device, so no resend or Set can bring the location back.
    private var clearing = false {
        didSet {
            guard isClearing != clearing else { return }
            isClearing = clearing
            // The Live Activity and the widget waited for the outcome of the Clear.
            if !clearing { syncActivity() }
        }
    }
    /// Clear is waiting for the device; the location is no longer shown as active.
    @Published private(set) var isClearing = false
    // The name travels with the queued Set, so a pin moved in the meantime cannot rename it.
    private var pending: Pending? {
        didSet { updateSetInProgress() }
    }
    // A Set from apply() runs, as opposed to a resend or a pairing check.
    private var applying = false {
        didSet { updateSetInProgress() }
    }
    /// A Set waits for the current work, e.g. a reconnect, or runs; the button shows it, also
    /// while a location is active and the state stays as it is.
    @Published private(set) var setInProgress = false

    private func updateSetInProgress() {
        let running = pending != nil || applying
        if setInProgress != running { setInProgress = running }
    }
    /// The long step of connecting, if one runs: a download or install can take minutes.
    @Published private(set) var connectStep: String?
    private struct Pending {
        let coordinate: CLLocationCoordinate2D
        let name: String?
        let takeover: Bool
        let request: Int?
        let set: Int
    }
    // The question (other VPN, DDI download, first VPN configuration) the last failed Set or
    // reconnect asked; only the user answers it. The answer applies to the place that asked,
    // not to the pin, which may have moved since.
    private var askedCode: String?
    private var askedFor: (coordinate: CLLocationCoordinate2D, name: String?)?
    // Shortcuts wait for the outcome of their own Set; one that stopped waiting gets none.
    private var requests = 0
    private var waiting: Set<Int> = []
    private var outcomes: [Int: SetOutcome] = [:]
    private var resendAfterWork = false
    private var pendingCheck = false
    // The generation the running pairing check started in, so a second tap can be told apart
    // from a check for a new file.
    private var runningCheck: Int?
    // Incremented by clear/disconnect so that work started earlier is discarded.
    private var generation = 0
    // The port the tunnel last came up on, kept across launches: it saves a Bonjour search when
    // the device's port is not the default one. A wrong one costs one quick failed attempt.
    private var lastPort: UInt16? {
        get { (UserDefaults.standard.object(forKey: Self.lastPortKey) as? Int).flatMap { UInt16(exactly: $0) } }
        set {
            if let newValue {
                UserDefaults.standard.set(Int(newValue), forKey: Self.lastPortKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastPortKey)
            }
        }
    }
    private static let lastPortKey = "lastTunnelPort"
    private var failedResends = 0
    private var backgroundFailures = 0
    // True at launch too: the widget may show what an earlier run left.
    private var returnedFromBackground = true

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
        // A location only lasts as long as this process; a widget still showing one is outdated.
        WidgetSync.clearActive()
        keepAlive.onFix = { [weak self] fix in
            let coordinate = fix.coordinate
            let accuracy = fix.horizontalAccuracy
            Task { @MainActor in self?.checkFix(coordinate, accuracy: accuracy) }
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
                    await self.liveActivity.showDemo(
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
    /// The place the device simulates now, for Shortcuts: not the preview, not while connecting
    /// or clearing. While reconnecting the device still keeps the last location it got.
    var simulatedPlace: (coordinate: CLLocationCoordinate2D, name: String?)? {
        guard !isSimulated, !clearing, let active, state == .active || state.isReconnecting else { return nil }
        return (active, activeName)
    }
    /// The place to announce after a Set, also in the preview, which `simulatedPlace` leaves out.
    var announcedPlace: (coordinate: CLLocationCoordinate2D, name: String?)? {
        guard !clearing, let active, state == .active || state.isReconnecting else { return nil }
        return (active, activeName)
    }
    /// The place of a Clear that did not finish: the device may still simulate it.
    private(set) var unclearedPlace: (coordinate: CLLocationCoordinate2D, name: String?)? {
        didSet {
            guard (unclearedPlace == nil) != (oldValue == nil) else { return }
            syncActivity()
            QuickActions.refresh()
        }
    }
    /// A location is simulated, or a Clear did not finish and the device may still keep it.
    var mayStillBeSimulated: Bool { simulatedPlace != nil || unclearedPlace != nil }
    /// A file the setup script copied in counts: connecting takes it in.
    var hasPairing: Bool { isSimulated || PairingStore.exists || PairingStore.hasDroppedFile }

    /// Takes in a pairing file the setup script copied into Documents. Left for later while a
    /// connection is being made, which takes it in itself.
    /// Returns whether a file was taken in, so an old import error can go.
    @discardableResult
    func adoptDroppedPairing() -> Bool {
        guard !busy, !clearing, PairingStore.adoptNow() else { return false }
        write("pairing file taken from Documents")
        Task { await pairingFileReplaced() }
        return true
    }

    /// Imports a pairing file picked in Files. Returns the error to show, if any.
    func importPairing(_ result: Result<URL, Error>) -> String? {
        do {
            // The same file again changes nothing, so a running simulation stays.
            if try PairingStore.importFile(at: result.get()) { Task { await pairingFileReplaced() } }
            return nil
        } catch {
            let deviceError = error as? DeviceError ?? DeviceError(.pairingInvalid, error.localizedDescription)
            return AppError(deviceError).summary
        }
    }

    /// A new pairing file was imported: the old connection goes, the new file is checked.
    func pairingFileReplaced() async {
        if isPreview { endPreview() }
        await pairingChanged()
        await checkNewPairing()
    }
    func requestLocationPermission() { keepAlive.requestPermission() }
    /// Also after a Clear that did not finish, so it can be tried again.
    var canClear: Bool { active != nil || state == .connecting || linkOpen || unclearedPlace != nil }

    /// The pin on the simulated place got a name: the Live Activity, the widget and Shortcuts use it too.
    func renameActive(at c: CLLocationCoordinate2D, to name: String) {
        guard let active, !Demo.isOn, active.distance(to: c) < 1, activeName != name else { return }
        activeName = name
        syncActivity()
    }

    /// The place the open question is about, so the map can show where the answer sets it.
    var questionPlace: CLLocationCoordinate2D? { askedCode == nil ? nil : askedFor?.coordinate }

    /// `consent` is true only when the user answered the question of the last failed Set or
    /// reconnect (replace the other VPN, download the DDI, add the VPN configuration) with
    /// Continue or Download. The answer sets the place that asked.
    func apply(consent: Bool = false) async {
        let place = consent ? askedFor : nil
        let takeover = consent && answerQuestion()
        if let place {
            await apply(place.coordinate, name: place.name, takeover: takeover)
        } else {
            await apply(target, name: targetName, takeover: takeover)
        }
    }

    /// For Shortcuts: sets the location and waits for this Set to end, also when it was queued.
    /// The Set runs on its own: if iOS stops the Shortcut, it still finishes, like a tap in the app.
    func setAndWait(_ coordinate: CLLocationCoordinate2D, name: String?) async -> SetOutcome {
        requests += 1
        let request = requests
        waiting.insert(request)
        defer {
            waiting.remove(request)
            outcomes[request] = nil
        }
        target = coordinate
        targetName = name
        Task { await self.apply(coordinate, name: name, request: request) }
        let deadline = Date().addingTimeInterval(Timing.setWait)
        while outcomes[request] == nil, Date() < deadline {
            // A cancelled sleep returns at once; without this check the loop would spin.
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { break }
        }
        return outcomes[request] ?? .notSet
    }

    // Returns whether the answer allows replacing the other VPN; the other consents are stored.
    private func answerQuestion() -> Bool {
        defer {
            askedCode = nil
            askedFor = nil
        }
        switch askedCode {
        case AppError.otherVPNCode: return true
        case AppError.ddiConsentCode: allowDDIDownload()
        case AppError.vpnNoticeCode: UserDefaults.standard.set(true, forKey: SettingsKey.vpnNoticeShown)
        default: break
        }
        return false
    }

    private func ask(_ code: String, about place: (coordinate: CLLocationCoordinate2D, name: String?)?) {
        guard AppError.questionCodes.contains(code) else { return }
        askedCode = code
        askedFor = place
    }

    private func resolve(_ request: Int?, _ outcome: SetOutcome) {
        guard let request, waiting.contains(request) else { return }
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
        applying = true
        // A direct Set replaces anything still queued.
        resolve(pending?.request, .notSet)
        pending = nil
        var outcome = SetOutcome.notSet
        defer {
            applying = false
            // Consent that this Set did not use (the link was still open) must not carry over.
            tunnel.allowTakeover = false
            resolve(request, outcome)
            finishWork()
            releaseIfIdleInBackground()
        }

        target = coordinate
        // A queued Set brings its own name; the pin must not keep the previous one.
        targetName = name
        LastCoordinate.save(coordinate, name: name)
        // Shown as connecting while LocSim is still in the foreground: iOS refuses new activities later.
        connectingTo = (coordinate, name, set, Date())
        // Each Set decides on its own; a queued Set never inherits the answer.
        tunnel.allowTakeover = takeover
        let started = generation
        // When-In-Use updates only start from the foreground, and the user may leave right after tapping.
        if UserDefaults.standard.bool(forKey: SettingsKey.keepAlive) { keepAlive.start() }
        do {
            try await send(coordinate, started: started)
            guard started == generation else { return await discard() }
            // Counted first: the Live Activity reads it when active and state change.
            setCount += 1
            setAt = Date()
            activeSet = set
            activeName = name
            askedCode = nil
            askedFor = nil
            unclearedPlace = nil
            active = coordinate
            state = .active
            outcome = .set
            keepActivityFresh()
            failedResends = 0
            backgroundFailures = 0
            write("set \(CoordinateParser.format(coordinate))")
            recents.add(coordinate, name: name)
            // The setting may have been turned off while connecting.
            if UserDefaults.standard.bool(forKey: SettingsKey.keepAlive) { keepAlive.start() } else { keepAlive.stop() }
            startResend()
        } catch {
            guard started == generation else { return await discard() }
            // A failed Set must not fall back to the previous location later.
            stopResending(keepQueued: true)
            active = nil
            // The device side may still be open (e.g. DDI not mounted); the next Set starts fresh.
            // A stuck link is replaced at once: closing it would wait for the call that hangs.
            if !renewLinkIfStuck() { await link.close() }
            syncLink()
            // A Clear made while the link closed has the last word.
            guard started == generation else { return }
            fail(error, about: (coordinate: coordinate, name: name))
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
            while clearing {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            }
            return
        }
        // Clear is often tapped right before switching to the app being tested.
        let backgroundTime = BackgroundTime("Clear location")
        defer { backgroundTime.end() }
        generation += 1
        stopResending()
        // Nothing was set yet, so there is nothing to clear on the device. After a Clear that did
        // not finish there is: the normal path below stops the tunnel and settles that place.
        if active == nil, state == .connecting, unclearedPlace == nil {
            // The attempt still running sees the new generation and closes the link itself.
            state = .idle
            write("connection cancelled")
            await releaseTunnelIfIdle()
            await liveActivity.waitForEnd()
            return
        }
        // Nothing may resend or set while the device clears; a Set made meanwhile runs afterwards.
        clearing = true
        // A second Clear after one that did not finish still concerns the same place.
        let clearedPlace = active.map { (coordinate: $0, name: activeName) } ?? unclearedPlace
        active = nil
        let finished = await clearLink()
        // The state is written before anything else can run, so a Set made next is not overwritten.
        // A Set queued while the device cleared already shows that it is connecting and runs next.
        unclearedPlace = finished ? nil : clearedPlace
        if pending != nil {
            if !finished { write("clearing did not finish, the queued Set runs next") }
        } else if finished {
            state = .idle
        } else {
            fail(DeviceError(.clearLocation, "Clearing the location did not finish"))
        }
        clearing = false
        if finished {
            // Not awaited: the location is already back, and stopping the tunnel can take seconds,
            // which would keep a Control Center or Live Activity button busy. If iOS suspends LocSim
            // first, the extension stops the tunnel by itself once the heartbeat is gone.
            Task { await releaseTunnelIfIdle() }
            releaseIfIdleInBackground()
        } else {
            // The device did not confirm; stopping the tunnel is what is left, so it is awaited.
            await releaseTunnelIfIdle()
        }
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
                var cleared = false
                do {
                    try await link.clear()
                    cleared = true
                    self.write("cleared")
                } catch {
                    self.write(error.localizedDescription)
                    await link.close()
                }
                once.finish(true)
                self.syncLink()
                // Only a clear the device confirmed lifts the error; a failed one may not have run.
                if cleared { self.recoverFromLateClear(started) }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: Timing.clearTimeout * 1_000_000_000)
                once.finish(false)
            }
        }
    }

    // The clear only came through after the timeout, so its error no longer applies.
    private func recoverFromLateClear(_ started: Int) {
        guard started == generation else { return }
        unclearedPlace = nil
        guard state.error?.code == AppError.clearFailedCode else { return }
        state = .idle
        releaseIfIdleInBackground()
    }

    func disconnect() async {
        if isPreview { return endPreview() }
        generation += 1
        stopResending()
        active = nil
        // Closing the connection and the tunnel ends any simulation left on the device.
        unclearedPlace = nil
        state = .idle
        write("disconnected")
        if !renewLinkIfStuck() { await link.close() }
        syncLink()
        await releaseTunnelIfIdle()
    }

    /// Pairing file removed or replaced: the running connection still uses the old one.
    func pairingChanged() async {
        // A check still running uses the old file; its result must not show for the new one.
        generation += 1
        // Possibly another device.
        lastPort = nil
        setPairingCheck(.notChecked)
        PairingStore.clearRejection()
        if case .failed = state { state = .idle }
        guard !isSimulated, active != nil || linkOpen || state == .connecting else { return }
        await disconnect()
        write("pairing file changed, connection closed")
    }

    /// A failing Set keeps the newer Set queued behind it; Clear and disconnect drop it.
    private func stopResending(keepQueued: Bool = false) {
        if !keepQueued {
            resolve(pending?.request, .notSet)
            pending = nil
        }
        resendAfterWork = false
        failedResends = 0
        backgroundFailures = 0
        resendTask?.cancel()
        resendTask = nil
        // A queued Set runs next and needs it: in the background it could not be started again.
        if !(keepQueued && pending != nil) { keepAlive.stop() }
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
        adoptDroppedPairing()
        lastSent = sentAt
        TimeZoneWatch.shared.check()
        // A reload asked for in the background may never have happened; in the foreground it is free.
        // Not when only Control Center or a notification covered the app.
        if returnedFromBackground {
            returnedFromBackground = false
            WidgetSync.reload()
        }
        if active != nil {
            // Renewed only when it runs short: every widget change costs a reload.
            liveActivity.keepFresh()
            WidgetSync.keepFresh()
            // Brings back an activity that could not be started or was ended while in the background.
            syncActivity()
        }
        guard active != nil, !isSimulated, !busy, !clearing else { return }
        if let sentAt, Date().timeIntervalSince(sentAt) < Double(Timing.minResend) { return }
        await resend()
    }

    func clearLog() { log.clear() }

    #if DEBUG
    /// Layout measurements for devices only available in the Simulator (iPhone Duo).
    func noteLayout(_ line: String) { write(line) }
    #endif

    /// Applies the Live Activity setting to a running session. `reshow`: the user turned it on
    /// again, which also brings back an activity swiped away earlier.
    func liveActivityChanged(reshow: Bool = false) {
        if reshow { liveActivity.resetDismissal() }
        syncActivity()
    }

    /// The widgets and the Live Activity show coordinates in the chosen format too.
    func coordinateFormatChanged() {
        WidgetSync.setFavorites(FavoriteList.shared.items)
        syncActivity()
    }

    /// Applies a new resend interval now instead of after the current wait.
    func resendIntervalChanged() {
        // A resend in progress, e.g. one that restarts the tunnel, would be cancelled with it.
        // The loop reads the interval each round, so the new value counts from the next wait.
        guard resendTask != nil, !busy else { return }
        startResend()
    }

    // Not in the preview, where the location of the device does not change.
    private func syncActivity() {
        // The widget only shows a real simulation, not the preview or demo mode.
        // While a Clear waits for the device, or did not finish, the location may still be
        // simulated: the widget and the Live Activity keep showing it until that is settled.
        let mayStillShow = clearing || unclearedPlace != nil
        if let active, !isSimulated, state == .active || state.isReconnecting {
            WidgetSync.setActive(
                name: activeName ?? String(localized: "Dropped pin"), at: active, since: setAt)
        } else if (active == nil && !mayStillShow) || isSimulated {
            WidgetSync.clearActive()
        }
        // The demo shows its own activity for the screenshots; a scene change must not end it.
        if Demo.isOn { return }
        guard !isPreview else { return liveActivity.end() }
        if let active {
            guard state == .active || state.isReconnecting else { return }
            liveActivity.show(
                name: activeName ?? String(localized: "Dropped pin"),
                at: active,
                connecting: false,
                reconnecting: state.isReconnecting,
                set: activeSet,
                startedAt: setAt)
        } else if state == .connecting, let next = connectingTo {
            liveActivity.show(
                name: next.name ?? String(localized: "Dropped pin"),
                at: next.coordinate,
                connecting: true,
                reconnecting: false,
                set: next.set,
                startedAt: next.since)
        } else if clearing {
            // Left as it is until the device answers.
        } else if let uncleared = unclearedPlace {
            // A Clear that did not finish: the place may still be simulated, also after a new
            // Set failed, which showed itself as connecting meanwhile.
            liveActivity.show(
                name: uncleared.name ?? String(localized: "Dropped pin"),
                at: uncleared.coordinate,
                connecting: false,
                reconnecting: false,
                set: activeSet,
                startedAt: setAt)
        } else {
            liveActivity.end()
        }
    }

    // Without Keep Alive iOS suspends LocSim soon in the background; the activity must turn outdated then.
    private func keepActivityFresh() {
        let background = UIApplication.shared.applicationState == .background
        guard !background || (keepAlive.isRunning && !backgroundDenied) else { return }
        liveActivity.keepFresh()
        WidgetSync.keepFresh()
    }

    /// Applies the Keep Alive setting to a running session.
    func keepAliveChanged(_ on: Bool) {
        // While connecting too: the first Set already started it.
        guard active != nil || state == .connecting, !isSimulated else { return }
        if on { keepAlive.start() } else { keepAlive.stop() }
    }

    // Covers Clear or a failed Set that finished after the app went to the background.
    private func releaseIfIdleInBackground() {
        guard UIApplication.shared.applicationState == .background else { return }
        Task { await enteredBackground() }
    }

    // Release location updates and any idle tunnel while nothing is simulated.
    func enteredBackground() async {
        returnedFromBackground = true
        if active != nil {
            // Without Keep Alive iOS suspends LocSim and the simulation ends with the tunnel. With it,
            // resends keep moving the date on, so it only passes if iOS ended LocSim.
            let keptAlive = keepAlive.isRunning && !backgroundDenied
            if keptAlive {
                // No new date on every switch to the background: each one would cost a widget reload.
                liveActivity.keepFresh()
                WidgetSync.keepFresh()
            } else {
                liveActivity.markStale(after: TunnelAddress.heartbeatTimeout)
                WidgetSync.markStale(after: TunnelAddress.heartbeatTimeout)
                // The tunnel ends one heartbeat timeout after the last beat; a beat now makes that
                // the moment the activity turns outdated, not up to a beat interval earlier.
                tunnel.beat(force: true)
            }
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

    private func send(_ c: CLLocationCoordinate2D, started: Int) async throws {
        renewLinkIfStuck()
        if !link.isOpen {
            try await reopen(started)
        }
        do {
            try await link.set(latitude: c.latitude, longitude: c.longitude)
        } catch let error where !(error is CancellationError) {
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
        // A file the setup script copied in meanwhile is used for this connection right away.
        if PairingStore.adoptNow() {
            PairingStore.clearRejection()
            setPairingCheck(.notChecked)
            write("pairing file taken from Documents")
        }
        let pairing = try PairingStore.load()
        let host = TunnelAddress.peer
        try await checkVPNNotice()
        try ensureCurrent(started)
        try await tunnel.start()
        try ensureCurrent(started)
        let hostname = Self.setting(SettingsKey.hostname, default: Defaults.hostname)
        let portText = Self.setting(SettingsKey.port, default: "")
        let manual = PairingPorts.manual(portText)
        if manual == nil, !portText.isEmpty { write("ignoring invalid port \"\(portText)\"") }
        var lastError: Error = DeviceError(.tunnel, "No port to try")
        var tried: UInt16?
        var resetPorts: Set<UInt16> = []
        var localPorts: Set<UInt16> = []

        func attempt(_ candidate: UInt16) async throws -> Bool {
            // A Clear or disconnect while ports are tried stops the search here.
            try ensureCurrent(started)
            do {
                try await link.openTunnel(LinkConfig(host: host, port: candidate, hostname: hostname, pairing: pairing))
                try ensureCurrent(started)
                if port != candidate { port = candidate }
                lastPort = candidate
                return true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Failed because a Clear stopped the tunnel: no Bonjour search, the known port stays.
                try ensureCurrent(started)
                write(error.localizedDescription)
                if TunnelFailure.isReset(error.localizedDescription) { resetPorts.insert(candidate) }
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
            localPorts = Set(services.filter(\.isLocal).map(\.port))
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
        if Self.rank(lastError) < 3, TunnelFailure.refusedSilently(localPorts: localPorts, resetPorts: resetPorts) {
            write("pairing service of this device reset the connection: pairing refused")
            throw DeviceError(.pairingRefused,
                              "The device's pairing service reset the connection; last error: \(lastError.localizedDescription)")
        }
        throw lastError
    }

    // Which failure to report when several ports fail: a refusal says the most, "socket io" the least.
    private static func rank(_ error: Error) -> Int {
        switch AppError(error).code {
        case AppError.rejectedCode: return 3
        case AppError.unreachableCode, AppError.connectionFailedCode: return 2
        case AppError.pairingServiceCode: return 0
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
        defer { connectStep = nil }
        if !DDIStore.isDownloaded(method) { connectStep = String(localized: "Downloading Developer Disk Image") }
        let dir = try await DDIStore.prepare(method) { [weak self] line in self?.write(line) }
        try ensureCurrent(started)
        connectStep = String(localized: "Installing Developer Disk Image")
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
    private func checkFix(_ fix: CLLocationCoordinate2D, accuracy: CLLocationAccuracy) {
        // A Set or resend in progress sends anyway.
        guard let active, !isSimulated, state == .active, !busy, !clearing else { return }
        let distance = fix.distance(to: active)
        // A coarse fix that may still be at the simulated place is no reset.
        guard distance - max(0, accuracy) > KeepAlive.jump else { return }
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
            try await send(active, started: started)
            guard started == generation else { return await discard() }
            tunnel.beat()
            keepActivityFresh()
            if failedResends > 0 { write("reconnected") }
            failedResends = 0
            backgroundFailures = 0
            // A question the failed attempts asked is answered by now, e.g. LocSim was selected again in Settings.
            askedCode = nil
            askedFor = nil
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
                // The alert shows during reconnecting too; its answer must count, for the active place.
                ask(appError.code, about: (coordinate: active, name: activeName))
                state = .reconnecting(appError)
            }
        }
    }

    private func giveUp(_ error: Error) async {
        let started = generation
        let place = active.map { (coordinate: $0, name: activeName) }
        stopResending(keepQueued: true)
        active = nil
        if !renewLinkIfStuck() { await link.close() }
        syncLink()
        guard started == generation else { return }
        fail(error, about: place)
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
    /// After an import: checks only once the VPN configuration exists. Before that the check
    /// would bring up the iOS prompt, which the setup steps announce for the first Set.
    func checkNewPairing() async {
        guard await tunnel.hasConfiguration() else { return setPairingCheck(.notChecked) }
        await checkPairing()
    }

    func checkPairing() async {
        guard !isSimulated else { return }
        // A running simulation already proves that the device accepts the file.
        if active != nil, state == .active {
            setPairingCheck(.valid)
            return
        }
        guard active == nil else { return }
        // A second tap while a check runs would only run the same check again afterwards. A new
        // file is checked once the old check has stopped.
        guard runningCheck != generation else { return }
        // Picked up once the current work is done.
        guard !busy else {
            setPairingCheck(.checking)
            pendingCheck = true
            return
        }
        busy = true
        let started = generation
        runningCheck = started
        defer {
            runningCheck = nil
            finishWork()
        }
        setPairingCheck(.checking)
        do {
            renewLinkIfStuck()
            try await openTunnel(started)
            await link.close()
            // The file was replaced meanwhile; the next check reports on the new one.
            guard started == generation else { return setPairingCheck(.notChecked) }
            setPairingCheck(.valid)
            write("pairing file valid")
        } catch is CancellationError {
            // A Clear stopped the check; the device side must not stay open.
            await link.close()
            setPairingCheck(.notChecked)
        } catch {
            guard started == generation else { return setPairingCheck(.notChecked) }
            let appError = AppError(error)
            setPairingCheck(appError.rejectsPairing ? .rejected(appError) : .unreachable(appError))
            write("pairing check: \(appError.code) \(appError.detail)")
        }
    }

    /// Before LocSim's VPN configuration is added for the first time: iOS turns off another VPN
    /// that is selected, so the user is told first. Not needed once the configuration exists.
    func needsVPNNotice() async -> Bool {
        guard !isSimulated, !UserDefaults.standard.bool(forKey: SettingsKey.vpnNoticeShown) else { return false }
        if await tunnel.hasConfiguration() {
            // Added before this notice existed.
            UserDefaults.standard.set(true, forKey: SettingsKey.vpnNoticeShown)
            return false
        }
        return true
    }

    func acceptVPNNotice() {
        UserDefaults.standard.set(true, forKey: SettingsKey.vpnNoticeShown)
    }

    private func checkVPNNotice() async throws {
        guard await needsVPNNotice() else { return }
        throw DeviceError(.vpnNotice, "VPN configuration not added yet")
    }

    /// Downloads the DDI ahead of time, e.g. on cellular, so that connecting later only mounts it.
    func downloadDDI() async throws {
        allowDDIDownload()
        _ = try await DDIStore.prepare(DDIMethod.current) { [weak self] line in self?.write(line) }
        write("DDI downloaded")
        // The question of the last Set is answered; the next Set mounts the image.
        if state.error?.code == AppError.ddiConsentCode, active == nil {
            askedCode = nil
            askedFor = nil
            state = .idle
        }
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
        // Only Sets on the device count as recent places; the demo has its own list.
        if !isSimulated { recents.add(coordinate, name: targetName) }
        write("set \(CoordinateParser.format(coordinate)) (demo)")
    }

    private func fail(_ error: Error, about place: (coordinate: CLLocationCoordinate2D, name: String?)? = nil) {
        let appError = AppError(error)
        ask(appError.code, about: place)
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

/// Asks iOS for a little time to finish, e.g. for a Clear tapped right before leaving the app.
@MainActor
private final class BackgroundTime {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
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
