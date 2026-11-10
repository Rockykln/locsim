import Foundation
import LocSimCore

/// User-facing error with a stable code for support. `detail` keeps the
/// technical message from the device layer.
struct AppError: Error, Equatable {
    let code: String
    let title: String
    let message: String
    let detail: String

    static let clearFailedCode = "LS-402"
    static let otherVPNCode = "LS-207"
    static let ddiConsentCode = "LS-303"

    /// The device or the file itself refuses the pairing, as opposed to not being reachable.
    var rejectsPairing: Bool { ["LS-100", "LS-101", "LS-102", "LS-203"].contains(code) }

    init(_ error: Error) {
        let detail = error.localizedDescription
        let kind: DeviceError.Kind = (error as? DeviceError)?.kind ?? (error is URLError ? .ddiDownload : .other)
        let entry = Self.entry(for: kind, error: error as? DeviceError, detail: detail)
        code = entry.code
        title = entry.title
        message = entry.message
        self.detail = detail
    }

    /// Title, message and code in one line, e.g. for a footer.
    var summary: String { String(localized: "\(title): \(message) (\(code))") }

    /// Message followed by the code, for places that already show the title.
    var messageWithCode: String { String(localized: "\(message) (\(code))") }

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

    private static func entry(for kind: DeviceError.Kind, error: DeviceError?, detail: String) -> Entry {
        switch kind {
        case .pairingMissing:
            return ("LS-100", String(localized: "No pairing file"),
                    String(localized: "Run the setup script, or import a pairing file in LocSim's settings under Pairing."))
        case .pairingInvalid:
            return ("LS-101", String(localized: "Pairing file not valid"),
                    String(localized: "The file could not be read. Create a new one with the setup script."))
        case .pairingLockdown:
            return ("LS-102", String(localized: "Wrong pairing file"),
                    String(localized: "This is a lockdown pairing file. LocSim needs the RPPairing file from the setup script."))
        case .pairingRefused:
            return rejectedEntry
        case .localTunnel:
            return ("LS-205", String(localized: "Local connection not started"),
                    String(localized: "LocSim could not start its connection to this iPhone. Allow the VPN configuration when iOS asks and try again."))
        case .otherVPN:
            return (otherVPNCode, String(localized: "Another VPN is selected"),
                    String(localized: "LocSim's local connection replaces it while a location is active. Tap Set Location again to continue, and select your VPN again in Settings afterwards."))
        case .localNetwork:
            return ("LS-208", String(localized: "Local Network access off"),
                    String(localized: "Allow Local Network for LocSim under Settings > Privacy & Security > Local Network, then try again."))
        case .tunnel:
            return tunnelEntry(error, detail: detail)
        case .notConnected:
            return ("LS-204", String(localized: "Connection lost"),
                    String(localized: "The connection to the device closed. Check Wi-Fi. LocSim reconnects on its own while a location is active."))
        case .ddiQuery:
            return ("LS-300", String(localized: "Developer Disk Image not available"),
                    String(localized: "The disk image state could not be read. Check that Developer Mode is on."))
        case .ddiConsent:
            return (ddiConsentCode, String(localized: "Developer Disk Image needed"),
                    String(localized: "iOS has not provided it. LocSim can download it from GitHub, about 16 MB."))
        case .ddiDownload:
            return ("LS-301", String(localized: "Download failed"),
                    String(localized: "The Developer Disk Image could not be downloaded. Check the internet connection."))
        case .ddiInstall:
            return ("LS-302", String(localized: "Developer Disk Image not installed"),
                    String(localized: "Installing the disk image failed. It needs an internet connection; try again."))
        case .locationService:
            return ("LS-400", String(localized: "Location service unavailable"),
                    String(localized: "The device did not provide location simulation. Turn on Mount Automatically in LocSim's settings under Developer Disk Image, or restart the device."))
        case .setLocation:
            return ("LS-401", String(localized: "Location not set"),
                    String(localized: "Sending the location failed. Tap Set Location to try again."))
        case .clearLocation:
            return (clearFailedCode, String(localized: "Location not cleared"),
                    String(localized: "Quit LocSim in the App Switcher to restore the real location."))
        case .other:
            return ("LS-900", String(localized: "Unexpected error"),
                    String(localized: "Copy the details and include them in a support request."))
        }
    }

    private static func tunnelEntry(_ error: DeviceError?, detail: String) -> Entry {
        switch TunnelFailure.classify(code: error?.code, subCode: error?.subCode, message: detail) {
        case .rejected:
            return rejectedEntry
        case .timeout:
            return ("LS-201", String(localized: "Device not reachable"),
                    String(localized: "Join a Wi-Fi network and try again."))
        case .unavailable:
            return ("LS-202", String(localized: "Pairing service unavailable"),
                    String(localized: "Join a Wi-Fi network. If it keeps failing, enable Show this iPhone when on Wi-Fi in Finder. Also allow Local Network for LocSim under Settings > Privacy & Security > Local Network."))
        case .other:
            return ("LS-206", String(localized: "Connection failed"),
                    String(localized: "The connection to the device broke off. Check Wi-Fi and try again."))
        }
    }

    private static var rejectedEntry: Entry {
        ("LS-203", String(localized: "Pairing rejected"),
         String(localized: "The device did not accept the pairing file. Check that the hostname in LocSim's settings matches the one used by the setup script, or create a new file, for example after an iOS update."))
    }
}
