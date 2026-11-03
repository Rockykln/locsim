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

    init() {
        // A location from an earlier run ended with that process; its activity is stale.
        Task {
            for activity in Activity<SimulationActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        // Swiping LocSim away ends the simulation, but iOS keeps the activity on screen. While a
        // location is active the app runs in the background, so it is told before it quits.
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            Self.endAllBeforeExit()
        }
    }

    // Blocks briefly: the process ends right after this notification returns.
    private nonisolated static func endAllBeforeExit() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for activity in Activity<SimulationActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    /// `set` counts the Sets; an activity the user swiped away only comes back with the next one.
    func show(name: String, coordinate: String, reconnecting: Bool, set: Int) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.liveActivity),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return end() }
        if activity?.activityState == .dismissed, set == shownSet { return }
        let state = SimulationActivityAttributes.ContentState(
            name: name, coordinate: coordinate, reconnecting: reconnecting)
        guard state != shown || set != shownSet || activity?.activityState != .active else { return }
        shown = state
        shownSet = set
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity, activity.activityState == .active {
            Task { await activity.update(content) }
            return
        }
        // iOS ends an activity after eight hours; a later change starts a new one.
        do {
            activity = try Activity.request(
                attributes: SimulationActivityAttributes(startedAt: Date()), content: content, pushType: nil)
        } catch {
            activity = nil
        }
    }

    /// Without Keep Alive iOS suspends LocSim and the simulation ends with the tunnel; from then on
    /// the activity shows as outdated instead of claiming a location.
    /// nil clears it again once LocSim is back in the foreground.
    func markStale(after seconds: TimeInterval?) {
        guard let activity, activity.activityState == .active, let shown else { return }
        let content = ActivityContent(state: shown, staleDate: seconds.map { Date().addingTimeInterval($0) })
        Task { await activity.update(content) }
    }

    func end() {
        shown = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
