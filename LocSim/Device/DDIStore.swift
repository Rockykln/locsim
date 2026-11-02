import CryptoKit
import Foundation

enum DDIMethod: String {
    case cryptex
    case personalized

    /// iOS 26.4 and later install the DDI as a cryptex through cryptexd.
    static var current: DDIMethod {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion > 26 || (v.majorVersion == 26 && v.minorVersion >= 4) ? .cryptex : .personalized
    }

    var folder: String {
        switch self {
        case .cryptex: return "Xcode_iOS_DDI_Cryptex"
        case .personalized: return "Xcode_iOS_DDI_Personalized"
        }
    }

    /// File names with their SHA-256 at the pinned commit.
    var files: [(name: String, sha256: String)] {
        switch self {
        case .cryptex:
            return [
                ("BuildManifest.plist", "27385d7582b03b36bb3104e22b520aee0c47d72fecb4e8ecfe12ef5d966c7012"),
                ("Image.dmg", "873097f695a8b9734e2abc54f795a8874d40ff6fd11208ecb01ef29534c7c176"),
                ("Image.dmg.trustcache", "f7f21986074eee03a215aca16ecfc78d6bf183600d8a0d2fb691f9896782e6f0"),
                ("Image.dmg.cryptex_info", "edf49aef55aacc063d4d7be05b713bb545ce2993b3f62bcc15eccd75e610ee6c"),
                ("Image.dmg.root_hash", "3543fad2805b88119695c417e12679380b3b5a2742994bbcc839c8e2de5d7302"),
            ]
        case .personalized:
            return [
                ("BuildManifest.plist", "8edd4a2f4f4ef1fbd7bfe49785d8badc673d1395d1d94d85b132ca8ab5ecaf54"),
                ("Image.dmg", "05fd807da5e19f030fa4941f24800c965c6c77982ab572dd5d1ef778fb69f9ca"),
                ("Image.dmg.trustcache", "36af60889ff5a737874a26daeb8e1a0139ebfebec6ec2e4d8f6a3c1bf1dce35c"),
            ]
        }
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
        } catch {
            throw DeviceError(.ddiDownload, "Cannot create DDI folder: \(error.localizedDescription)")
        }

        for file in method.files {
            let target = dir.appendingPathComponent(file.name)
            if await verify(target, file.sha256) { continue }
            try? fm.removeItem(at: target)

            log("downloading \(file.name)")
            let (temp, response) = try await URLSession.shared.download(
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
