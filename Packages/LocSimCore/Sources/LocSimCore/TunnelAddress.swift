import Foundation

/// Fixed addresses of the local tunnel. iOS only delivers traffic from an app to this device's
/// own services when it arrives from another address, so `peer` stands in for that sender.
public enum TunnelAddress {
    public static let device = "10.7.0.0"
    public static let peer = "10.7.0.1"
    /// Only the peer is routed into the tunnel, so a network that uses 10.7.0.x stays reachable.
    public static let hostMask = "255.255.255.255"
    /// Message the app sends while it needs the tunnel; the extension stops once it no longer arrives.
    public static let heartbeat = Data("alive".utf8)
    /// Longer than the default resend interval, so a resend carries the beat and the timer rarely fires.
    /// Interval plus tolerance stays 30 s inside the timeout.
    public static let heartbeatInterval: TimeInterval = 85
    public static let heartbeatTolerance: TimeInterval = 5
    public static let heartbeatTimeout: TimeInterval = 120
}
