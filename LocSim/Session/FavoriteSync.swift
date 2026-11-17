import Foundation
import os

/// Opt-in: the same favorites on every device of the Apple Account, through the iCloud key-value
/// store. The data stays in the person's iCloud; LocSim runs no server. How often a favorite was
/// used is not shared: it stays on each device.
///
/// The list travels as a whole and the newest change wins, so a device must never send a list
/// that misses favorites it has not seen yet:
/// - Until a device has heard from iCloud it sends nothing; changes made meanwhile, deletions
///   included, are merged in once it does.
/// - A device that never hears from iCloud (offline, or no list exists yet) joins after a while,
///   but what it sends then is marked as an addition: other devices merge it instead of taking
///   it over, until this device hears from iCloud.
/// - A missing or unreadable list in iCloud is never answered with this device's list.
/// - Favorites a list from iCloud removes here are kept, see `FavoriteList.removedByICloud`.
@MainActor
enum FavoriteSync {
    private static let key = "favorites"
    private static let log = Logger(subsystem: "com.rockykln.locsim", category: "iCloud")
    private static var observer: NSObjectProtocol?
    private static var waitTask: Task<Void, Never>?
    /// How long to wait for news from iCloud before this device joins without it.
    private static let joinWait: Duration = .seconds(60)
    private static let deletedLimit = 200
    private static var store: NSUbiquitousKeyValueStore { .default }

    static var isOn: Bool { UserDefaults.standard.bool(forKey: SettingsKey.iCloudFavorites) && !Demo.isOn }

    /// Set once this device has merged with the list from iCloud; from then on changes replace.
    private static var joined: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.iCloudFavoritesJoined) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.iCloudFavoritesJoined) }
    }

    /// Joined without having heard from iCloud: what this device sends is only added elsewhere.
    private static var blind: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.iCloudFavoritesBlind) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.iCloudFavoritesBlind) }
    }

    /// Favorites deleted here before joining, so the merge does not bring them back.
    private static var deletedBeforeJoin: [Favorite] {
        get { StoredList.load(SettingsKey.iCloudFavoritesDeleted) ?? [] }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: SettingsKey.iCloudFavoritesDeleted)
            } else {
                StoredList.save(Array(newValue.suffix(deletedLimit)), SettingsKey.iCloudFavoritesDeleted)
            }
        }
    }

    /// At launch.
    static func start(_ list: FavoriteList) {
        guard isOn else { return }
        connect(list)
    }

    /// Turned on in Settings.
    static func turnedOn(_ list: FavoriteList) {
        guard isOn else { return }
        reset()
        connect(list)
    }

    /// Turned off: this device keeps its copy, iCloud keeps the list for the other devices.
    static func turnedOff() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        reset()
    }

    private static func reset() {
        waitTask?.cancel()
        waitTask = nil
        joined = false
        blind = false
        deletedBeforeJoin = []
    }

    /// Every change made on this device, also restoring favorites.
    static func localChange(from old: [Favorite], to new: [Favorite]) {
        guard isOn else { return }
        if joined {
            send(new, additive: blind)
            return
        }
        let removed = old.filter { before in !new.contains { same(before, $0) } }
        if !removed.isEmpty { deletedBeforeJoin = merge(deletedBeforeJoin, removed) }
        // A favorite added again is no longer deleted.
        let readded = deletedBeforeJoin.filter { gone in new.contains { same(gone, $0) } }
        if !readded.isEmpty { deletedBeforeJoin = deletedBeforeJoin.filter { gone in !readded.contains { same(gone, $0) } } }
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
        // Joined without having heard from iCloud: the local copy may be its own addition or
        // old, so only a change notification is acted on.
        if joined, blind { return }
        if joined, let remote {
            apply(remote, list)
            return
        }
        // Joined, but no list here: a device restored from a backup or moved to a new one keeps
        // this setting, not the local copy of the iCloud data. It must not send its old list.
        if joined {
            log.debug("Joined, but no list here yet: waiting for iCloud")
            joined = false
            blind = false
        }
        waitForList(list)
    }

    /// Joins when iCloud reports a change. Without one, for example offline or when no list
    /// exists yet, it joins after a while with what it has, marked as an addition.
    private static func waitForList(_ list: FavoriteList) {
        waitTask?.cancel()
        waitTask = Task { @MainActor [weak list] in
            try? await Task.sleep(for: joinWait)
            guard !Task.isCancelled, let list, isOn, !joined,
                  FileManager.default.ubiquityIdentityToken != nil else { return }
            log.debug("No news from iCloud: joining, sending only additions")
            join(load(), list, heardFromICloud: false)
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
            reset()
            if load() == nil {
                // The new account's list may not be here yet.
                waitForList(list)
                return
            }
        default:
            break
        }
        let remote = load()
        guard joined else {
            join(remote, list, heardFromICloud: true)
            return
        }
        // Missing or unreadable, e.g. from a newer version: never answered with this list.
        guard let remote else { return }
        if blind {
            // First news after joining without it: the list from iCloud may be newer, so both are kept.
            blind = false
            addFromICloud(remote.favorites, list)
            return
        }
        apply(remote, list)
    }

    /// Merges with the list from iCloud. Having heard from iCloud, the result replaces the list
    /// there; it only leaves out what was deleted here on purpose. Without that, it is sent as an
    /// addition, since the local copy of the iCloud data may be old.
    private static func join(_ remote: Payload?, _ list: FavoriteList, heardFromICloud: Bool) {
        waitTask?.cancel()
        waitTask = nil
        let deleted = deletedBeforeJoin
        let remoteItems = (remote?.favorites ?? []).filter { item in !deleted.contains { same($0, item) } }
        let merged = merge(list.items, remoteItems)
        joined = true
        blind = !heardFromICloud
        deletedBeforeJoin = []
        if merged != list.items { list.setFromSync(merged) }
        let count = merged.count
        log.debug("Joined with \(count) favorites")
        if merged.isEmpty {
            // Everything was deleted here on purpose while waiting: that is a clear.
            if heardFromICloud, !deleted.isEmpty, remote?.favorites.isEmpty == false { send([], additive: false) }
            return
        }
        if merged != remote?.favorites { send(merged, additive: blind) }
    }

    /// Takes over the list from iCloud, but never an empty one over this device's favorites
    /// unless the last favorite was removed on purpose. Favorites it removes here are kept, see
    /// `FavoriteList.removedByICloud`. A list marked as an addition is merged instead.
    private static func apply(_ remote: Payload, _ list: FavoriteList) {
        if remote.additive {
            addFromICloud(remote.favorites, list)
            return
        }
        if remote.favorites.isEmpty, !list.items.isEmpty, !remote.cleared {
            log.error("Ignored an empty list from iCloud that was not cleared on purpose")
            send(list.items, additive: false)
            return
        }
        list.applyFromICloud(remote.favorites)
    }

    /// Keeps everything on both sides and sends the result as the new list.
    private static func addFromICloud(_ remote: [Favorite], _ list: FavoriteList) {
        let merged = merge(list.items, remote)
        if merged != list.items { list.setFromSync(merged) }
        if !merged.isEmpty, merged != remote { send(merged, additive: false) }
    }

    private static func send(_ items: [Favorite], additive: Bool) {
        let payload = Payload(favorites: items, cleared: items.isEmpty && !additive, additive: additive)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        guard data != store.data(forKey: key) else { return }
        store.set(data, forKey: key)
        let count = items.count
        log.debug("Sent \(count) favorites, addition: \(additive)")
    }

    /// The list and how to take it, in one value so they always arrive together.
    private struct Payload: Codable {
        var favorites: [Favorite]
        /// Someone removed the last favorite; an empty list without it is never taken over.
        var cleared: Bool
        /// Sent by a device that had not heard from iCloud: merged, never taken over.
        var additive: Bool

        init(favorites: [Favorite], cleared: Bool, additive: Bool) {
            self.favorites = favorites
            self.cleared = cleared
            self.additive = additive
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            favorites = try c.decode([Favorite].self, forKey: .favorites)
            cleared = try c.decodeIfPresent(Bool.self, forKey: .cleared) ?? false
            additive = try c.decodeIfPresent(Bool.self, forKey: .additive) ?? false
        }
    }

    /// Also reads the plain list of earlier test builds, which never counts as cleared.
    /// One unreadable entry makes the whole list unreadable: taking over the rest would drop it.
    private static func load() -> Payload? {
        guard let data = store.data(forKey: key) else { return nil }
        if let payload = try? JSONDecoder().decode(Payload.self, from: data) { return payload }
        guard let list = try? JSONDecoder().decode([Favorite].self, from: data) else { return nil }
        return Payload(favorites: list, cleared: false, additive: false)
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
