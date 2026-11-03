import Foundation

public enum PairingFileCheck: Equatable, Sendable {
    case valid
    /// A lockdown pairing file (HostPrivateKey) instead of an RPPairing file.
    case lockdown
    case invalid(String)

    public static let maxSize = 64 * 1024

    public static func check(_ data: Data) -> PairingFileCheck {
        guard data.count <= maxSize else { return .invalid("File too large for a pairing file") }
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = plist as? [String: Any] else { return .invalid("Not a property list") }
        if dict["private_key"] is Data, dict["public_key"] is Data { return .valid }
        if dict["HostPrivateKey"] != nil { return .lockdown }
        return .invalid("Missing public_key/private_key")
    }
}
