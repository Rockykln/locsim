import XCTest
@testable import LocSimCore

final class CoordinateTextTests: XCTestCase {
    private func assertParses(_ text: String, _ lat: Double, _ lon: Double, accuracy: Double = 1e-6,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let c = CoordinateText.parse(text) else {
            return XCTFail("\(text) did not parse", file: file, line: line)
        }
        XCTAssertEqual(c.latitude, lat, accuracy: accuracy, text, file: file, line: line)
        XCTAssertEqual(c.longitude, lon, accuracy: accuracy, text, file: file, line: line)
    }

    func testDecimal() {
        assertParses("48.8566, 2.3522", 48.8566, 2.3522)
        assertParses("48,8566 2,3522", 48.8566, 2.3522)
        assertParses("52,5 13,4", 52.5, 13.4)
        assertParses("52, 13", 52, 13)
        assertParses("−33.86, 151.2", -33.86, 151.2)
    }

    func testHemispheres() {
        assertParses("N 48.8566 E 2.3522", 48.8566, 2.3522)
        assertParses("48,85660° N, 2,35220° O", 48.8566, 2.3522)
        assertParses("2.3522 E 48.8566 N", 48.8566, 2.3522)
        assertParses("33.8688 S 151.2093 E", -33.8688, 151.2093)
    }

    func testDegreesMinutesSeconds() {
        assertParses(#"48°51'23.8"N 2°21'07.9"E"#, 48.856611, 2.352194, accuracy: 1e-5)
    }

    func testRejects() {
        for text in [#"48°60'0"N 2°E"#, "48.5°30'N 2°E", "N 48 N 2", "91, 0", "Paris", "48.8566", ""] {
            XCTAssertNil(CoordinateText.parse(text), text)
        }
    }

    func testMapLinks() {
        assertParses("https://maps.apple.com/?ll=48.8566,2.3522&q=Paris", 48.8566, 2.3522)
        assertParses("https://maps.apple.com/place?coordinate=52.52,13.405", 52.52, 13.405)
        assertParses("https://www.google.com/maps/@48.8566,2.3522,15z", 48.8566, 2.3522)
        assertParses("https://www.google.com/maps/search/?api=1&query=47.3782,8.5402", 47.3782, 8.5402)
        assertParses("geo:38.711,-9.137?z=12", 38.711, -9.137)
        assertParses("https://maps.apple.com/place?address=Paris&coordinate=48.8566,2.3522&name=Paris",
                     48.8566, 2.3522)
        assertParses("Eiffel Tower\nhttps://maps.apple.com/?ll=48.8584,2.2945&q=Eiffel%20Tower", 48.8584, 2.2945)
        XCTAssertNil(CoordinateText.parse("https://maps.apple/p/AbCdEf123"))
        XCTAssertNil(CoordinateText.parse("https://example.com/?ll=48.8566,2.3522"))
        XCTAssertNil(CoordinateText.parse("https://maps.apple.com/?q=Paris"))
    }

    func testFormat() {
        let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
        XCTAssertEqual(CoordinateText.format(paris, as: .decimal, precision: 5), "48.85660, 2.35220")
        XCTAssertEqual(CoordinateText.format(paris, as: .decimal, precision: 9), "48.8566000, 2.3522000")
        XCTAssertEqual(CoordinateText.format(paris, as: .dms), "48°51′23.8″N 2°21′07.9″E")
        XCTAssertEqual(CoordinateText.format(Coordinate(latitude: -0.000001, longitude: 0), as: .decimal),
                       "0.00000, 0.00000")
    }

    func testFormatRoundTrip() {
        let c = Coordinate(latitude: -33.8688, longitude: 151.2093)
        for format in CoordinateFormat.allCases {
            let text = CoordinateText.format(c, as: format, precision: 7)
            assertParses(text, c.latitude, c.longitude, accuracy: 0.1 / 3600)
        }
    }

    func testMapLinkHelpers() throws {
        let short = try XCTUnwrap(MapLink.url(in: "Eiffel Tower\nhttps://maps.apple/p/AbCdEf123"))
        XCTAssertTrue(MapLink.isAppleShortLink(short))
        XCTAssertFalse(MapLink.isAppleShortLink(try XCTUnwrap(URL(string: "https://maps.apple.com/?ll=1,2"))))
        XCTAssertTrue(MapLink.isGoogleShortLink(try XCTUnwrap(URL(string: "https://maps.app.goo.gl/xyz"))))
        let named = try XCTUnwrap(URL(string: "https://maps.apple.com/?ll=48.8584,2.2945&q=Eiffel%20Tower"))
        XCTAssertEqual(MapLink.placeName(named), "Eiffel Tower")
        let coordinatesOnly = try XCTUnwrap(URL(string: "https://maps.apple.com/?q=48.8584,2.2945"))
        XCTAssertNil(MapLink.placeName(coordinatesOnly))
        XCTAssertNil(MapLink.url(in: "48.8566, 2.3522"))
    }

    func testLinksInText() {
        assertParses("see https://maps.apple.com/?ll=48.85,2.35.", 48.85, 2.35)
        assertParses("(https://maps.apple.com/?ll=48.85,2.35)", 48.85, 2.35)
        assertParses("https://www.google.de/maps/search/?api=1&query=48.85+2.35", 48.85, 2.35)
        assertParses("geo:0,0?q=48.85,2.35(Cafe)", 48.85, 2.35)
        assertParses("N48°51.4' E2°21.1'", 48.856667, 2.351667, accuracy: 1e-5)
    }

    func testOnlyMapHosts() throws {
        XCTAssertFalse(MapLink.isMap(try XCTUnwrap(URL(string: "https://music.apple.com/?ll=1,2"))))
        XCTAssertFalse(MapLink.isMap(try XCTUnwrap(URL(string: "https://docs.google.com/document/d/1"))))
        XCTAssertTrue(MapLink.isMap(try XCTUnwrap(URL(string: "https://www.google.com/maps/place/x"))))
        XCTAssertTrue(MapLink.isMap(try XCTUnwrap(URL(string: "https://maps.google.de/?q=1,2"))))
        XCTAssertNil(CoordinateText.parse("https://maps.apple.com/?q=Pizza&sll=48.85,2.35"))
        XCTAssertEqual(MapLink.placeName(try XCTUnwrap(URL(string: "https://www.google.com/maps/search/?api=1&query=Pizza+Place"))),
                       "Pizza Place")
    }
}
