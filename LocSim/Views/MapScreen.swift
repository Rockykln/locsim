import MapKit
import SwiftUI

struct MapScreen: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var favorites: FavoriteList
    @StateObject private var search = PlaceSearch()
    @State private var camera: MapCameraPosition = .automatic
    @State private var showSettings = false
    @State private var showWelcome = false
    @State private var showFavorites = false
    @State private var naming = false
    @State private var favoriteName = ""
    @State private var searchError: String?
    @State private var shownError: AppError?
    @State private var droppedPins = 0
    @State private var suggestionsHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @Namespace private var mapScope
    @State private var mapBottom: CGFloat = 0
    @State private var panelTop: CGFloat = .infinity
    @State private var locateTask: Task<Void, Never>?
    // Annotations added before the map has settled stay invisible until the next redraw.
    @State private var mapReady = false
    // Cancelled by any newer choice, so a late result cannot move the pin back.
    @State private var searchTask: Task<Void, Never>?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    // Shown while nothing is simulated, once location access is allowed.
    @State private var showsUserLocation = false
    @AppStorage(SettingsKey.mapStyle) private var mapStyle = MapStyleOption.standard.rawValue
    @AppStorage(SettingsKey.zoom) private var zoom = ZoomOption.block.rawValue
    @AppStorage(SettingsKey.autoApply) private var autoApply = false
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.precision) private var precision = 5
    @AppStorage(SettingsKey.coordinateFormat) private var coordinateFormat = CoordinateFormat.decimal.rawValue

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea()
            topBar
                .frame(maxWidth: 640)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        pinButton
                        locateButton
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.bottom, 10)
                bottomPanel
            }
            .frame(maxWidth: 640)
            .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .top) {
            dropdown
                .padding(.horizontal, Metrics.margin)
                .padding(.top, Metrics.barBottom + Metrics.dropdownGap)
                .frame(maxWidth: 640)
        }
        .ignoresSafeArea(.keyboard)
        .mapScope(mapScope)
        .sensoryFeedback(trigger: session.state) { old, new in
            guard haptics, old != new else { return nil }
            switch new {
            case .active: return .success
            case .failed: return .error
            default: return nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { showsUserLocation = false }
            if phase == .active { showRealPositionIfAllowed() }
        }
        .onChange(of: session.state) { _, _ in showRealPositionIfAllowed() }
        .onChange(of: session.active == nil) { _, idle in
            if idle {
                showRealPositionIfAllowed()
            } else {
                showsUserLocation = false
                locateTask?.cancel()
            }
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView().environmentObject(session)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(session)
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesView { favorite in
                select(favorite.coordinate, name: favorite.name, apply: autoApply)
                showFavorites = false
            }
            .equatable()
            .environmentObject(favorites)
        }
        .alert(
            shownError?.title ?? "",
            isPresented: Binding(get: { shownError != nil }, set: { if !$0 { shownError = nil } }),
            presenting: shownError
        ) { error in
            Button("Copy Details") { UIPasteboard.general.string = error.report }
            Button("OK", role: .cancel) {}
        } message: { error in
            Text("\(error.message)\n\nError \(error.code)")
        }
        .alert("Save favorite", isPresented: $naming) {
            TextField("Name", text: $favoriteName)
            Button("Save") { saveFavorite() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            camera = Demo.camera ?? region(session.target)
            showRealPositionIfAllowed()
            if !session.hasPairing { showWelcome = true }
            showDemo()
        }
    }

    // MARK: - Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera, scope: mapScope) {
                if showsUserLocation, session.active == nil, scenePhase == .active {
                    UserAnnotation()
                }
                if mapReady {
                    Annotation(
                        session.targetName ?? String(localized: "Dropped pin"),
                        coordinate: session.target, anchor: MapPin.anchor
                    ) {
                        MapPin(showsActiveDot: activeIsAtPin)
                    }
                    // The panel already shows the name.
                    .annotationTitles(.hidden)
                }
                if mapReady, let active = session.active, !activeIsAtPin {
                    Annotation(String(localized: "Active"), coordinate: active) {
                        ActiveDot()
                    }
                    // The panel already shows the state.
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(resolvedMapStyle)
            .mapControls {}
            // Measured from the panel, which stays put; safe area insets would include the keyboard.
            .safeAreaPadding(.bottom, max(0, mapBottom - panelTop - 2))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { mapBottom = $0 }
            // Symmetric to keep the camera centered; moves the legal label past the panel corner.
            .safeAreaPadding(.horizontal, 16)
            .onMapCameraChange(frequency: .onEnd) { context in
                search.bias(to: context.region)
                mapReady = true
            }
            // In case the camera reports no change after the first layout.
            .task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                mapReady = true
            }
            // Simultaneous, so MapKit's double tap to zoom still works.
            .simultaneousGesture(TapGesture().onEnded { searchFocused = false })
            .onLongPress { dropPin(at: $0, proxy: proxy) }
            .sensoryFeedback(trigger: droppedPins) { _, _ in haptics ? .impact : nil }
        }
    }

    // MapKit picks the order of separate annotations, so at the same spot they are drawn as one.
    private var activeIsAtPin: Bool {
        guard let active = session.active else { return false }
        return abs(active.latitude - session.target.latitude) < 1e-7
            && abs(active.longitude - session.target.longitude) < 1e-7
    }

    private func dropPin(at point: CGPoint, proxy: MapProxy) {
        guard !legalZone.contains(point) else { return }
        // Beside the globe a point still maps to its edge; accept only points that project back.
        guard let coordinate = proxy.convert(point, from: .global),
              let back = proxy.convert(coordinate, to: .global),
              hypot(back.x - point.x, back.y - point.y) < 24 else { return }
        searchFocused = false
        searchTask?.cancel()
        locateTask?.cancel()
        session.target = coordinate
        session.targetName = nil
        droppedPins += 1
    }

    // Area around MapKit's legal link where taps must not move the pin.
    private var legalZone: CGRect {
        CGRect(x: 0, y: panelTop - Metrics.legalZone.height,
               width: Metrics.legalZone.width, height: Metrics.legalZone.height)
    }

    private var resolvedMapStyle: MapStyle {
        switch MapStyleOption(rawValue: mapStyle) ?? .standard {
        case .standard: return .standard(elevation: .realistic, pointsOfInterest: Demo.isOn ? .excludingAll : .all)
        case .hybrid: return .hybrid(elevation: .realistic)
        case .imagery: return .imagery(elevation: .realistic)
        }
    }

    // MARK: - Search bar

    private var topBar: some View {
        HStack(spacing: 8) {
            iconButton("globe", label: "Website") {
                openURL(AppLinks.website)
            }
            searchField
            iconButton("star", label: "Favorites") { showFavorites = true }
            iconButton("gearshape", label: "Settings") { showSettings = true }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, Metrics.barTop)
        .overlay(alignment: .topTrailing) {
            MapCompass(scope: mapScope)
                .frame(width: Metrics.control)
                .padding(.trailing, Metrics.margin)
                .offset(y: Metrics.barBottom + Metrics.compassGap)
        }
        .overlay(alignment: .topLeading) {
            MapScaleView(scope: mapScope)
                .padding(.leading, 16)
                .offset(y: Metrics.barBottom + Metrics.compassGap + 6)
        }
        .zIndex(1)
    }

    @ViewBuilder
    private var dropdown: some View {
        if let searchError {
            Text(searchError)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if searchFocused || Demo.screen == .search, hasSuggestions {
            suggestions
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            // Own placeholder so it is never cut off on narrow screens.
            TextField("Search place or coordinates", text: $search.query, prompt: Text(verbatim: ""))
                .overlay(alignment: .leading) {
                    if search.query.isEmpty {
                        ViewThatFits(in: .horizontal) {
                            Text("Search place or coordinates")
                            Text("Place or coordinates")
                                .minimumScaleFactor(0.75)
                        }
                        .lineLimit(1)
                        .foregroundStyle(Color(uiColor: .placeholderText))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(submitSearch)
                .onChange(of: search.query) { _, _ in searchError = nil }
            if !search.query.isEmpty {
                Button {
                    search.reset()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(uiColor: .systemGray))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Metrics.control)
        .glassCapsule(interactive: true)
    }

    private var hasSuggestions: Bool {
        guard !search.query.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return search.coordinate != nil || !search.completions.isEmpty || Demo.suggestions != nil
    }

    // Secondary content uses opaque colors: translucent ones were sometimes not drawn on the material.
    private var suggestions: some View {
        ScrollView {
            suggestionRows
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { suggestionsHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(suggestionsHeight, Metrics.dropdownMaxHeight))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var suggestionRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let coordinate = search.coordinate {
                suggestionRow(
                    icon: "scope",
                    title: CoordinateParser.format(coordinate),
                    subtitle: String(localized: "Coordinates")
                ) {
                    select(coordinate, name: nil, apply: autoApply)
                }
            }
            if let demo = Demo.suggestions {
                ForEach(Array(demo.enumerated()), id: \.offset) { index, place in
                    if index > 0 { Divider().overlay(Color(uiColor: .opaqueSeparator)).padding(.leading, 44) }
                    suggestionRow(icon: "mappin", title: place.title, subtitle: place.subtitle) {
                        select(place.coordinate, name: place.title, apply: autoApply)
                    }
                }
            } else {
                ForEach(Array(search.completions.enumerated()), id: \.element.id) { index, completion in
                    if index > 0 || search.coordinate != nil {
                        Divider().overlay(Color(uiColor: .opaqueSeparator)).padding(.leading, 44)
                    }
                    suggestionRow(icon: "mappin", title: completion.title, subtitle: completion.subtitle) {
                        searchTask?.cancel()
                        searchTask = Task { await pick(completion) }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func suggestionRow(
        icon: String, title: String, subtitle: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(Color(uiColor: .systemGray))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .systemGray))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: Metrics.control, height: Metrics.control)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle()
        .accessibilityLabel(Text(label))
    }

    // MARK: - Panel

    private var pinButton: some View {
        Button {
            locateTask?.cancel()
            fly(to: session.target)
        } label: {
            PinGlyph(height: 22)
                .frame(width: Metrics.control, height: Metrics.control)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle()
        .accessibilityLabel("Show pin")
    }

    private var locateButton: some View {
        Button {
            locateTask?.cancel()
            if let active = session.active {
                fly(to: active)
            } else {
                showsUserLocation = true
                locateTask = Task { await flyToRealLocation() }
            }
        } label: {
            Image(systemName: session.active != nil ? "location.fill" : "location")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(session.active != nil ? Color.blue : Color.primary)
                .frame(width: Metrics.control, height: Metrics.control)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle()
        .accessibilityLabel(
            session.active != nil ? String(localized: "Show active location") : String(localized: "Show my location"))
    }

    private func fly(to coordinate: CLLocationCoordinate2D) {
        withAnimation(.smooth(duration: 1.0)) {
            camera = .camera(MapCamera(centerCoordinate: coordinate, distance: zoom))
        }
    }

    // Never asks for permission; that happens when the user taps the locate button.
    private func showRealPositionIfAllowed() {
        // After a failed Clear the simulation may still be in force.
        guard !Demo.isOn, session.active == nil, session.state.error?.code != AppError.clearFailedCode else {
            return
        }
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: showsUserLocation = true
        default: break
        }
    }

    private func flyToRealLocation() async {
        session.requestLocationPermission()
        // The wait for a fix below should not run while the permission prompt is open.
        let manager = CLLocationManager()
        let wasAsked = manager.authorizationStatus == .notDetermined
        while manager.authorizationStatus == .notDetermined {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
        }
        guard manager.authorizationStatus != .denied, manager.authorizationStatus != .restricted else {
            // Only an earlier denial sends the user to Settings, not the answer just given.
            if !wasAsked, let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            return
        }
        let requested = Date().addingTimeInterval(-1)
        let fix = Task { () -> CLLocationCoordinate2D? in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    // The first update can be the last known fix, which may still be the simulated one.
                    if let location = update.location, location.timestamp >= requested { return location.coordinate }
                }
            } catch {}
            return nil
        }
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            fix.cancel()
        }
        let coordinate = await fix.value
        timeout.cancel()
        guard !Task.isCancelled else { return }
        if let coordinate {
            fly(to: coordinate)
        } else {
            withAnimation { camera = .userLocation(fallback: camera) }
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.targetName ?? String(localized: "Dropped pin"))
                        .font(.headline)
                        .lineLimit(1)
                    Text(CoordinateParser.format(session.target))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button {
                    favoriteName = session.targetName ?? ""
                    naming = true
                } label: {
                    Image(systemName: "star")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassCircle()
                .accessibilityLabel("Save favorite")
            }

            Button {
                if let error = session.state.error { shownError = error }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 8, height: 8)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if session.state.isFailure {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(session.state.isFailure ? Text("Shows error details") : Text(verbatim: ""))

            if session.backgroundDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Without location access, the location stops in the background. Tap to allow.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button {
                    searchFocused = false
                    Task { await session.apply() }
                } label: {
                    Label(
                        session.state == .connecting
                            ? String(localized: "Connecting") : String(localized: "Set Location"),
                        systemImage: "location.fill")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .primaryButton()
                .disabled(session.state == .connecting)

                Button {
                    Task { await session.clear() }
                } label: {
                    Label("Clear", systemImage: "arrow.uturn.backward")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.vertical, 6)
                }
                .secondaryButton()
                .disabled(!session.canClear)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: Metrics.panelRadius)
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, 4)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { panelTop = $0 }
    }

    private var statusLine: String {
        var parts: [String] = []
        switch session.state {
        case .idle: parts.append(session.active == nil ? String(localized: "Not active") : String(localized: "Idle"))
        case .connecting: parts.append(String(localized: "Connecting"))
        case .active:
            parts.append(String(localized: "Active"))
            // The pin shows the active location unless it was moved since.
            if let active = session.active, CoordinateParser.format(active) != CoordinateParser.format(session.target) {
                parts.append(CoordinateParser.format(active))
            }
        case .reconnecting(let error): parts.append("\(String(localized: "Reconnecting"))  ·  \(error.code)")
        case .failed(let error): parts.append("\(error.title)  ·  \(error.code)")
        }
        if let sent = session.lastSent, session.state == .active {
            parts.append(sent.formatted(date: .omitted, time: .standard))
        }
        return parts.joined(separator: "  ·  ")
    }

    private var stateColor: Color {
        switch session.state {
        case .active: return .green
        case .failed: return .red
        case .connecting, .reconnecting: return .orange
        case .idle: return .secondary
        }
    }

    // MARK: - Actions

    private func submitSearch() {
        if let coordinate = search.coordinate {
            select(coordinate, name: nil, apply: autoApply)
            return
        }
        guard !search.query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            do {
                let place = try await search.search()
                guard !Task.isCancelled else { return }
                select(place.coordinate, name: place.name, apply: autoApply)
            } catch {
                guard !Task.isCancelled else { return }
                searchError = error.localizedDescription
            }
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        do {
            let place = try await search.resolve(completion)
            guard !Task.isCancelled else { return }
            select(place.coordinate, name: place.name, apply: autoApply)
        } catch {
            guard !Task.isCancelled else { return }
            searchError = error.localizedDescription
        }
    }

    private func select(_ coordinate: CLLocationCoordinate2D, name: String?, apply: Bool = false) {
        searchTask?.cancel()
        locateTask?.cancel()
        session.target = coordinate
        session.targetName = name
        searchFocused = false
        search.reset()
        withAnimation(.smooth(duration: 1.2)) {
            camera = .camera(MapCamera(centerCoordinate: coordinate, distance: zoom))
        }
        if apply {
            Task { await session.apply() }
        }
    }

    private func region(_ c: CLLocationCoordinate2D) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: c, latitudinalMeters: 1500, longitudinalMeters: 1500))
    }

    private func showDemo() {
        switch Demo.screen {
        case .search:
            search.query = Demo.query
        case .favorites:
            showFavorites = true
        case .map, nil:
            break
        }
    }

    private func saveFavorite() {
        let name = favoriteName.trimmingCharacters(in: .whitespaces)
        let c = session.target
        favorites.items.append(Favorite(
            name: name.isEmpty ? CoordinateParser.format(c) : name,
            latitude: c.latitude,
            longitude: c.longitude))
    }
}

private enum Metrics {
    static let margin: CGFloat = 12
    static let control: CGFloat = 46
    static let barTop: CGFloat = 4
    static let barBottom: CGFloat = barTop + control
    static let compassGap: CGFloat = 7.5
    static let dropdownGap: CGFloat = 8
    static let dropdownMaxHeight: CGFloat = 320
    static let panelRadius: CGFloat = 30
    static let legalZone = CGSize(width: 170, height: 44)
}

private let longPressDuration = 0.3

private extension View {
    /// Reports where the finger is as soon as the press is long enough, while it is still down.
    @ViewBuilder
    func onLongPress(_ action: @escaping (CGPoint) -> Void) -> some View {
        if #available(iOS 18, *) {
            gesture(LongPressRecognizer(action: action))
        } else {
            // SwiftUI only reports the position again once the finger moves or lifts.
            simultaneousGesture(
                LongPressGesture(minimumDuration: longPressDuration)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onEnded { value in
                        guard case .second(true, let drag?) = value,
                              hypot(drag.translation.width, drag.translation.height) < 10 else { return }
                        action(drag.startLocation)
                    })
        }
    }
}

@available(iOS 18, *)
private struct LongPressRecognizer: UIGestureRecognizerRepresentable {
    let action: (CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = longPressDuration
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { action(context.converter.location(in: .global)) }
    }

    /// Keeps panning and zooming the map working next to the long press.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
