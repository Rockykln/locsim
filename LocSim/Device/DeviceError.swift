import Foundation

/// Technical error from the device layer. `message` is meant for the log;
/// `AppError` turns it into what the user sees.
struct DeviceError: LocalizedError {
    enum Kind {
        case pairingMissing
        case pairingInvalid
        case pairingLockdown
        case localTunnel
        case otherVPN
        case localNetwork
        case tunnel
        case notConnected
        case ddiQuery
        case ddiConsent
        case ddiDownload
        case ddiInstall
        case locationService
        case setLocation
        case clearLocation
        case other
    }

    let kind: Kind
    let message: String
    /// idevice's error code and sub code, when the error came from the library.
    let code: Int32?
    let subCode: Int32?

    init(_ kind: Kind, _ message: String, code: Int32? = nil, subCode: Int32? = nil) {
        self.kind = kind
        self.message = message
        self.code = code
        self.subCode = subCode
    }

    var errorDescription: String? { message }
}
