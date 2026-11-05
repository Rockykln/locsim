import CoreLocation
import UIKit

/// The actions shown when the LocSim icon on the Home Screen is held. iOS shows up to four:
/// Clear while a location is simulated (otherwise the last location), the two most used
/// favorites, and Search. They always open LocSim; the system offers no way to run them in
/// the background.
@MainActor
enum QuickActions {
    private enum Kind: String {
        case clear, last, favorite, search
    }

    static func refresh() {
        let session = SimulationSession.shared
        var items: [UIApplicationShortcutItem] = []
        if session.active != nil {
            items.append(item(.clear, String(localized: "Clear Location"), symbol: "arrow.uturn.backward"))
        } else if LastCoordinate.isSaved {
            items.append(item(.last, String(localized: "Set Last Location"), subtitle: LastCoordinate.loadName(),
                              symbol: "location.fill"))
        }
        for favorite in FavoriteUsage.ranked(FavoriteList.shared.items).prefix(2) {
            items.append(item(.favorite, favorite.name, subtitle: CoordinateParser.format(favorite.coordinate),
                              symbol: "star.fill", id: favorite.id))
        }
        items.append(item(.search, String(localized: "Search"), symbol: "magnifyingglass"))
        UIApplication.shared.shortcutItems = items
    }

    private static func item(
        _ kind: Kind, _ title: String, subtitle: String? = nil, symbol: String, id: UUID? = nil
    ) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: kind.rawValue, localizedTitle: title, localizedSubtitle: subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: symbol),
            userInfo: id.map { ["id": $0.uuidString as NSString] })
    }

    /// Runs a chosen action. Returns whether it was one of LocSim's.
    @discardableResult
    static func perform(_ item: UIApplicationShortcutItem) -> Bool {
        guard let kind = Kind(rawValue: item.type) else { return false }
        let session = SimulationSession.shared
        switch kind {
        case .clear:
            // The list may be older than the simulation it offers to end.
            guard session.canClear else { return true }
            Task { await session.clear() }
        case .last:
            guard LastCoordinate.isSaved else { return true }
            set(LastCoordinate.load(), name: LastCoordinate.loadName())
        case .favorite:
            guard let raw = item.userInfo?["id"] as? String, let id = UUID(uuidString: raw),
                  let favorite = FavoriteList.shared.items.first(where: { $0.id == id }) else { return true }
            set(favorite.coordinate, name: favorite.name)
        case .search:
            ExternalRequests.shared.post(.search)
        }
        return true
    }

    private static func set(_ coordinate: CLLocationCoordinate2D, name: String?) {
        ExternalRequests.shared.post(.set(latitude: coordinate.latitude, longitude: coordinate.longitude, name: name))
    }
}

/// Sets and searches asked for from outside the map: quick actions and widget taps. The map
/// screen runs them like its own taps (camera, setup steps), also when it appears only later.
@MainActor
final class ExternalRequests: ObservableObject {
    static let shared = ExternalRequests()

    enum Kind: Equatable {
        case set(latitude: Double, longitude: Double, name: String?)
        case search
    }

    struct Request: Equatable {
        let id = UUID()
        let kind: Kind
    }

    @Published var next: Request?

    func post(_ kind: Kind) { next = Request(kind: kind) }
}

/// SwiftUI has no hook for quick actions, so a scene delegate receives them.
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let item = connectionOptions.shortcutItem else { return }
        // The map screen picks the request up once it is there.
        MainActor.assumeIsolated { _ = QuickActions.perform(item) }
    }

    func windowScene(
        _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(MainActor.assumeIsolated { QuickActions.perform(shortcutItem) })
    }

    // The system reads the actions when LocSim leaves the screen.
    func sceneWillResignActive(_ scene: UIScene) {
        MainActor.assumeIsolated { QuickActions.refresh() }
    }
}

final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}
