import Foundation

/// A `_remotepairing._tcp` service found by Bonjour.
public struct PairingService: Equatable, Sendable {
    public let name: String
    public let port: UInt16
    public let addresses: [String]
    public let isLocal: Bool

    public init(name: String, port: UInt16, addresses: [String], isLocal: Bool) {
        self.name = name
        self.port = port
        self.addresses = addresses
        self.isLocal = isLocal
    }
}

public enum PairingPorts {
    public static let fallback: UInt16 = 49152

    /// Other devices on the network advertise the service too: local ports first, at most
    /// two from other devices, then the usual default.
    public static func candidates(_ services: [PairingService]) -> [UInt16] {
        var ports: [UInt16] = []
        let remote = services.filter { !$0.isLocal }.prefix(2)
        for service in services.filter(\.isLocal) + remote where !ports.contains(service.port) {
            ports.append(service.port)
        }
        if !ports.contains(fallback) { ports.append(fallback) }
        return ports
    }

    /// The port typed in Settings, or nil for automatic or anything that is not a port.
    public static func manual(_ text: String) -> UInt16? {
        UInt16(text.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
    }
}
