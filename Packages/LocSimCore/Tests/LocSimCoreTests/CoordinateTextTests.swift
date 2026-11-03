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

    func testAppleShortLinks() throws {
        XCTAssertNil(CoordinateText.parse("https://maps.apple/p/12.5,3.25"))
        XCTAssertNil(CoordinateText.parse("Café 21\nhttps://maps.apple/p/k8b3.4Dx-19"))
        let bare = try XCTUnwrap(MapLink.url(in: "maps.apple/p/AbC123"))
        XCTAssertEqual(bare.absoluteString, "https://maps.apple/p/AbC123")
        XCTAssertTrue(MapLink.isAppleShortLink(bare))
        assertParses("maps.apple.com/place?coordinate=52.52,13.405", 52.52, 13.405)
        XCTAssertNil(MapLink.url(in: "notmaps.apple/p/x"))

        // The redirects of a short link, with a last step that no longer names the place.
        let steps = try ["https://maps.apple.com/p/AbC123",
                         "https://maps.apple.com/place?place-id=I1234&address=Unter+den+Linden&name=Cafe",
                         "https://maps.apple.com/place?place-id=I1234&coordinate=52.517,13.389&name=Cafe",
                         "https://maps.apple.com/unsupported"].map { try XCTUnwrap(URL(string: $0)) }
        XCTAssertEqual(MapLink.bestStep(steps), steps[2])
        XCTAssertEqual(MapLink.bestStep(Array(steps.prefix(2))), steps[1])
        XCTAssertNil(MapLink.bestStep([steps[0], steps[3]]))
        XCTAssertTrue(MapLink.hasCoordinates(steps[2]))
        XCTAssertFalse(MapLink.hasCoordinates(steps[1]))
    }

    func testGeoAndGoogleEdgeCases() throws {
        // A name in geo: is a search, not 0,0.
        XCTAssertNil(CoordinateText.parse("geo:0,0?q=Eiffel+Tower"))
        XCTAssertEqual(MapLink.placeName(try XCTUnwrap(MapLink.url(in: "geo:0,0?q=Eiffel+Tower"))), "Eiffel Tower")
        assertParses("geo:0,0?q=48.85,2.35(Cafe)", 48.85, 2.35)
        assertParses("Pin: geo:48.85,2.35.", 48.85, 2.35)
        // Google place links: the place, not the map center.
        assertParses("https://www.google.com/maps/place/Eiffel+Tower/@48.8583701,2.2919064,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d48.8583701!4d2.2944813",
                     48.8583701, 2.2944813)
        // A search's map center is not the place; the name is searched instead.
        let search = try XCTUnwrap(MapLink.url(in: "https://www.google.com/maps/search/Pizza/@48.85,2.35,15z"))
        XCTAssertNil(CoordinateText.parse(search.absoluteString))
        XCTAssertEqual(MapLink.placeName(search), "Pizza")
        assertParses("https://www.google.com/maps/dir/48.85,2.35/52.52,13.40/@50,8,6z", 52.52, 13.40)
        assertParses("google.com/maps/@48.85,2.35,15z", 48.85, 2.35)
        assertParses("maps.apple.com?ll=48.85,2.35", 48.85, 2.35)
        assertParses("https://www.google.com/maps?q=loc:48.85,2.35", 48.85, 2.35)
        // Numbers in an address are not coordinates.
        XCTAssertNil(CoordinateText.parse("https://maps.apple.com/?q=10+20+Main+Street"))
        XCTAssertNil(CoordinateText.parse("https://maps.apple.com/?ll=0x1p5,1e1"))
    }

    func testSignsAndHemispheres() {
        assertParses("\u{2013}33°52′ 151°12′", -33.866667, 151.2, accuracy: 1e-5)
        assertParses("\u{2010}33.5, 151.2", -33.5, 151.2)
        XCTAssertNil(CoordinateText.parse("48°51'23\"N 2°21'07\"E 12"))
        XCTAssertNil(CoordinateText.parse("48°51'N 2°21'E foo"))
        assertParses("48.85, W 2.35", 48.85, -2.35)
        assertParses("N 48.85, 2.35 W", 48.85, -2.35)
        assertParses("48°51'N, W 2°21'", 48.85, -2.35, accuracy: 1e-2)
        XCTAssertNil(CoordinateText.parse("48.85 2.35 E N"))
        // Unchanged: decimal commas and consistent letters.
        assertParses("48,8566 2,3522", 48.8566, 2.3522)
        assertParses("N 48.8566 E 2.3522", 48.8566, 2.3522)
        assertParses("2.3522 E, 48.8566 N", 48.8566, 2.3522)
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
