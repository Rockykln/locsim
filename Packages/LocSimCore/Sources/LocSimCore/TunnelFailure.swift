import Foundation

/// What a failed RPPairing tunnel says about the cause, from idevice's error code and message.
public enum TunnelFailure: Equatable, Sendable {
    /// The device refused the keys: wrong hostname or an outdated pairing file.
    case rejected
    case timeout
    /// Nothing answered on the port, or the network refused the connection.
    case unavailable
    case other

    // idevice codes: 1 socket, 103 remote pairing (sub codes 3, 5 and 6 refuse the keys),
    // 109 timeout. Connection errors arrive as text, so those are still matched by message.
    public static func classify(code: Int32?, subCode: Int32?, message: String) -> TunnelFailure {
        let text = message.lowercased()
        if code == 103, let subCode, [3, 5, 6].contains(subCode) { return .rejected }
        if code == 109 || text.contains("timeout") || text.contains("timed out") { return .timeout }
        if code == 1 || text.contains("socket io") || text.contains("refused") || text.contains("unreachable")
            || text.range(of: #"(^|[^a-z])connect:"#, options: .regularExpression) != nil {
            return .unavailable
        }
        if text.contains("pairingrejected") || text.contains("pairverifyfailed") || text.contains("srpauthfailed") {
            return .rejected
        }
        return .other
    }
}
