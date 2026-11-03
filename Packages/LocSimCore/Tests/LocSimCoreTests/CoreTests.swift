import Foundation
import XCTest
@testable import LocSimCore

final class LoopbackPacketTests: XCTestCase {
    private func packet(from source: [UInt8], to destination: [UInt8]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 28)
        bytes[0] = 0x45
        bytes.replaceSubrange(12..<16, with: source)
        bytes.replaceSubrange(16..<20, with: destination)
        for i in 20..<28 { bytes[i] = UInt8(i) }
        return Data(bytes)
    }

    func testSwapsAddresses() throws {
        let reflected = try XCTUnwrap(LoopbackPacket.reflected(packet(from: [10, 7, 0, 0], to: [10, 7, 0, 1])))
        XCTAssertEqual(reflected, packet(from: [10, 7, 0, 1], to: [10, 7, 0, 0]))
    }

    func testIgnoresOtherPackets() {
        XCTAssertNil(LoopbackPacket.reflected(packet(from: [10, 7, 0, 5], to: [10, 7, 0, 1])))
        XCTAssertNil(LoopbackPacket.reflected(packet(from: [10, 7, 0, 0], to: [8, 8, 8, 8])))
        XCTAssertNil(LoopbackPacket.reflected(Data(repeating: 0x45, count: 19)))
        var v6 = packet(from: [10, 7, 0, 0], to: [10, 7, 0, 1])
        v6[0] = 0x60
        XCTAssertNil(LoopbackPacket.reflected(v6))
    }

    func testSliceWithOffset() throws {
        let full = Data([0xFF, 0xFF]) + packet(from: [10, 7, 0, 0], to: [10, 7, 0, 1])
        let slice = full[2...]
        XCTAssertNotEqual(slice.startIndex, 0)
        let reflected = try XCTUnwrap(LoopbackPacket.reflected(slice))
        XCTAssertEqual(Data(reflected), packet(from: [10, 7, 0, 1], to: [10, 7, 0, 0]))
    }
}

final class PairingPortsTests: XCTestCase {
    private func service(_ port: UInt16, local: Bool) -> PairingService {
        PairingService(name: "s\(port)", port: port, addresses: [], isLocal: local)
    }

    func testCandidates() {
        XCTAssertEqual(PairingPorts.candidates([]), [49152])
        let services = [service(1, local: false), service(50000, local: true), service(2, local: false),
                        service(3, local: false)]
        XCTAssertEqual(PairingPorts.candidates(services), [50000, 1, 2, 49152])
        XCTAssertEqual(PairingPorts.candidates([service(49152, local: true)]), [49152])
    }

    func testManualPort() {
        XCTAssertEqual(PairingPorts.manual("50123"), 50123)
        XCTAssertEqual(PairingPorts.manual(" 50123 "), 50123)
        for text in ["", "0", "70000", "abc", "-1"] { XCTAssertNil(PairingPorts.manual(text), text) }
    }
}

final class ResendPolicyTests: XCTestCase {
    func testBackoff() {
        XCTAssertEqual((0...5).map { ResendPolicy.delay(base: 10, failures: $0) }, [10, 20, 40, 60, 60, 60])
        XCTAssertEqual(ResendPolicy.delay(base: 30, failures: 1), 60)
        XCTAssertEqual(ResendPolicy.delay(base: 1, failures: 0), 3)
    }
}

final class TunnelFailureTests: XCTestCase {
    func testCodes() {
        XCTAssertEqual(TunnelFailure.classify(code: 103, subCode: 5, message: ""), .rejected)
        XCTAssertEqual(TunnelFailure.classify(code: 103, subCode: 1, message: "RemotePairing(UnknownTlv(4))"), .other)
        XCTAssertEqual(TunnelFailure.classify(code: 109, subCode: 0, message: ""), .timeout)
        XCTAssertEqual(TunnelFailure.classify(code: 1, subCode: 0, message: ""), .unavailable)
    }

    func testMessages() {
        XCTAssertEqual(TunnelFailure.classify(code: 16, subCode: 0, message: "InternalError(\"connect: Connection refused\")"), .unavailable)
        XCTAssertEqual(TunnelFailure.classify(code: nil, subCode: nil, message: "operation timed out"), .timeout)
        XCTAssertEqual(TunnelFailure.classify(code: nil, subCode: nil, message: "RemotePairing(PairVerifyFailed)"), .rejected)
        XCTAssertEqual(TunnelFailure.classify(code: nil, subCode: nil, message: "connection reset by peer"), .other)
        XCTAssertEqual(TunnelFailure.classify(code: nil, subCode: nil, message: "Xpc(disconnect: peer closed)"), .other)
        XCTAssertEqual(TunnelFailure.classify(code: 103, subCode: nil, message: "RemotePairing"), .other)
    }
}

final class PairingFileCheckTests: XCTestCase {
    private func plist(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    func testValid() throws {
        XCTAssertEqual(PairingFileCheck.check(try plist(["private_key": Data([1]), "public_key": Data([2])])), .valid)
    }

    func testLockdown() throws {
        XCTAssertEqual(PairingFileCheck.check(try plist(["HostPrivateKey": Data([1])])), .lockdown)
    }

    func testInvalid() throws {
        XCTAssertEqual(PairingFileCheck.check(try plist(["private_key": "a", "public_key": "b"])),
                       .invalid("Missing public_key/private_key"))
        XCTAssertEqual(PairingFileCheck.check(Data([0xFF, 0x00, 0x13])), .invalid("Not a property list"))
        XCTAssertEqual(PairingFileCheck.check(Data(count: PairingFileCheck.maxSize + 1)),
                       .invalid("File too large for a pairing file"))
    }
}

final class DDIMethodTests: XCTestCase {
    func testMethod() {
        XCTAssertEqual(DDIMethod.method(major: 17, minor: 4), .personalized)
        XCTAssertEqual(DDIMethod.method(major: 26, minor: 3), .personalized)
        XCTAssertEqual(DDIMethod.method(major: 26, minor: 4), .cryptex)
        XCTAssertEqual(DDIMethod.method(major: 27, minor: 0), .cryptex)
    }

    /// The setup tool that mirrors the downloads pins the same hashes.
    func testHashesMatchFetchScript() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../tools/fetch-vendor.sh").standardized
        let script = try String(contentsOf: root, encoding: .utf8)
        for method in [DDIMethod.cryptex, .personalized] {
            for file in method.files {
                XCTAssertTrue(script.contains(file.sha256), "\(method.folder)/\(file.name)")
            }
        }
    }
}
