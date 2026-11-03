import ActivityKit
import Foundation
import UIKit

/// Keeps one Live Activity in step with the simulated location: started with the first Set,
/// updated when the place or the connection state changes, ended with Clear.
@MainActor
final class LiveActivityController {
    private var activity: Activity<SimulationActivityAttributes>?
    private var shown: SimulationActivityAttributes.ContentState?
    private var shownSet = 0
    // When the shown Set was made; a replacement activity keeps that start time.
    private var startedAt = Date()
    // Kept across updates: an update while LocSim goes to the background must not clear it.
    private var staleDate: Date?
    // Set only when the user swiped the activity away, not when iOS ended it.
    private var dismissedSet: Int?

    /// Long names are cut: the content of an activity is limited to 4 KB.
    private static let nameLimit = 120

    init() {
        // A location from an earlier run ended with that process; its activity is stale.
        let leftovers = Self.current()
        Task { await Self.end(leftovers) }
        // Swiping LocSim away ends the simulation, but iOS keeps the activity on screen. While a
        // location is active the app runs in the background, so it is told before it quits.
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            Self.endAllBeforeExit()
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
    func showDemo(name: String, coordinate: String, startedAt: Date) {
        let state = SimulationActivityAttributes.ContentState(name: name, coordinate: coordinate, reconnecting: false)
        activity = try? Activity.request(
            attributes: SimulationActivityAttributes(startedAt: startedAt),
            content: ActivityContent(state: state, staleDate: nil), pushType: nil)
    }
    #endif

    private var isRunning: Bool {
        guard let state = activity?.activityState else { return false }
        return state == .active || state == .stale
    }

    /// `set` counts the Sets; an activity the user swiped away only comes back with the next one.
    func show(name: String, coordinate: String, reconnecting: Bool, set: Int) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.liveActivity),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return end() }
        noteDismissal()
        if dismissedSet == set { return }
        let state = SimulationActivityAttributes.ContentState(
            name: String(name.prefix(Self.nameLimit)), coordinate: coordinate, reconnecting: reconnecting)
        guard state != shown || set != shownSet || !isRunning else { return }
        if set != shownSet {
            startedAt = Date()
            dismissedSet = nil
        }
        shown = state
        shownSet = set
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let activity, isRunning {
            Task { await activity.update(content) }
            return
        }
        // iOS ends an activity after eight hours and keeps it on screen for a while; a later
        // change replaces it, so only one is ever shown.
        if let old = activity {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        do {
            activity = try Activity.request(
                attributes: SimulationActivityAttributes(startedAt: startedAt), content: content, pushType: nil)
        } catch {
            // Starting is only allowed in the foreground; the next change there tries again.
            activity = nil
            shown = nil
        }
    }

    // A dismissed activity that was still running was swiped away by the user.
    private func noteDismissal() {
        guard activity?.activityState == .dismissed, shown != nil else { return }
        dismissedSet = shownSet
        activity = nil
    }

    /// Marks the activity as outdated from `seconds` on, e.g. when iOS may suspend LocSim.
    /// nil clears it again once LocSim is back in the foreground.
    func markStale(after seconds: TimeInterval?) {
        staleDate = seconds.map { Date().addingTimeInterval($0) }
        guard let activity, isRunning, let shown else { return }
        let content = ActivityContent(state: shown, staleDate: staleDate)
        Task { await activity.update(content) }
    }

    /// While LocSim keeps running in the background, moves the stale date forward now and then,
    /// so the activity only turns outdated if LocSim stopped without saying so (e.g. iOS ended it).
    func keepFresh(for seconds: TimeInterval) {
        guard let staleDate, staleDate.timeIntervalSinceNow < seconds / 2 else { return }
        markStale(after: seconds)
    }

    func end() {
        shown = nil
        staleDate = nil
        activity = nil
        // All of them, also one iOS ended after eight hours that is still on screen.
        let ids = Self.current()
        Task { await Self.end(ids) }
    }
}
