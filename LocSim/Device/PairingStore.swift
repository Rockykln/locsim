import Foundation
import LocSimCore

/// Stores the imported RPPairing file. Files dropped into Documents are imported
/// on next access.
enum PairingStore {
    private static let fileName = "rppairing.plist"
    // Checked first; other .plist files with "pair" in the name follow, e.g. "rppairing (1).plist".
    private static let dropNames = ["rppairing.plist", "pairingFile.plist", "pairing.plist"]
    /// Set when a file dropped into Documents failed validation, so Settings can say why.
    private(set) static var rejectedDrop = false

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

    @discardableResult
    private static func adoptDroppedFile() -> Bool {
        for url in droppedFiles() {
            let data = try? read(url)
            var lockdown = false
            let valid = data.map { data in
                do {
                    try validate(data)
                    return true
                } catch {
                    lockdown = (error as? DeviceError)?.kind == .pairingLockdown
                    return false
                }
            } ?? false
            // The setup script may still be writing it over USB.
            if !valid, let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate, Date().timeIntervalSince(modified) < 5 {
                continue
            }
            if valid, let data {
                // Kept if it could not be stored, e.g. before the first unlock after a restart.
                guard (try? save(data)) != nil else { return false }
                // Dropped files are visible in Files and part of backups; never leave one behind.
                try? FileManager.default.removeItem(at: url)
                rejectedDrop = false
                return true
            }
            // Only a file the setup script wrote is ours to delete. Other names and lockdown
            // pairing files may be the user's own copy, kept for other tools.
            if dropNames.contains(url.lastPathComponent), !lockdown {
                try? FileManager.default.removeItem(at: url)
            }
            rejectedDrop = true
        }
        return false
    }

    private static func droppedFiles() -> [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let all = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        // Only files that look like a pairing file; other files the user keeps here are left alone.
        let plists = all.filter {
            $0.pathExtension.lowercased() == "plist" && $0.lastPathComponent.lowercased().contains("pair")
        }
        let known = dropNames.compactMap { name in plists.first { $0.lastPathComponent == name } }
        let others = plists.filter { !dropNames.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return known + others
    }
}
