import ActivityKit
import CoreLocation
import Foundation
import UIKit

/// Keeps one Live Activity in step with the simulated location: started when a Set begins
/// (only possible in the foreground), updated when the place or the connection state changes,
/// ended with Clear or a failed Set.
@MainActor
final class LiveActivityController {
    private var activity: Activity<SimulationActivityAttributes>?
    private var shown: SimulationActivityAttributes.ContentState?
    private var shownSet = 0
    // iOS ends an activity after eight hours; a dismissal before that was a swipe by the user.
    private var requestedAt = Date()
    // Kept across updates: an update while LocSim goes to the background must not clear it.
    private var staleDate: Date?
    // Set only when the user swiped the activity away, not when iOS ended it.
    private var dismissedSet: Int?
    private var ending: Task<Void, Never>?
    // Without a stale date, an activity left by a crashed LocSim would look current for hours.
    private let freshFor: TimeInterval

    /// Long names are cut: the content of an activity is limited to 4 KB.
    private static let nameLimit = 120
    private static let systemEnd: TimeInterval = 8 * 3600 - 15 * 60

    init(freshFor: TimeInterval) {
        self.freshFor = freshFor
        // A location from an earlier run ended with that process; its activity is stale.
        let leftovers = Self.current()
        Task { await Self.end(leftovers) }
        // Swiping LocSim away ends the simulation, but iOS keeps the activity on screen. While a
        // location is active the app runs in the background, so it is told before it quits.
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            Self.endAllBeforeExit()
            // The simulated location ends with the process; the widget must not keep showing it.
            MainActor.assumeIsolated {
                WidgetSync.clearActive()
                FavoriteUsage.end()
            }
        }
    }

    private nonisolated static func current() -> Set<String> {
        Set(Activity<SimulationActivityAttributes>.activities.map(\.id))
    }

    /// Ends the given activities; one started after the list was taken is left alone.
    // Not on the main actor: willTerminate waits for it while blocking the main thread.
    private nonisolated static func end(_ ids: Set<String>?) async {
        for activity in Activity<SimulationActivityAttributes>.activities where ids?.contains(activity.id) ?? true {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // Blocks briefly: the process ends right after this notification returns.
    private nonisolated static func endAllBeforeExit() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await end(nil)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    #if DEBUG
    /// For the screenshot of the Lock Screen in demo mode.
    /// Retries for a while: right after the Simulator boots, iOS refuses new activities.
    func showDemo(name: String, coordinate: String, startedAt: Date) async {
        let state = SimulationActivityAttributes.ContentState(
            name: name, coordinate: coordinate, reconnecting: false, startedAt: startedAt)
        for _ in 0..<20 {
            do {
                activity = try Activity.request(
                    attributes: SimulationActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: nil), pushType: nil)
                return
            } catch {
                print("Demo Live Activity not started yet: \(error)")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
    #endif

    private var isRunning: Bool {
        guard let state = activity?.activityState else { return false }
        return state == .active || state == .stale
    }

    /// `set` counts the Sets; an activity the user swiped away only comes back with the next one.
    func show(
        name: String, at c: CLLocationCoordinate2D, connecting: Bool, reconnecting: Bool, set: Int, startedAt: Date
    ) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.liveActivity),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return end() }
        noteDismissal()
        if dismissedSet == set { return }
        if set != shownSet { dismissedSet = nil }
        let state = SimulationActivityAttributes.ContentState(
            name: String(name.prefix(Self.nameLimit)), coordinate: CoordinateParser.format(c),
            reconnecting: reconnecting, startedAt: startedAt, connecting: connecting,
            spokenCoordinate: CoordinateParser.spoken(c))
        guard state != shown || !isRunning else { return }
        shown = state
        shownSet = set
        if staleDate == nil { staleDate = Date().addingTimeInterval(freshFor) }
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let activity, isRunning {
            Task { await activity.update(content) }
            return
        }
        // iOS ends an activity after eight hours and keeps it on screen for a while; a later
        // change replaces it, so only one is ever shown. The old one goes only once the new one
        // is there: in the background the request fails.
        let old = activity
        do {
            let new = try Activity.request(attributes: SimulationActivityAttributes(), content: content, pushType: nil)
            activity = new
            requestedAt = Date()
            if let old { Task { await old.end(nil, dismissalPolicy: .immediate) } }
        } catch {
            // Starting is only allowed in the foreground; the next change there tries again.
            shown = nil
        }
    }

    // Judged by age, not by state events: those may not arrive while LocSim is suspended.
    private func noteDismissal() {
        guard activity?.activityState == .dismissed, shown != nil else { return }
        if Date().timeIntervalSince(requestedAt) < Self.systemEnd { dismissedSet = shownSet }
        activity = nil
    }

    /// Marks the activity as outdated from `seconds` on, e.g. when iOS may suspend LocSim.
    func markStale(after seconds: TimeInterval) {
        staleDate = Date().addingTimeInterval(seconds)
        guard let activity, isRunning, let shown else { return }
        let content = ActivityContent(state: shown, staleDate: staleDate)
        Task { await activity.update(content) }
    }

    /// While LocSim keeps running, moves the stale date forward now and then, so the activity
    /// only turns outdated if LocSim stopped without saying so (crash, or iOS ended it).
    func keepFresh() {
        guard let staleDate, staleDate.timeIntervalSinceNow < freshFor / 2 else { return }
        markStale(after: freshFor)
    }

    func end() {
        shown = nil
        staleDate = nil
        activity = nil
        // All of them, also one iOS ended after eight hours that is still on screen.
        let ids = Self.current()
        ending = Task { await Self.end(ids) }
    }

    /// Waits for the last end(): iOS may suspend LocSim right after a Clear in the background.
    func waitForEnd() async {
        await ending?.value
    }
}
