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

    func testResendNeverShorterAfterFailure() {
        XCTAssertEqual(ResendPolicy.delay(base: 120, failures: 0), 120)
        XCTAssertEqual(ResendPolicy.delay(base: 120, failures: 1), 60)
        XCTAssertEqual(ResendPolicy.delay(base: 10, failures: 1), 20)
        XCTAssertGreaterThan(ResendPolicy.delay(base: Int.max / 2 + 1, failures: 1), 0)
    }
}
