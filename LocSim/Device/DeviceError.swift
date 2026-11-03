import Foundation

/// Technical error from the device layer. `message` is meant for the log;
/// `AppError` turns it into what the user sees.
struct DeviceError: LocalizedError {
    enum Kind {
        case pairingMissing
        case pairingInvalid
        case pairingLockdown
        case localTunnel
        case tunnel
        case notConnected
        case ddiQuery
        case ddiDownload
        case ddiInstall
        case locationService
        case setLocation
        case clearLocation
        case other
    }

    let kind: Kind
    let message: String

    init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    var errorDescription: String? { message }
}
