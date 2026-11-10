import Foundation
import os

/// Opt-in: the same favorites on every device of the Apple Account, through the iCloud key-value
/// store. The data stays in the person's iCloud; LocSim runs no server. How often a favorite was
/// used is not shared: it stays on each device.
///
/// The list travels as a whole and the newest change wins. Until this device has seen the list in
/// iCloud once, it merges instead: right after turning it on, or on a new install, the local copy
/// of the iCloud data can still be empty, and sending this device's list then would replace the
/// favorites of the other devices.
@MainActor
enum FavoriteSync {
    private static let key = "favorites"
    private static let log = Logger(subsystem: "com.rockykln.locsim", category: "iCloud")
    private static var observer: NSObjectProtocol?
    private static var store: NSUbiquitousKeyValueStore { .default }

    static var isOn: Bool { UserDefaults.standard.bool(forKey: SettingsKey.iCloudFavorites) && !Demo.isOn }

    /// Set once this device has merged with the list from iCloud; from then on changes replace.
    private static var joined: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.iCloudFavoritesJoined) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.iCloudFavoritesJoined) }
    }

    /// At launch.
    static func start(_ list: FavoriteList) {
        guard isOn else { return }
        connect(list)
    }

    /// Turned on in Settings.
    static func turnedOn(_ list: FavoriteList) {
        guard isOn else { return }
        joined = false
        connect(list)
    }

    /// Turned off: this device keeps its copy, iCloud keeps the list for the other devices.
    static func turnedOff() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        joined = false
    }

    static func push(_ items: [Favorite]) {
        let payload = Payload(favorites: items, cleared: items.isEmpty)
        guard isOn, let data = try? JSONEncoder().encode(payload) else { return }
        guard data != store.data(forKey: key) else { return }
        store.set(data, forKey: key)
        let count = items.count
        log.debug("Sent \(count) favorites")
    }

    private static func connect(_ list: FavoriteList) {
        if FileManager.default.ubiquityIdentityToken == nil {
            log.error("iCloud is not available: not signed in, or iCloud is off for LocSim")
        }
        observe(list)
        // Asks iCloud for the current list; it arrives as a change notification.
        store.synchronize()
        let remote = load()
        // Plain values: the log evaluates its arguments later, outside the main actor.
        let wasJoined = joined, count = remote?.favorites.count ?? -1
        log.debug("Started, joined: \(wasJoined), favorites in iCloud: \(count)")
        if joined {
            apply(remote, list)
        } else {
            // Only adds: a list from iCloud that is not here yet must not be replaced.
            mergeIn(remote?.favorites ?? [], list)
        }
    }

    private static func observe(_ list: FavoriteList) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main
        ) { [weak list] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            Task { @MainActor in
                guard let list else { return }
                changed(reason, list)
            }
        }
    }

    private static func changed(_ reason: Int?, _ list: FavoriteList) {
        guard isOn else { return }
        let code = reason ?? -1
        log.debug("Change from iCloud, reason: \(code)")
        switch reason {
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            log.error("The iCloud key-value store is full")
            return
        case NSUbiquitousKeyValueStoreAccountChange:
            // Another Apple Account: its list is new to this device.
            joined = false
        default:
            break
        }
        let remote = load()
        if joined {
            apply(remote, list)
        } else {
            mergeIn(remote?.favorites ?? [], list)
            joined = true
        }
    }

    /// Takes over the list from iCloud, but never an empty one over this device's favorites
    /// unless the last favorite was removed on purpose. Favorites it removes here are kept, see
    /// `FavoriteList.removedByICloud`.
    private static func apply(_ remote: Payload?, _ list: FavoriteList) {
        guard let remote else {
            // Missing or unreadable: this device's list is the better copy.
            if !list.items.isEmpty { push(list.items) }
            return
        }
        if remote.favorites.isEmpty, !list.items.isEmpty, !remote.cleared {
            log.error("Ignored an empty list from iCloud that was not cleared on purpose")
            push(list.items)
            return
        }
        list.applyFromICloud(remote.favorites)
    }

    /// Adds the favorites only in iCloud and sends the result back, so both sides have all of them.
    private static func mergeIn(_ remote: [Favorite], _ list: FavoriteList) {
        let merged = merge(list.items, remote)
        // Nothing on either side: sending an empty list would only look like a deliberate clear.
        guard !merged.isEmpty else { return }
        if merged != list.items {
            list.items = merged   // sends it through didSet
        } else {
            push(merged)
        }
    }

    /// The list and whether it is empty on purpose, in one value so they always arrive together.
    private struct Payload: Codable {
        var favorites: [Favorite]
        /// Someone removed the last favorite; an empty list without it is never taken over.
        var cleared: Bool
    }

    /// Also reads the plain list of earlier test builds, which never counts as cleared.
    private static func load() -> Payload? {
        guard let data = store.data(forKey: key) else { return nil }
        if let payload = try? JSONDecoder().decode(Payload.self, from: data) { return payload }
        guard let list = try? JSONDecoder().decode([Favorite].self, from: data) else { return nil }
        return Payload(favorites: list, cleared: false)
    }

    /// This device's favorites first, then those only in iCloud. The same favorite on both sides,
    /// by id or by place and name, appears once.
    static func merge(_ local: [Favorite], _ remote: [Favorite]) -> [Favorite] {
        var result = local
        for favorite in remote where !result.contains(where: { same($0, favorite) }) {
            result.append(favorite)
        }
        return result
    }

    static func same(_ a: Favorite, _ b: Favorite) -> Bool {
        a.id == b.id || (a.name == b.name && a.coordinate.distance(to: b.coordinate) < 1)
    }
}
