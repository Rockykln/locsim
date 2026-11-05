// Siri AI can call these as tools. The @AppIntent(.tool) macro needs iOS 27.3, while the app
// runs from iOS 17.4, so each tool is its own type that only exists from iOS 27.3 on and runs
// the action Shortcuts already knows. SIRI_AI is set only for builds with the iOS 27.3 SDK or
// later (see project.yml); a build with an older SDK contains none of this.
#if SIRI_AI
import AppIntents

// Hidden in Shortcuts, which already lists the original actions. Set Last Location
// (Control Center) and the Live Activity's Clear button have no tool: they would duplicate these.

@available(iOS 27.3, *)
@AppIntent(.tool)
struct SetFavoriteTool: AppIntent {
    static let title: LocalizedStringResource = "Set Location to Favorite"
    static let description = IntentDescription("Opens LocSim and simulates the location of a saved favorite.")
    static let openAppWhenRun = true
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Favorite", description: "A place the person saved as a favorite in LocSim")
    var favorite: FavoriteEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var intent = SetFavoriteIntent()
        intent.favorite = favorite
        return try await intent.perform()
    }
}

@available(iOS 27.3, *)
@AppIntent(.tool)
struct SetPlaceTool: AppIntent {
    static let title: LocalizedStringResource = "Set Location to Place"
    static let description = IntentDescription(
        "Opens LocSim, finds a place by its name or address and simulates its location. Coordinates and map links work too.")
    static let openAppWhenRun = true
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Place", description: "A place name or address, for example Eiffel Tower or Alexanderplatz, Berlin")
    var place: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var intent = SetPlaceIntent()
        intent.place = place
        return try await intent.perform()
    }
}

@available(iOS 27.3, *)
@AppIntent(.tool)
struct SetCoordinatesTool: AppIntent {
    static let title: LocalizedStringResource = "Set Coordinates"
    static let description = IntentDescription(
        "Opens LocSim and simulates a location from coordinates or a map link that contains them.")
    static let openAppWhenRun = true
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Coordinates", description: "For example 48.8566, 2.3522")
    var coordinates: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var intent = SetCoordinatesIntent()
        intent.coordinates = coordinates
        return try await intent.perform()
    }
}

@available(iOS 27.3, *)
@AppIntent(.tool)
struct ClearLocationTool: AppIntent {
    static let title: LocalizedStringResource = "Clear Location"
    static let description = IntentDescription("Ends the simulated location and restores the real one.")
    static let openAppWhenRun = false
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ClearLocationIntent().perform()
    }
}
#endif
