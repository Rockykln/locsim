import AppIntents
import Foundation

// In both targets: iOS hands this configuration to the app when the widget is tapped.

/// Which favorites the medium widget lists, chosen in its settings.
struct ChooseFavoritesIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Favorites"
    static let description = IntentDescription("Pick the favorites the widget lists. Without a choice it lists the most used ones.")

    // A switch, because iOS offers no way to empty the list once favorites are chosen.
    @Parameter(title: "Show Most Used", default: true)
    var mostUsed: Bool

    @Parameter(title: "Favorites", size: 3)
    var favorites: [WidgetFavorite]?

    static var parameterSummary: some ParameterSummary {
        When(\.$mostUsed, .equalTo, true) {
            Summary {
                \.$mostUsed
            }
        } otherwise: {
            Summary {
                \.$mostUsed
                \.$favorites
            }
        }
    }
}

/// A favorite as the widget knows it, from the list the app shares with the widget.
struct WidgetFavorite: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Favorite")
    static let defaultQuery = WidgetFavoriteQuery()

    let id: UUID
    let name: String
    let coordinate: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(coordinate)")
    }
}

struct WidgetFavoriteQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetFavorite] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetFavorite] {
        all()
    }

    private func all() -> [WidgetFavorite] {
        let snapshot = WidgetSnapshot.load()
        return (snapshot.catalog ?? snapshot.favorites).map {
            WidgetFavorite(id: $0.id, name: $0.name, coordinate: $0.coordinate)
        }
    }
}
