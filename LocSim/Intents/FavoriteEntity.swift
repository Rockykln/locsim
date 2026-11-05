import AppIntents
import CoreLocation
import Foundation

/// A saved favorite, as Shortcuts and Siri see it.
struct FavoriteEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Favorite")
    static let defaultQuery = FavoriteQuery()

    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(CoordinateParser.format(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))")
    }

    init(_ favorite: Favorite) {
        id = favorite.id
        name = favorite.name
        latitude = favorite.latitude
        longitude = favorite.longitude
    }
}

// Enumerable: the list is short, and Siri can then choose among all favorites itself.
struct FavoriteQuery: EntityStringQuery, EnumerableEntityQuery {
    @MainActor
    func allEntities() async throws -> [FavoriteEntity] {
        FavoriteList.shared.items.map(FavoriteEntity.init)
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [FavoriteEntity] {
        FavoriteList.shared.items.filter { identifiers.contains($0.id) }.map(FavoriteEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [FavoriteEntity] {
        FavoriteList.shared.items
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(FavoriteEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [FavoriteEntity] {
        FavoriteList.shared.items.map(FavoriteEntity.init)
    }
}
