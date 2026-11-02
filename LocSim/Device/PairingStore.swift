import Foundation

/// Stores the imported RPPairing file. Files dropped into Documents are imported
/// on next access.
enum PairingStore {
    private static let fileName = "rppairing.plist"
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

    private static let maxSize = 64 * 1024

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
    }

    private static func validate(_ data: Data) throws {
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = plist as? [String: Any] else {
            throw DeviceError(.pairingInvalid, "Not a property list")
        }
        guard dict["private_key"] is Data, dict["public_key"] is Data else {
            if dict["HostPrivateKey"] != nil {
                throw DeviceError(.pairingLockdown, "Lockdown pairing file instead of RPPairing")
            }
            throw DeviceError(.pairingInvalid, "Missing public_key/private_key")
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

    private static func adoptDroppedFile() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in dropNames {
            let url = docs.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            // Dropped files are visible in Files and part of backups; never leave one behind.
            defer { try? FileManager.default.removeItem(at: url) }
            if let data = try? read(url), (try? validate(data)) != nil {
                try? save(data)
                rejectedDrop = false
                return
            }
            rejectedDrop = true
        }
    }
}
