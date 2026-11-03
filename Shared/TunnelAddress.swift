/// Fixed addresses of the local tunnel. iOS only delivers traffic from an app to this device's
/// own services when it arrives from another address, so `peer` stands in for that sender.
enum TunnelAddress {
    static let device = "10.7.0.0"
    static let peer = "10.7.0.1"
    static let subnetMask = "255.255.255.0"
}
