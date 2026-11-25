import Foundation

/// Technical error from the device layer. `message` is meant for the log;
/// `AppError` turns it into what the user sees.
struct DeviceError: LocalizedError {
    enum Kind {
        case pairingMissing
        case pairingInvalid
        case pairingLockdown
        /// The device's pairing service resets the connection instead of answering.
        case pairingRefused
        case localTunnel
        case otherVPN
        /// LocSim's VPN configuration does not exist yet; the user is told before iOS asks.
        case vpnNotice
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
        /// Writing a file failed because the device is full.
        case storage
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

    /// The device has no space left, as Foundation and URLSession report it.
    static func isOutOfSpace(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteOutOfSpaceError { return true }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOSPC) { return true }
        if let code = (error as? URLError)?.code, code == .cannotWriteToFile || code == .cannotCreateFile { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }
}
