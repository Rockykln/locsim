import XCTest
@testable import LocSimCore

/// Formats people paste from websites, apps and links.
final class PastedFormatsTests: XCTestCase {
    private func parse(_ text: String, _ language: String = "en") -> Coordinate? {
        CoordinateText.parse(text, language: language)
    }

    private let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)

    func testGooglePlaceBeforeMapView() {
        // In Google links "ll" is only the map view; the place is in q or the destination.
        XCTAssertEqual(parse("https://maps.google.com/maps?saddr=40.7,-74.0&daddr=48.8566,2.3522&ll=45.0,-30.0&z=4"), paris)
        XCTAssertEqual(parse("https://maps.google.com/maps?q=48.8566,2.3522&ll=45.0,-30.0&z=4"), paris)
        // An old link with only the view still works.
        XCTAssertEqual(parse("https://maps.google.com/?ll=48.8566,2.3522"), paris)
    }

    func testWholeNumbersInSearchTermsAreNames() {
        XCTAssertNil(parse("https://www.google.com/maps/search/7+11"))
        XCTAssertNil(parse("https://maps.apple.com/?q=10+20"))
        XCTAssertNil(parse("https://www.google.com/maps/place/24+7"))
        XCTAssertNil(parse("3 4"))
        // A pin or view may still be whole numbers.
        XCTAssertEqual(parse("https://maps.apple.com/?ll=48,2")?.latitude, 48)
    }

    func testWikipedia() {
        let c = parse("48°51′24″N 2°21′08″E / 48.85667°N 2.35222°E / 48.85667; 2.35222")
        XCTAssertEqual(c?.latitude ?? 0, 48.85667, accuracy: 1e-4)
        XCTAssertEqual(c?.longitude ?? 0, 2.35222, accuracy: 1e-4)
    }

    func testLabels() {
        XCTAssertEqual(parse("Latitude: 48.8566\nLongitude: 2.3522"), paris)
        XCTAssertEqual(parse("Coordinates: 48.8566, 2.3522"), paris)
        XCTAssertEqual(parse("Lat: 48.8566 N Long: 2.3522 E"), paris)
        XCTAssertEqual(parse("lat 48.8566 lon 2.3522"), paris)
        XCTAssertEqual(parse("Breite: 48,8566 Länge: 2,3522", "de"), paris)
        // Place names stay names.
        XCTAssertNil(parse("Long Beach 12"))
    }

    func testCoordinatesNextToShortLink() {
        XCTAssertEqual(parse("48.8566, 2.3522 https://maps.app.goo.gl/abc"), paris)
        XCTAssertNil(parse("Eiffel Tower https://maps.app.goo.gl/abc"))
    }

    func testDegreesAndMinutesWithLettersAfter() {
        let c = parse("48° 51.396 N 2° 21.132 E")
        XCTAssertEqual(c?.latitude ?? 0, 48.8566, accuracy: 1e-4)
        XCTAssertEqual(c?.longitude ?? 0, 2.3522, accuracy: 1e-4)
    }

    func testWazeAndOpenStreetMap() {
        XCTAssertEqual(parse("https://www.waze.com/live-map/directions?navigate=yes&to=ll.48.8566%2C2.3522"), paris)
        XCTAssertEqual(parse("https://www.openstreetmap.org/?lat=48.8566&lon=2.3522&zoom=15"), paris)
    }

    func testLabelsInReverseOrder() {
        XCTAssertEqual(parse("Longitude: 2.3522, Latitude: 48.8566"), paris)
        XCTAssertEqual(parse("lng: 2.3522 lat: 48.8566"), paris)
        XCTAssertEqual(parse("Länge: 2,3522 Breite: 48,8566", "de"), paris)
        XCTAssertEqual(parse("lon: 151.2093, lat: -33.8688"), Coordinate(latitude: -33.8688, longitude: 151.2093))
        // Letters already give the order; the labels must not swap a second time.
        XCTAssertEqual(parse("Longitude: 2.3522 E, Latitude: 48.8566 N"), paris)
        XCTAssertEqual(parse("Lat/Long: 48.8566, 2.3522"), paris)
        XCTAssertEqual(parse("Lng / Lat: 2.3522, 48.8566"), paris)
        XCTAssertNil(parse("Long Beach 12"))
    }

    func testAndIsNoHemisphere() {
        XCTAssertNil(parse("41.9028 e 12.4964", "it"))
        // With axis labels the "e" is "and", and the labels give the order.
        XCTAssertEqual(parse("Lat: 38.7223 e Long: -9.1393", "pt"), Coordinate(latitude: 38.7223, longitude: -9.1393))
        XCTAssertEqual(parse("Latitudine: 41.9028 e Longitudine: 12.4964", "it"),
                       Coordinate(latitude: 41.9028, longitude: 12.4964))
        // An uppercase E stays east.
        XCTAssertEqual(parse("2.3522 E 48.8566"), paris)
        XCTAssertEqual(parse("48.85 N 2.35"), Coordinate(latitude: 48.85, longitude: 2.35))
    }

    func testTypographicMarksAndLabels() {
        for text in ["48°51‘23.8“N 2°21‘07.9“E", "48°51´23.8\"N 2°21´07.9\"E", "48°51ʹ23.8ʺN 2°21ʹ07.9ʺE"] {
            let c = parse(text)
            XCTAssertEqual(c?.latitude ?? 0, 48.856611, accuracy: 1e-5, text)
            XCTAssertEqual(c?.longitude ?? 0, 2.352194, accuracy: 1e-5, text)
        }
        XCTAssertEqual(parse("Koordinaten: 48.8566, 2.3522", "de"), paris)
        XCTAssertEqual(parse("Coordonnées : 48.8566, 2.3522", "fr"), paris)
        XCTAssertEqual(parse("Latitud: 40.4168, Longitud: -3.7038", "es"), Coordinate(latitude: 40.4168, longitude: -3.7038))
        XCTAssertEqual(parse("Latitudine: 48.8566, Longitudine: 2.3522", "it"), paris)
        XCTAssertEqual(parse("Breedtegraad: 48.8566, Lengtegraad: 2.3522", "nl"), paris)
        XCTAssertEqual(parse("📍 48.8566, 2.3522"), paris)
        XCTAssertNil(parse("Location 1.5 2.5"))
    }

    func testWholeNumbersOnlyWhenAllowed() {
        XCTAssertNil(parse("52, 13"))
        XCTAssertEqual(CoordinateText.parse("52, 13", language: "en", allowWholeNumbers: true),
                       Coordinate(latitude: 52, longitude: 13))
        XCTAssertEqual(CoordinateText.parse("0, 0", language: "en", allowWholeNumbers: true),
                       Coordinate(latitude: 0, longitude: 0))
        XCTAssertEqual(CoordinateText.parse("90 180", language: "en", allowWholeNumbers: true),
                       Coordinate(latitude: 90, longitude: 180))
        XCTAssertNil(CoordinateText.parse("91, 0", language: "en", allowWholeNumbers: true))
    }

    func testRouteDestinations() throws {
        let osm = "https://www.openstreetmap.org/directions?engine=fossgis_osrm_car"
            + "&route=52.52%2C13.405%3B48.8566%2C2.3522#map=6/50.68/7.88"
        XCTAssertEqual(parse(osm), paris)
        XCTAssertNil(parse("https://www.openstreetmap.org/directions#map=6/50.68/7.88"))
        XCTAssertEqual(parse("https://www.openstreetmap.org/directions?from=&to=48.8566%2C2.3522#map=6/50.68/7.88"), paris)
        // A route without a destination names no place to go to.
        let startOnly = try XCTUnwrap(URL(string: "https://www.google.com/maps/dir/Louvre//@48.86,2.33,14z"))
        XCTAssertNil(MapLink.placeName(startOnly))
        XCTAssertNil(parse("https://www.google.com/maps/dir/48.8606,2.3376//@48.86,2.33,14z"))
        let trailing = try XCTUnwrap(URL(string: "https://www.google.com/maps/dir/Louvre/Eiffel+Tower/"))
        XCTAssertEqual(MapLink.placeName(trailing), "Eiffel Tower")
        let named = [
            "https://www.google.com/maps/dir/?api=1&destination=Eiffel+Tower",
            "https://maps.apple.com/?daddr=Eiffel+Tower",
            "https://maps.apple.com/directions?destination=Eiffel%20Tower",
            "https://www.google.com/maps/dir/48.80,2.30/Eiffel+Tower/@48.85,2.29,13z",
        ]
        for link in named {
            let url = try XCTUnwrap(URL(string: link))
            XCTAssertNil(parse(link), link)
            XCTAssertEqual(MapLink.placeName(url), "Eiffel Tower", link)
        }
    }

    func testWazeShareLinkAndOtherNames() throws {
        XCTAssertEqual(parse("https://ul.waze.com/ul?place=ChIJ&ll=48.85661400%2C2.35222190&navigate=yes"),
                       Coordinate(latitude: 48.856614, longitude: 2.3522219))
        XCTAssertFalse(MapLink.isMap(try XCTUnwrap(URL(string: "https://wiki.openstreetmap.org/wiki/Main_Page"))))
        // A search or event link names nothing on the map.
        XCTAssertNil(MapLink.placeName(try XCTUnwrap(URL(string: "https://www.google.com/search?q=hotel+paris"))))
        XCTAssertNil(MapLink.placeName(try XCTUnwrap(URL(string: "https://example.com/event?name=Party"))))
        XCTAssertEqual(MapLink.placeName(try XCTUnwrap(URL(string: "https://maps.apple.com/?q=Eiffel+Tower"))), "Eiffel Tower")
    }

    func testShortLinkRedirectsStayAtApple() throws {
        for link in ["https://maps.apple.com/place?q=x", "https://maps.apple/p/abc", "https://www.apple.com/maps/"] {
            XCTAssertTrue(MapLink.isAppleRedirect(try XCTUnwrap(URL(string: link))), link)
        }
        for link in ["http://maps.apple.com/place", "https://example.com/", "https://maps.apple.com.example.org/",
                     "https://notapple.com/"] {
            XCTAssertFalse(MapLink.isAppleRedirect(try XCTUnwrap(URL(string: link))), link)
        }
        XCTAssertFalse(MapLink.isAppleShortLink(try XCTUnwrap(URL(string: "geo://maps.apple/p/abc"))))
    }

    func testLongInputStaysFast() {
        let inputs = [
            "https://maps.apple.com/?q=x" + String(repeating: ")", count: 4000),
            String(repeating: "1", count: 3000) + "'",
            "N 48 51.3" + String(repeating: " ", count: 1000) + "x",
        ]
        for text in inputs {
            let start = Date()
            _ = parse(text)
            _ = MapLink.url(in: text)
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5, String(text.prefix(30)))
        }
    }

    func testLabelsAsWrittenInTheAppLanguages() {
        let munich = Coordinate(latitude: 48.137154, longitude: 11.576124)
        XCTAssertEqual(parse("GPS-Koordinaten: 48.137154, 11.576124", "de"), munich)
        XCTAssertEqual(parse("Lat. 48.8566, Long. 2.3522"), paris)
        // "GPS" before a label must not hide the axis.
        XCTAssertEqual(parse("GPS Lon: 2.3522, GPS Lat: 48.8566"), paris)
        XCTAssertEqual(parse("48.137154 / 11.576124"), munich)
        // A slash between whole numbers is still a name where whole numbers are refused.
        XCTAssertNil(parse("7 / 11"))
        XCTAssertEqual(CoordinateText.parse("7 / 11", language: "en", allowWholeNumbers: true),
                       Coordinate(latitude: 7, longitude: 11))
    }

    func testOldGoogleRouteLinkSearchesTheNamedDestination() throws {
        // ll is only the map view; the named destination is searched instead of the view.
        let link = "https://maps.google.com/maps?daddr=Eiffel+Tower&ll=48.87,2.33&z=12"
        XCTAssertNil(parse(link))
        XCTAssertEqual(MapLink.placeName(try XCTUnwrap(URL(string: link))), "Eiffel Tower")
        // Apple links keep reading ll.
        XCTAssertEqual(parse("https://maps.apple.com/?daddr=Eiffel+Tower&ll=48.8566,2.3522"), paris)
    }

    func testSlashAndPlusInLinkNames() throws {
        let route = try XCTUnwrap(URL(string: "https://www.google.com/maps/dir/Prague+Castle/Karlova+186%2F25,+Praha/@50.08,14.41,15z"))
        XCTAssertEqual(MapLink.placeName(route), "Karlova 186/25, Praha")
        XCTAssertNil(parse(route.absoluteString))
        let place = try XCTUnwrap(URL(string: "https://www.google.com/maps/place/Mariahilfer+Stra%C3%9Fe+12%2F3/@48.19,16.35,17z"))
        XCTAssertEqual(MapLink.placeName(place), "Mariahilfer Straße 12/3")
        XCTAssertEqual(MapLink.placeName(try XCTUnwrap(URL(string: "https://maps.google.com/?q=A%2BB+Cafe"))), "A+B Cafe")
        // An empty geo: label names nothing.
        XCTAssertNil(MapLink.placeName(try XCTUnwrap(URL(string: "geo:48.8566,2.3522?q=48.8566,2.3522()"))))
    }

    func testLinksInTypographicQuotes() {
        for text in ["„https://maps.apple.com/?ll=48.8566,2.3522“", "«https://maps.apple.com/?ll=48.8566,2.3522»",
                     "“https://maps.apple.com/?ll=48.8566,2.3522”", "「https://maps.apple.com/?ll=48.8566,2.3522」"] {
            XCTAssertEqual(parse(text), paris, text)
            XCTAssertEqual(MapLink.url(in: text)?.absoluteString, "https://maps.apple.com/?ll=48.8566,2.3522", text)
        }
    }

    func testSearchTermAddsTheAddress() throws {
        let link = try XCTUnwrap(URL(string: "https://maps.apple.com/?name=Cafe+Central&address=Herrengasse+14,+Wien"))
        XCTAssertEqual(MapLink.placeName(link), "Cafe Central")
        XCTAssertEqual(MapLink.searchTerm(link), "Cafe Central, Herrengasse 14, Wien")
        let addressOnly = try XCTUnwrap(URL(string: "https://maps.apple.com/?address=Herrengasse+14,+Wien"))
        XCTAssertEqual(MapLink.searchTerm(addressOnly), "Herrengasse 14, Wien")
    }

    func testResendNeverShorterAfterFailure() {
        XCTAssertEqual(ResendPolicy.delay(base: 120, failures: 0), 120)
        XCTAssertEqual(ResendPolicy.delay(base: 120, failures: 1), 60)
        XCTAssertEqual(ResendPolicy.delay(base: 10, failures: 1), 20)
        XCTAssertGreaterThan(ResendPolicy.delay(base: Int.max / 2 + 1, failures: 1), 0)
    }
}
