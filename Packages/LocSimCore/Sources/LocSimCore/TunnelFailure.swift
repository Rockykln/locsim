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

    /// A device that does not accept the keys often gives no answer but resets the connection.
    public static func isReset(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("connectionreset") || text.contains("connection reset")
    }

    /// The device's own pairing service was found, and every port it offers reset the connection:
    /// the network is fine, the device refuses the pairing. A port that was not tried, or failed in
    /// another way, keeps the usual message.
    public static func refusedSilently(localPorts: Set<UInt16>, resetPorts: Set<UInt16>) -> Bool {
        !localPorts.isEmpty && localPorts.isSubset(of: resetPorts)
    }
}
