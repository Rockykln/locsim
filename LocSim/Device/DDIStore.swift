import CryptoKit
import Foundation
import LocSimCore

extension DDIMethod {
    static var current: DDIMethod {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return method(major: v.majorVersion, minor: v.minorVersion)
    }
}

/// Downloads the DDI from doronz88/DeveloperDiskImage, pinned to a commit and
/// verified against known hashes.
enum DDIStore {
    private static let commit = "d2d3e18b695e0e0bec3051f13e7ca6e0a50241e9"
    private static let baseURL = URL(
        string: "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/\(commit)/PersonalizedImages")!

    static func directory(for method: DDIMethod) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DDI", isDirectory: true)
            .appendingPathComponent("\(commit.prefix(10))-\(method.rawValue)", isDirectory: true)
    }

    static func isDownloaded(_ method: DDIMethod) -> Bool {
        let dir = directory(for: method)
        return method.files.allSatisfy { size(of: dir.appendingPathComponent($0.name)) > 0 }
    }

    @MainActor
    static func prepare(_ method: DDIMethod, log: (String) -> Void) async throws -> URL {
        let dir = directory(for: method)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            // About 16 MB that can be downloaded again; keep it out of backups.
            var root = dir.deletingLastPathComponent()
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? root.setResourceValues(values)
        } catch {
            throw DeviceError(.ddiDownload, "Cannot create DDI folder: \(error.localizedDescription)")
        }

        for file in method.files {
            let target = dir.appendingPathComponent(file.name)
            if await verify(target, file.sha256) { continue }
            try? fm.removeItem(at: target)

            log("downloading \(file.name)")
            let (temp, response) = try await session.download(
                from: baseURL.appendingPathComponent("\(method.folder)/\(file.name)"))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, await verify(temp, file.sha256) else {
                try? fm.removeItem(at: temp)
                throw DeviceError(.ddiDownload, "DDI download failed or does not match: \(file.name) HTTP \(status)")
            }
            do {
                try fm.moveItem(at: temp, to: target)
            } catch {
                throw DeviceError(.ddiDownload, "Cannot store \(file.name): \(error.localizedDescription)")
            }
        }
        return dir
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    static func remove() {
        try? FileManager.default.removeItem(at: directory(for: .cryptex).deletingLastPathComponent())
    }

    // Hashing the image (about 16 MB) off the main actor keeps the UI responsive.
    private static func verify(_ url: URL, _ sha256: String) async -> Bool {
        await Task.detached(priority: .utility) { Self.matches(url, sha256) }.value
    }

    private static func matches(_ url: URL, _ sha256: String) -> Bool {
        guard size(of: url) > 0, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == sha256
    }

    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
