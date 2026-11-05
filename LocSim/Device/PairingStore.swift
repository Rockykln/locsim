import Foundation
import LocSimCore

/// Stores the imported RPPairing file. Files dropped into Documents are imported
/// on next access.
enum PairingStore {
    private static let fileName = "rppairing.plist"
    // Names the setup script writes; only these are ever deleted. Other .plist files with "pair"
    // in the name (e.g. "rppairing (1).plist") are imported but kept.
    private static let dropNames = ["rppairing.plist", "pairingFile.plist", "pairing.plist"]
    /// Set when a setup script file in Documents was not a pairing file and has been removed.
    private(set) static var rejectedDrop = false
    /// A lockdown pairing file (not RPPairing) is in Documents. It is never deleted.
    private(set) static var lockdownDrop = false

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(fileName)
    }

    static var exists: Bool {
        adoptDroppedFile()
        return FileManager.default.fileExists(atPath: storeURL.path)
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
        adoptDroppedFile()
        guard let data = try? Data(contentsOf: storeURL) else {
            throw DeviceError(.pairingMissing, "No pairing file imported")
        }
        var url = storeURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return data
    }

    static func importFile(at url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try read(url)
        try validate(data)
        try save(data)
        rejectedDrop = false
    }

    private static let maxSize = PairingFileCheck.maxSize

    private static func read(_ url: URL) throws -> Data {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxSize else { throw DeviceError(.pairingInvalid, "File too large for a pairing file") }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw DeviceError(.pairingInvalid, "Cannot read file: \(error.localizedDescription)")
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: storeURL)
        rejectedDrop = false
    }

    private static func validate(_ data: Data) throws {
        switch PairingFileCheck.check(data) {
        case .valid: return
        case .lockdown: throw DeviceError(.pairingLockdown, "Lockdown pairing file instead of RPPairing")
        case .invalid(let reason): throw DeviceError(.pairingInvalid, reason)
        }
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
            throw DeviceError(.pairingInvalid, "Cannot store pairing file: \(error.localizedDescription)")
        }
    }

    /// Rule: the newest valid candidate is imported, at most one per pass. Setup script files
    /// (`dropNames`) are deleted once imported, or when they were read and are not a pairing file
    /// at all. Other `*pair*.plist` files may be the user's own copies: they are imported once
    /// (per modification date) and left in place. Lockdown files and unreadable files are never
    /// deleted.
    @discardableResult
    private static func adoptDroppedFile() -> Bool {
        let files = droppedFiles()
        let stored = UserDefaults.standard.dictionary(forKey: importedKey) as? [String: Double] ?? [:]
        let present = Set(files.map { $0.0.lastPathComponent })
        var seen = stored.filter { present.contains($0.key) }
        var lockdownFound = false
        var adopted = false
        var replaced = false
        for (url, modified) in files {
            let name = url.lastPathComponent
            let ours = dropNames.contains(name)
            let stamp = modified?.timeIntervalSince1970 ?? 0
            if !ours, seen[name] == stamp { continue }
            // Unreadable (e.g. data protection before the first unlock): keep it and retry later.
            guard let data = try? read(url) else { continue }
            switch PairingFileCheck.check(data) {
            case .valid:
                if !adopted {
                    if (try? Data(contentsOf: storeURL)) != data {
                        // Kept if it could not be stored, e.g. before the first unlock after a restart.
                        guard (try? save(data)) != nil else { break }
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
            case .invalid:
                // The setup script may still be writing it over USB.
                if let modified, Date().timeIntervalSince(modified) < 5 { continue }
                if ours, (try? FileManager.default.removeItem(at: url)) != nil {
                    rejectedDrop = true
                }
            }
        }
        lockdownDrop = lockdownFound
        if seen != stored { UserDefaults.standard.set(seen, forKey: importedKey) }
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
}
