import Foundation

/// Opt-in: the same favorites on every device of the Apple Account, through the iCloud key-value
/// store. The data stays in the person's iCloud; LocSim runs no server. How often a favorite was
/// used is not shared: it stays on each device.
///
/// The list travels as a whole and the newest change wins. Turning it on merges this device's
/// list with the one in iCloud once, so nothing is lost on either side.
@MainActor
enum FavoriteSync {
    private static let key = "favorites"
    private static var observer: NSObjectProtocol?
    private static var store: NSUbiquitousKeyValueStore { .default }

    static var isOn: Bool { UserDefaults.standard.bool(forKey: SettingsKey.iCloudFavorites) && !Demo.isOn }

    /// At launch: iCloud has the current list, unless it has none yet.
    static func start(_ list: FavoriteList) {
        guard isOn else { return }
        observe(list)
        store.synchronize()
        if let remote = load() {
            list.applyFromICloud(remote)
        } else {
            push(list.items)
        }
    }

    /// Turned on in Settings: both lists together, then shared.
    static func turnedOn(_ list: FavoriteList) {
        guard isOn else { return }
        observe(list)
        store.synchronize()
        let merged = merge(list.items, load() ?? [])
        if merged != list.items {
            list.items = merged
        } else {
            push(merged)
        }
    }

    /// Turned off: this device keeps its copy, iCloud keeps the list for the other devices.
    static func turnedOff() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    static func push(_ items: [Favorite]) {
        guard isOn, let data = try? JSONEncoder().encode(items) else { return }
        guard data != store.data(forKey: key) else { return }
        store.set(data, forKey: key)
    }

    private static func observe(_ list: FavoriteList) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main
        ) { [weak list] _ in
            Task { @MainActor in
                guard let list, isOn, let remote = load() else { return }
                list.applyFromICloud(remote)
            }
        }
    }

    private static func load() -> [Favorite]? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([Favorite].self, from: data)
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

    private static func same(_ a: Favorite, _ b: Favorite) -> Bool {
        a.id == b.id || (a.name == b.name && a.coordinate.distance(to: b.coordinate) < 1)
    }
}
