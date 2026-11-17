import Foundation

public enum LoopbackPacket {
    private static let device = bytes(TunnelAddress.device)
    private static let peer = bytes(TunnelAddress.peer)

    private static let tcp: UInt8 = 6

    /// Returns the packet as if `peer` had sent it to this device, or nil for anything that is not
    /// device-to-peer IPv4 TCP. Swapping the two addresses leaves the IP and TCP checksums valid.
    /// The developer services are reached over TCP only, so nothing else is passed back.
    public static func reflected(_ packet: Data) -> Data? {
        guard packet.count >= 20, packet[packet.startIndex] >> 4 == 4,
              packet[packet.startIndex + 9] == tcp else { return nil }
        let source = packet.startIndex + 12
        let destination = packet.startIndex + 16
        guard packet[source..<source + 4] == device, packet[destination..<destination + 4] == peer else {
            return nil
        }
        var result = packet
        result.replaceSubrange(source..<source + 4, with: peer)
        result.replaceSubrange(destination..<destination + 4, with: device)
        return result
    }

    private static func bytes(_ address: String) -> Data {
        Data(address.split(separator: ".").compactMap { UInt8($0) })
    }
}
