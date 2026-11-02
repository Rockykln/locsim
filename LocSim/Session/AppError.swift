import Foundation

/// User-facing error with a stable code for support. `detail` keeps the
/// technical message from the device layer.
struct AppError: Error, Equatable {
    let code: String
    let title: String
    let message: String
    let detail: String

    static let clearFailedCode = "LS-402"

    /// The device or the file itself refuses the pairing, as opposed to not being reachable.
    var rejectsPairing: Bool { ["LS-100", "LS-101", "LS-102", "LS-203"].contains(code) }

    init(_ error: Error) {
        let detail = error.localizedDescription
        let kind: DeviceError.Kind = (error as? DeviceError)?.kind ?? (error is URLError ? .ddiDownload : .other)
        let entry = Self.entry(for: kind, detail: detail)
        code = entry.code
        title = entry.title
        message = entry.message
        self.detail = detail
    }

    /// Text for the clipboard, so a support request contains everything needed.
    var report: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return """
            \(code) \(title)
            \(detail)
            LocSim \(version) (\(build)) \(AppLinks.commit), iOS \(os)
            """
    }

    private typealias Entry = (code: String, title: String, message: String)

    private static func entry(for kind: DeviceError.Kind, detail: String) -> Entry {
        switch kind {
        case .pairingMissing:
            return ("LS-100", String(localized: "No pairing file"),
                    String(localized: "Import a pairing file under Settings > Pairing."))
        case .pairingInvalid:
            return ("LS-101", String(localized: "Pairing file not valid"),
                    String(localized: "The file could not be read. Create a new one with tools/make-pairing.sh."))
        case .pairingLockdown:
            return ("LS-102", String(localized: "Wrong pairing file"),
                    String(localized: "This is a lockdown pairing file. LocSim needs an RPPairing file from tools/make-pairing.sh."))
        case .invalidHost:
            return ("LS-200", String(localized: "Invalid target address"),
                    String(localized: "Check the target IP under Settings > Connection. The default is 10.7.0.1."))
        case .tunnel:
            return tunnelEntry(detail)
        case .notConnected:
            return ("LS-204", String(localized: "Connection lost"),
                    String(localized: "The connection to the device closed. Check LocalDevVPN and Wi-Fi. LocSim reconnects on its own while a location is active."))
        case .ddiQuery:
            return ("LS-300", String(localized: "Developer Disk Image not available"),
                    String(localized: "The disk image state could not be read. Check that Developer Mode is on."))
        case .ddiDownload:
            return ("LS-301", String(localized: "Download failed"),
                    String(localized: "The Developer Disk Image could not be downloaded. Check the internet connection."))
        case .ddiInstall:
            return ("LS-302", String(localized: "Developer Disk Image not installed"),
                    String(localized: "Installing the disk image failed. It needs an internet connection; try again."))
        case .locationService:
            return ("LS-400", String(localized: "Location service unavailable"),
                    String(localized: "The device did not provide location simulation. Turn on Mount Automatically under Settings, or restart the device."))
        case .setLocation:
            return ("LS-401", String(localized: "Location not set"),
                    String(localized: "Sending the location failed. Tap Set Location to try again."))
        case .clearLocation:
            return (clearFailedCode, String(localized: "Location not cleared"),
                    String(localized: "Close LocSim to restore the real location."))
        case .other:
            return ("LS-900", String(localized: "Unexpected error"),
                    String(localized: "Copy the details and include them in a support request."))
        }
    }

    private static func tunnelEntry(_ detail: String) -> Entry {
        let text = detail.lowercased()
        if text.contains("timeout") || text.contains("timed out") {
            return ("LS-201", String(localized: "Device not reachable"),
                    String(localized: "Connect LocalDevVPN and try again."))
        }
        if text.contains("socket io") || text.contains("refused") || text.contains("unreachable") {
            return ("LS-202", String(localized: "Pairing service unavailable"),
                    String(localized: "Check that LocalDevVPN is connected and join a Wi-Fi network. If it keeps failing, enable Show this iPhone when on Wi-Fi in Finder. Also allow Local Network for LocSim under Settings > Privacy & Security > Local Network."))
        }
        return ("LS-203", String(localized: "Pairing rejected"),
                String(localized: "The device did not accept the pairing file. Create a new one, for example after an iOS update."))
    }
}
