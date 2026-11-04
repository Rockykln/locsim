import LocSimCore
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct MapScreen: View {
    @EnvironmentObject private var session: SimulationSession
    @EnvironmentObject private var favorites: FavoriteList
    @EnvironmentObject private var recents: RecentList
    @StateObject private var search = PlaceSearch()
    @State private var camera: MapCameraPosition = .automatic
    @State private var showSettings = false
    @State private var showWelcome = false
    @State private var showFavorites = false
    @State private var favoritePick: Favorite?
    @State private var naming = false
    @State private var favoriteName = ""
    @State private var searchError: String?
    @State private var shownError: AppError?
    @State private var droppedPins = 0
    @State private var feedback = 0
    @State private var resolving: String?
    @State private var mapCenter: CLLocationCoordinate2D?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var locationOff = false
    @State private var question: AppError?
    @State private var webPage: WebPage?
    @State private var suggestionsHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @Namespace private var mapScope
    @State private var mapBottom: CGFloat = 0
    @State private var panelTop: CGFloat = .infinity
    @State private var topBarBottom: CGFloat = 0
    @State private var panelContentHeight: CGFloat = 0
    @State private var locateTask: Task<Void, Never>?
    // Annotations added before the map has settled stay invisible until the next redraw.
    @State private var mapReady = false
    // Cancelled by any newer choice, so a late result cannot move the pin back.
    @State private var searchTask: Task<Void, Never>?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Shown while nothing is simulated, once location access is allowed.
    @State private var showsUserLocation = false
    @AppStorage(SettingsKey.mapStyle) private var mapStyle = MapStyleOption.standard.rawValue
    @AppStorage(SettingsKey.zoom) private var zoom = ZoomOption.block.rawValue
    @AppStorage(SettingsKey.autoApply) private var autoApply = false
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.precision) private var precision = 5
    @AppStorage(SettingsKey.coordinateFormat) private var coordinateFormat = CoordinateFormat.decimal.rawValue
    @AppStorage(SettingsKey.recentsEnabled) private var recentsEnabled = true

    // Split in three: as one chain of modifiers the body is too much for the type checker.
    var body: some View {
        withPresentations(withFeedback(layers))
            .onAppear {
                let start: MapCameraPosition = Demo.camera
                    ?? .camera(MapCamera(centerCoordinate: session.target, distance: zoom))
                camera = start
                mapCenter = session.target
                showRealPositionIfAllowed()
                if !session.hasPairing { showWelcome = true }
                showDemo()
            }
    }

    private var layers: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea()
            topBar
                .frame(maxWidth: 640)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { topBarBottom = $0 }
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
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .top) {
            dropdown
                .padding(.horizontal, Metrics.margin)
                .padding(.top, Metrics.barBottom + Metrics.dropdownGap)
                .frame(maxWidth: 640)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .ignoresSafeArea(.keyboard)
        .mapScope(mapScope)
    }

    private func withFeedback(_ content: some View) -> some View {
        content
        .sensoryFeedback(trigger: session.setCount) { _, _ in haptics ? .success : nil }
        .onChange(of: session.setCount) { _, _ in
            AccessibilityNotification.Announcement(String(localized: "Location set")).post()
            // A Shortcut can set a place the map does not show; the map follows it there.
            if let active = session.active, !isVisible(active) { fly(to: active) }
        }
        .sensoryFeedback(trigger: session.state) { old, new in
            guard haptics, old != new, case .failed = new else { return nil }
            return .error
        }
        .sensoryFeedback(trigger: feedback) { _, _ in haptics ? .impact(weight: .light) : nil }
        .onChange(of: session.state) { old, new in
            announce(old, new)
            if let error = new.error, [AppError.ddiConsentCode, AppError.otherVPNCode].contains(error.code) {
                question = error
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
    }

    private func withPresentations(_ content: some View) -> some View {
        content
        .sheet(isPresented: $showWelcome) {
            WelcomeView().environmentObject(session)
        }
        .webPageSheet($webPage)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(session)
                .environmentObject(recents)
        }
        // The pick is applied once the sheet is gone: a setup sheet opened while this one
        // is still closing would not appear.
        .sheet(isPresented: $showFavorites, onDismiss: {
            guard let favorite = favoritePick else { return }
            favoritePick = nil
            select(favorite.coordinate, name: favorite.name, apply: autoApply)
        }) {
            FavoritesView { favorite in
                favoritePick = favorite
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
            Button("Copy Details") { Clipboard.copy(error.report) }
            Button("OK", role: .cancel) {}
        } message: { error in
            Text("\(error.message)\n\nError \(error.code)")
        }
        .alert(
            question?.title ?? "",
            isPresented: Binding(get: { question != nil }, set: { if !$0 { question = nil } }),
            presenting: question
        ) { error in
            // Setting the location again answers both questions; the session reads the error.
            Button(error.code == AppError.ddiConsentCode ? String(localized: "Download") : String(localized: "Continue")) {
                Task { await session.apply() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .alert("Location access is off", isPresented: $locationOff) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow location access for LocSim in Settings to show your position.")
        }
        .alert("Save favorite", isPresented: $naming) {
            TextField("Name", text: $favoriteName)
            Button("Save") { saveFavorite() }
            Button("Cancel", role: .cancel) {}
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
                            .accessibilityLabel(session.targetName ?? String(localized: "Dropped pin"))
                            .accessibilityValue(CoordinateParser.spoken(session.target))
                    }
                    // The panel already shows the name.
                    .annotationTitles(.hidden)
                }
                if mapReady, let active = session.active, !activeIsAtPin {
                    Annotation(String(localized: "Active"), coordinate: active) {
                        ActiveDot()
                            .accessibilityLabel("Active location")
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
                mapCenter = context.region.center
                visibleRegion = context.region
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
            // Long press has no VoiceOver equivalent.
            .accessibilityAction(named: "Drop Pin at Map Center") { dropPinAtCenter() }
        }
    }

    // MapKit picks the order of separate annotations, so at the same spot they are drawn as one.
    private var activeIsAtPin: Bool {
        guard let active = session.active else { return false }
        return abs(active.latitude - session.target.latitude) < 1e-7
            && abs(active.longitude - session.target.longitude) < 1e-7
    }

    private func dropPinAtCenter() {
        guard let center = mapCenter else { return }
        searchTask?.cancel()
        locateTask?.cancel()
        session.target = center
        session.targetName = nil
        droppedPins += 1
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
                webPage = WebPage(url: AppLinks.website)
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
            Label {
                Text(searchError).foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .task(id: searchError) {
                AccessibilityNotification.Announcement(searchError).post()
                // VoiceOver users need longer: the message is read out, then found again by swiping.
                let seconds: UInt64 = UIAccessibility.isVoiceOverRunning ? 12 : 4
                // Cancelled by a newer error, which must stay for its own time.
                guard (try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)) != nil else { return }
                self.searchError = nil
            }
        } else if searchFocused || Demo.screen == .search || Demo.screen == .recents, hasSuggestions {
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
                .onChange(of: searchFocused) { _, focused in if !focused { searchError = nil } }
            if resolving != nil, !search.query.isEmpty, search.completions.isEmpty {
                ProgressView().controlSize(.small)
            }
            if !search.query.isEmpty {
                Button {
                    search.reset()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(uiColor: .systemGray))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.trailing, -12)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Metrics.control)
        .glassCapsule(interactive: true)
    }

    private var hasSuggestions: Bool {
        // An empty field offers pasting and the last locations.
        guard !search.query.trimmingCharacters(in: .whitespaces).isEmpty else { return Demo.screen != .search }
        return search.coordinate != nil || !search.completions.isEmpty || search.hasNoMatches
            || Demo.suggestions != nil
    }

    private var showsRecents: Bool { recentsEnabled && !recents.items.isEmpty }

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
            if search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyQueryRows
            }
            if search.hasNoMatches {
                Text("No suggestions. Tap Search to look it up.")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .systemGray))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
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
                    suggestionRow(icon: "mappin", title: completion.title, subtitle: completion.subtitle,
                                  loading: resolving == completion.id) {
                        searchTask?.cancel()
                        resolving = completion.id
                        searchTask = Task {
                            await pick(completion)
                            if resolving == completion.id { resolving = nil }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // Paste goes through the system button, which reads the clipboard without a permission prompt.
    @ViewBuilder
    private var emptyQueryRows: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .frame(width: 20)
                .foregroundStyle(Color(uiColor: .systemGray))
                .accessibilityHidden(true)
            Text("Coordinates or a Maps link")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .systemGray))
                .lineLimit(2)
            Spacer(minLength: 8)
            if resolving != nil {
                ProgressView().controlSize(.small)
            } else if Demo.isOn {
                // The Simulator's pasteboard is not reliable for screenshots; this looks like the
                // enabled system button.
                Button(String(localized: "Paste", comment: "Demo stand-in for the system paste button")) {}
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            } else {
                // Links copied from Maps or Safari are often only a URL on the pasteboard, not text.
                PasteButton(supportedContentTypes: [.plainText, .text, .url]) { providers in
                    Task { @MainActor in
                        if let text = await Self.pastedText(providers) { paste(text) }
                    }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        if showsRecents {
            Divider().overlay(Color(uiColor: .opaqueSeparator)).padding(.leading, 44)
            HStack {
                Text("Recent")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemGray))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(String(localized: "Clear List", defaultValue: "Clear", comment: "Removes all recent locations")) {
                    recents.clear()
                    feedback += 1
                }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Clear recent locations")
                // Lines up with the label inside the paste button above, not with its edge.
                .padding(.trailing, 12)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
            ForEach(recents.items) { item in
                suggestionRow(
                    icon: "clock",
                    title: item.name ?? CoordinateParser.format(item.coordinate),
                    subtitle: item.name == nil ? "" : CoordinateParser.format(item.coordinate)
                ) {
                    select(item.coordinate, name: item.name, apply: autoApply)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        recents.remove(item)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                // A context menu is hard to reach with VoiceOver.
                .accessibilityAction(named: "Remove") { recents.remove(item) }
            }
        }
    }

    private func paste(_ text: String) {
        if let coordinate = CoordinateParser.parse(text) {
            let name = MapLink.url(in: text).flatMap(MapLink.placeName)
            select(coordinate, name: name, apply: autoApply)
        } else if MapLink.url(in: text).map(MapLink.isMap) == true {
            searchTask?.cancel()
            resolving = text
            searchTask = Task { await openLink(text) }
        } else {
            // Not a coordinate or Maps link: search for it like typed text.
            search.query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Text first, since it can hold the place name next to the link; a bare URL otherwise.
    private static func pastedText(_ providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            // A file URL is where iOS put a copy of the data, not what was copied.
            if let text = await load(String.self, from: provider)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty, !text.lowercased().hasPrefix("file:") {
                return text
            }
        }
        for provider in providers {
            if let url = await load(URL.self, from: provider), !url.isFileURL { return url.absoluteString }
        }
        return nil
    }

    private static func load<T: _ObjectiveCBridgeable & Sendable>(
        _ type: T.Type, from provider: NSItemProvider
    ) async -> T? where T._ObjectiveCType: NSItemProviderReading {
        guard provider.canLoadObject(ofClass: type) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
        }
    }

    private func openLink(_ text: String) async {
        defer { if resolving == text { resolving = nil } }
        do {
            guard let place = try await search.place(fromLink: text) else { return }
            guard !Task.isCancelled else { return }
            select(place.coordinate, name: place.name, apply: autoApply)
        } catch {
            guard !Task.isCancelled else { return }
            searchError = error.localizedDescription
        }
    }

    private func suggestionRow(
        icon: String, title: String, subtitle: String, loading: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(Color(uiColor: .systemGray))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .systemGray))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if loading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loading)
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
        .accessibilityShowsLargeContentViewer()
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
        // The map itself is hard to reach with VoiceOver, so the action is offered here too.
        .accessibilityAction(named: "Drop Pin at Map Center") { dropPinAtCenter() }
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

    /// Only the part of the map between the top bar and the panel counts as visible.
    // Only read for its authorization status; one instance instead of a new one per state change.
    private static let locationManager = CLLocationManager()

    private func isVisible(_ c: CLLocationCoordinate2D) -> Bool {
        guard let r = visibleRegion, r.span.latitudeDelta > 0, mapBottom > 0 else { return false }
        guard abs(c.longitude - r.center.longitude) <= r.span.longitudeDelta / 2 else { return false }
        // Close enough on the spans a camera move can leave; the map is shown from the top of the screen.
        let y = (r.center.latitude + r.span.latitudeDelta / 2 - c.latitude) / r.span.latitudeDelta * mapBottom
        return y > topBarBottom && y < min(panelTop, mapBottom)
    }

    private func fly(to coordinate: CLLocationCoordinate2D, duration: Double = 1.0) {
        let target = MapCameraPosition.camera(MapCamera(centerCoordinate: coordinate, distance: zoom))
        if reduceMotion {
            camera = target
        } else {
            withAnimation(.smooth(duration: duration)) { camera = target }
        }
    }

    // Never asks for permission; that happens when the user taps the locate button.
    private func showRealPositionIfAllowed() {
        // After a failed Clear the simulation may still be in force.
        guard !Demo.isOn, session.active == nil, session.state.error?.code != AppError.clearFailedCode else {
            return
        }
        switch Self.locationManager.authorizationStatus {
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
            // Only an earlier denial needs an explanation, not the answer just given.
            if !wasAsked { locationOff = true }
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
        } else if reduceMotion {
            camera = .userLocation(fallback: camera)
        } else {
            withAnimation { camera = .userLocation(fallback: camera) }
        }
    }

    private var bottomPanel: some View {
        // At the largest text sizes on small iPhones the panel can grow past the top bar;
        // then it scrolls instead. Its height follows the content, so a short panel stays short.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    // Inside the scroll view, so scrolled text reaches the rounded edge instead of being cut.
                    panelContent
                        .padding(18)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelContentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: panelContentHeight > 0 ? min(panelContentHeight, Metrics.panelMaxHeight) : nil)
            } else {
                panelContent
                    .padding(18)
            }
        }
        .glassPanel(cornerRadius: Metrics.panelRadius)
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, 4)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { panelTop = $0 }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.targetName ?? String(localized: "Dropped pin"))
                        .font(.headline)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    Text(CoordinateParser.format(session.target))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(CoordinateParser.spoken(session.target))
                        // Own menu instead of text selection, which would copy through Universal Clipboard.
                        .contextMenu {
                            Button {
                                Clipboard.copy(CoordinateParser.format(session.target))
                                feedback += 1
                            } label: {
                                Label("Copy Coordinates", systemImage: "doc.on.doc")
                            }
                        }
                        .accessibilityAction(named: "Copy Coordinates") {
                            Clipboard.copy(CoordinateParser.format(session.target))
                            feedback += 1
                        }
                }
                Spacer(minLength: 0)
                favoriteButton
            }

            if let error = session.state.error {
                Button {
                    shownError = error
                } label: {
                    status
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows error details")
            } else {
                status
                    .accessibilityElement(children: .combine)
            }

            if session.isPreview {
                let row = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
                row {
                    Label("Preview: the location of this iPhone does not change.", systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Button("End Preview") {
                        session.endPreview()
                        if !session.hasPairing { showWelcome = true }
                    }
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }

            if session.backgroundDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label {
                        Text("Without location access, the simulation stops in the background. Tap to allow.")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            // Stacked at large text sizes, so neither label is cut off.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Button {
                    setLocation()
                } label: {
                    HStack(spacing: 8) {
                        if session.state == .connecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text(session.state == .connecting ? String(localized: "Connecting") : String(localized: "Set Location"))
                    }
                    .font(.body.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .primaryButton()
                .disabled(session.state == .connecting)

                Button {
                    feedback += 1
                    Task { await session.clear() }
                } label: {
                    // While connecting this stops the attempt.
                    Label(session.state == .connecting ? String(localized: "Cancel") : String(localized: "Clear"),
                          systemImage: "arrow.uturn.backward")
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                        .padding(.vertical, 6)
                }
                .secondaryButton()
                .disabled(!session.canClear)
            }
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            if session.state.isFailure {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var favoriteButton: some View {
        let saved = favorites.favorite(at: session.target)
        return Button {
            if let saved {
                favorites.items.removeAll { $0.id == saved.id }
                feedback += 1
            } else {
                favoriteName = session.targetName ?? ""
                naming = true
            }
        } label: {
            Image(systemName: saved == nil ? "star" : "star.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(saved == nil ? Color.primary : Color.yellow)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle()
        .accessibilityLabel(saved == nil ? String(localized: "Save favorite") : String(localized: "Remove favorite"))
    }

    private func announce(_ old: SimulationSession.State, _ new: SimulationSession.State) {
        guard old != new else { return }
        let text: String
        switch new {
        case .idle where old == .active: text = String(localized: "Location cleared")
        case .reconnecting(let error) where !old.isReconnecting:
            text = String(localized: "Reconnecting: \(error.title)", comment: "VoiceOver announcement, then the error title")
        case .failed(let error): text = error.title
        default: return
        }
        AccessibilityNotification.Announcement(text).post()
    }

    private var statusLine: String {
        // Until the device answers, the state still says active although the location is going.
        if session.isClearing { return String(localized: "Clearing") }
        var parts: [String] = []
        switch session.state {
        case .idle: parts.append(String(localized: "Not active"))
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
        if session.isClearing { return .orange }
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
            select(coordinate, name: MapLink.url(in: search.query).flatMap(MapLink.placeName), apply: autoApply)
            return
        }
        if MapLink.url(in: search.query).map(MapLink.isMap) == true {
            paste(search.query)
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
        fly(to: coordinate, duration: 1.2)
        if apply { setLocation() }
    }

    /// Every Set goes through here; without a pairing file it opens the setup steps instead.
    private func setLocation() {
        searchFocused = false
        guard session.hasPairing else {
            showWelcome = true
            return
        }
        Task { await session.apply() }
    }

    private func showDemo() {
        switch Demo.screen {
        case .search:
            search.query = Demo.query
        case .favorites:
            showFavorites = true
        case .map, .recents, .live, nil:
            break
        }
    }

    private func saveFavorite() {
        let name = favoriteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = session.target
        guard favorites.favorite(at: c) == nil else { return }
        feedback += 1
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
    // Leaves the top bar free on a 667 pt iPhone SE at the largest text sizes.
    static let panelMaxHeight: CGFloat = 420
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
