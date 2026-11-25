import CryptoKit
import Foundation
import IDevice
import LocSimCore

/// Stores the imported RPPairing file. Files dropped into Documents are imported by `adoptNow()`,
/// whose caller handles a replaced file, and when a connection starts.
enum PairingStore {
    private static let fileName = "rppairing.plist"
    // The name the setup script writes; only this file is ever deleted. Other .plist files with
    // "pair" in the name (e.g. "rppairing (1).plist", another tool's "pairingFile.plist") are
    // imported but kept.
    private static let dropNames = ["rppairing.plist"]
    /// Set when a setup script file in Documents was not a pairing file and has been removed.
    private(set) static var rejectedDrop = false
    /// A lockdown pairing file (not RPPairing) is in Documents. It is never deleted.
    private(set) static var lockdownDrop = false

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(fileName)
    }

    /// Only looks; a dropped file is not taken in here, so a replaced file is never missed.
    static var exists: Bool {
        FileManager.default.fileExists(atPath: storeURL.path)
    }

    /// Pairing files left in LocSim's folder in Files: the user's own copies and lockdown files.
    /// They are part of device backups and hold a key for this device, so the user is told.
    static var copiesInDocuments: [String] {
        droppedFiles().map { $0.0.lastPathComponent }
    }

    /// A file in Documents that may be a pairing file and was not imported yet. Files already
    /// found to be lockdown or not valid do not count: they would make LocSim look set up.
    static var hasDroppedFile: Bool {
        let seen = UserDefaults.standard.dictionary(forKey: importedKey) as? [String: Double] ?? [:]
        let lockdown = UserDefaults.standard.dictionary(forKey: lockdownKey) as? [String: Double] ?? [:]
        let invalid = UserDefaults.standard.dictionary(forKey: invalidKey) as? [String: Double] ?? [:]
        return droppedFiles().contains { url, modified in
            let name = url.lastPathComponent
            let stamp = modified?.timeIntervalSince1970 ?? 0
            if lockdown[name] == stamp || invalid[name] == stamp { return false }
            return dropNames.contains(name) || seen[name] != stamp
        }
    }

    /// Imports a dropped file and reports whether one replaced or added the stored file.
    @discardableResult
    static func adoptNow() -> Bool {
        adoptDroppedFile()
    }

    static func clearRejection() {
        rejectedDrop = false
    }

    static func load() throws -> Data {
        guard let data = try? Data(contentsOf: storeURL) else {
            // Only a lockdown file was copied in: say that, not "no pairing file".
            if lockdownDrop { throw DeviceError(.pairingLockdown, "Only a lockdown pairing file in Documents") }
            throw DeviceError(.pairingMissing, "No pairing file imported")
        }
        var url = storeURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return data
    }

    /// Returns whether the stored file changed; the same file again keeps the connection.
    @discardableResult
    static func importFile(at url: URL) throws -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try read(url)
        try validate(data)
        rejectedDrop = false
        if (try? Data(contentsOf: storeURL)) == data { return false }
        try save(data)
        noteImported(data)
        return true
    }

    private static let maxSize = PairingFileCheck.maxSize

    private static func read(_ url: URL) throws -> Data {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxSize else { throw DeviceError(.pairingInvalid, "File too large for a pairing file") }
        let data: Data
        do {
            // Read with a bound too: the size above may be unknown, e.g. for a file in iCloud Drive.
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maxSize + 1) ?? Data()
        } catch {
            throw DeviceError(.pairingInvalid, "Cannot read file: \(error.localizedDescription)")
        }
        guard data.count <= maxSize else { throw DeviceError(.pairingInvalid, "File too large for a pairing file") }
        return data
    }

    static func remove() {
        try? FileManager.default.removeItem(at: storeURL)
        rejectedDrop = false
    }

    private static func validate(_ data: Data) throws {
        switch check(data) {
        case .valid: return
        case .lockdown: throw DeviceError(.pairingLockdown, "Lockdown pairing file instead of RPPairing")
        case .invalid(let reason): throw DeviceError(.pairingInvalid, reason)
        }
    }

    /// The quick check, then idevice's own parser, the one connecting uses: a file only the quick
    /// check accepts would replace a working one and fail later.
    private static func check(_ data: Data) -> PairingFileCheck {
        let result = PairingFileCheck.check(data)
        guard case .valid = result else { return result }
        var handle: OpaquePointer?
        let err = data.withUnsafeBytes { raw in
            rp_pairing_file_from_bytes(raw.bindMemory(to: UInt8.self).baseAddress, UInt(raw.count), &handle)
        }
        rp_pairing_file_free(handle)
        guard let err else { return .valid }
        let message = err.pointee.message.map { String(cString: $0) } ?? "unknown error"
        idevice_error_free(err)
        return .invalid("Not readable as RPPairing file: \(message)")
    }

    /// Hashes of files taken from Documents, so a renamed or moved old copy is not imported again
    /// over the current file. Only the hash is kept, not the file.
    private static func noteImported(_ data: Data) {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var hashes = UserDefaults.standard.stringArray(forKey: hashesKey) ?? []
        hashes.removeAll { $0 == hash }
        hashes.append(hash)
        UserDefaults.standard.set(Array(hashes.suffix(20)), forKey: hashesKey)
    }

    private static func wasImported(_ data: Data) -> Bool {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (UserDefaults.standard.stringArray(forKey: hashesKey) ?? []).contains(hash)
    }

    // Readable after first unlock because resends reconnect while the device is locked.
    // Excluded from backups so the key never leaves the device.
    private static func save(_ data: Data) throws {
        var url = storeURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            let kind: DeviceError.Kind = DeviceError.isOutOfSpace(error) ? .storage : .pairingInvalid
            throw DeviceError(kind, "Cannot store pairing file: \(error.localizedDescription)")
        }
    }

    /// Rule: the newest valid candidate is imported, at most one per pass. Setup script files
    /// (`dropNames`) are deleted once imported, or when they were read and are not a pairing file
    /// at all. Other `*pair*.plist` files may be the user's own copies: they are imported once
    /// (per content, so renaming an old copy does not bring it back) and left in place. Lockdown
    /// files and unreadable files are never deleted; once checked, they no longer count as new.
    @discardableResult
    private static func adoptDroppedFile() -> Bool {
        let files = droppedFiles()
        let present = Set(files.map { $0.0.lastPathComponent })
        func current(_ key: String) -> [String: Double] {
            (UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]).filter { present.contains($0.key) }
        }
        let stored = UserDefaults.standard.dictionary(forKey: importedKey) as? [String: Double] ?? [:]
        var seen = current(importedKey)
        let storedLockdown = UserDefaults.standard.dictionary(forKey: lockdownKey) as? [String: Double] ?? [:]
        var lockdown = current(lockdownKey)
        let storedInvalid = UserDefaults.standard.dictionary(forKey: invalidKey) as? [String: Double] ?? [:]
        var invalid = current(invalidKey)
        var lockdownFound = false
        var adopted = false
        var replaced = false
        for (url, modified) in files {
            let name = url.lastPathComponent
            let ours = dropNames.contains(name)
            let stamp = modified?.timeIntervalSince1970 ?? 0
            if !ours, seen[name] == stamp { continue }
            if lockdown[name] == stamp {
                lockdownFound = true
                continue
            }
            if invalid[name] == stamp { continue }
            // Unreadable (e.g. data protection before the first unlock): keep it and retry later.
            guard let data = try? read(url) else { continue }
            switch check(data) {
            case .valid:
                // A copy of a file imported before, e.g. renamed in Files, is not the user's new choice
                // over the current file. Without a stored file, e.g. after Remove, it is taken in.
                if !ours, wasImported(data), let current = try? Data(contentsOf: storeURL), current != data {
                    seen[name] = stamp
                    continue
                }
                if !adopted {
                    if (try? Data(contentsOf: storeURL)) != data {
                        // Kept if it could not be stored, e.g. before the first unlock after a restart.
                        guard (try? save(data)) != nil else { break }
                        noteImported(data)
                        replaced = true
                    }
                    adopted = true
                    rejectedDrop = false
                }
                // Older valid files are retired too, so a later pass never imports them over this one.
                if ours {
                    // Dropped files are visible in Files and part of backups; never leave one behind.
                    try? FileManager.default.removeItem(at: url)
                } else {
                    seen[name] = stamp
                }
            case .lockdown:
                lockdownFound = true
                lockdown[name] = stamp
            case .invalid:
                // The setup script may still be writing it over USB.
                if let modified, Date().timeIntervalSince(modified) < 5 { continue }
                if ours, (try? FileManager.default.removeItem(at: url)) != nil {
                    rejectedDrop = true
                } else {
                    invalid[name] = stamp
                }
            }
        }
        lockdownDrop = lockdownFound
        if seen != stored { UserDefaults.standard.set(seen, forKey: importedKey) }
        if lockdown != storedLockdown { UserDefaults.standard.set(lockdown, forKey: lockdownKey) }
        if invalid != storedInvalid { UserDefaults.standard.set(invalid, forKey: invalidKey) }
        return replaced
    }

    // Newest first; on equal dates the setup script names come first.
    private static func droppedFiles() -> [(URL, Date?)] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let all = (try? FileManager.default.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        // Only files that look like a pairing file; other files the user keeps here are left alone.
        let plists = all.filter {
            $0.pathExtension.lowercased() == "plist" && $0.lastPathComponent.lowercased().contains("pair")
        }
        let dated = plists.map { url in
            (url, try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        }
        func rank(_ url: URL) -> Int { dropNames.firstIndex(of: url.lastPathComponent) ?? dropNames.count }
        return dated.sorted { a, b in
            let da = a.1 ?? .distantPast, db = b.1 ?? .distantPast
            if da != db { return da > db }
            if rank(a.0) != rank(b.0) { return rank(a.0) < rank(b.0) }
            return a.0.lastPathComponent < b.0.lastPathComponent
        }
    }

    // Name to modification date of other-named files already imported, so a later pass does not
    // import them again over the user's later choice.
    private static let importedKey = "pairing.importedDrops"
    // Name to modification date of files found to be lockdown or not valid.
    private static let lockdownKey = "pairing.lockdownDrops"
    private static let invalidKey = "pairing.invalidDrops"
    private static let hashesKey = "pairing.importedHashes"
}
