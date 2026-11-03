import Foundation

enum LoopbackPacket {
    private static let device = Data([10, 7, 0, 0])
    private static let peer = Data([10, 7, 0, 1])

    /// Returns the packet as if `peer` had sent it to this device, or nil for anything that is not
    /// device-to-peer IPv4. Swapping the two addresses leaves the IP and TCP checksums valid.
    static func reflected(_ packet: Data) -> Data? {
        guard packet.count >= 20, packet[packet.startIndex] >> 4 == 4 else { return nil }
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
}
