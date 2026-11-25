import Foundation
import UIKit
@preconcurrency import UserNotifications

/// iOS can take its time zone from the location, so a simulated place in another time zone moves
/// the clock too, most noticeably offline. Only Settings > Privacy & Security > Location Services
/// > System Services > Setting Time Zone prevents it, and apps cannot open that page.
///
/// While a location is simulated this keeps the real time zone. When the device's time zone
/// changes, the map shows a notice, and in the background a notification says the same once.
@MainActor
final class TimeZoneWatch: ObservableObject {
    static let shared = TimeZoneWatch()

    /// The time zone the device moved to, while it differs from the real one.
    @Published private(set) var changedTo: TimeZone?
    /// Hidden until the next simulation once the person dismissed it.
    @Published private(set) var dismissed = false

    private var real: TimeZone?
    // The real zone for a few minutes after a simulation ended: the clock may still be in that
    // place's zone when the next one starts.
    private var recentReal: (zone: TimeZone, until: Date)?
    private var notified = false
    private var observer: NSObjectProtocol?
    private static let notificationID = "timeZoneChanged"

    var showsNotice: Bool { changedTo != nil && !dismissed }

    /// A location is simulated now; the time zone at this moment is the real one.
    func started() {
        guard real == nil else { return }
        NSTimeZone.resetSystemTimeZone()
        if let recent = recentReal, Date() < recent.until {
            real = recent.zone
        } else {
            real = TimeZone.current
        }
        recentReal = nil
        changedTo = nil
        dismissed = false
        notified = false
        observer = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        // A notification left from an earlier run is outdated; the zone may still differ, though.
        Self.removeNotification()
        check()
        // Quiet notifications need no question; the question comes once the notice is seen.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .provisional]) { _, _ in }
    }

    /// The real location is back, and with it the real time zone.
    func stopped() {
        guard let real else { return }
        recentReal = (real, Date().addingTimeInterval(10 * 60))
        self.real = nil
        changedTo = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        Self.removeNotification()
    }

    private static func removeNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
    }

    /// Also run when the app comes to the foreground, in case the change came while suspended.
    func check() {
        guard let real else { return }
        NSTimeZone.resetSystemTimeZone()
        let now = TimeZone.current
        guard now.identifier != real.identifier else {
            changedTo = nil
            // Back to the real zone: the notification no longer applies, and a later change notifies again.
            if notified { Self.removeNotification() }
            notified = false
            return
        }
        changedTo = now
        // Hidden for this location means no notification either.
        if UIApplication.shared.applicationState != .active, !notified, !dismissed {
            notified = true
            notify(now)
        }
    }

    func dismiss() {
        dismissed = true
    }

    /// Asks for banners once the person has seen the notice in the app, when it is clear why.
    func askForNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .notDetermined || status == .provisional else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    static func name(of zone: TimeZone) -> String {
        zone.localizedName(for: .generic, locale: .current) ?? zone.identifier
    }

    static func help(for zone: TimeZone) -> String {
        String(localized: "The time zone follows the simulated place and is now \(name(of: zone)). To keep the real time zone, turn off Settings > Privacy & Security > Location Services > System Services > Setting Time Zone.")
    }

    private func notify(_ zone: TimeZone) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time Zone Changed")
        content.body = Self.help(for: zone)
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
