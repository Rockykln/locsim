import LocSimCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var session: SimulationSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var recents: RecentList
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage(SettingsKey.hostname) private var hostname = Defaults.hostname
    @AppStorage(SettingsKey.port) private var port = ""
    @AppStorage(SettingsKey.resend) private var resend = Defaults.resend
    @AppStorage(SettingsKey.keepAlive) private var keepAlive = true
    @AppStorage(SettingsKey.autoMount) private var autoMount = true
    @AppStorage(SettingsKey.mapStyle) private var mapStyle = MapStyleOption.standard.rawValue
    @AppStorage(SettingsKey.precision) private var precision = 5
    @AppStorage(SettingsKey.coordinateFormat) private var coordinateFormat = CoordinateFormat.decimal.rawValue
    @AppStorage(SettingsKey.zoom) private var zoom = ZoomOption.district.rawValue
    @AppStorage(SettingsKey.autoApply) private var autoApply = false
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.recentsEnabled) private var recentsEnabled = true
    @AppStorage(SettingsKey.liveActivity) private var liveActivity = true

    @State private var importing = false
    // Read in onAppear: an initial value here would touch the disk every time the parent redraws.
    @State private var hasPairing = false
    @State private var ddiDownloaded = false
    @State private var ddiLoading = false
    @State private var ddiError: String?
    @State private var pairingMessage: String?
    @State private var showWelcome = false
    @State private var confirmRemove = false
    @State private var webPage: WebPage?

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                pairingSection
                mapSection
                connectionSection
                ddiSection
                Section {
                    NavigationLink {
                        LogView(log: session.log).environmentObject(session)
                    } label: {
                        LogRow(log: session.log, label: item)
                    }
                }
                aboutSection
            }
            .onAppear(perform: readFiles)
            .onChange(of: session.state) { _, _ in readFiles() }
            // A file copied in by the setup script replaces the stored one; the old connection must go.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                if PairingStore.adoptNow() { pairingReplaced() }
                hasPairing = PairingStore.exists
            }
            .sheet(isPresented: $showWelcome, onDismiss: {
                hasPairing = PairingStore.exists
                pairingMessage = nil
            }) {
                WelcomeView(fromSettings: true).environmentObject(session)
            }
            .webPageSheet($webPage)
            .confirmationDialog("Remove the pairing file?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove Pairing File", role: .destructive) {
                    PairingStore.remove()
                    hasPairing = false
                    Task { await session.pairingChanged() }
                }
            } message: {
                Text("A running simulation stops. You need the setup script to create a new one.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList, .xml, .data]) { result in
                do {
                    try PairingStore.importFile(at: result.get())
                    pairingMessage = nil
                    pairingReplaced()
                    announce(String(localized: "Pairing file imported"))
                } catch {
                    let deviceError = error as? DeviceError ?? DeviceError(.pairingInvalid, error.localizedDescription)
                    pairingMessage = AppError(deviceError).summary
                    announce(pairingMessage)
                }
                hasPairing = PairingStore.exists
            }
        }
    }

    private func pairingReplaced() {
        Task {
            if session.isPreview { session.endPreview() }
            await session.pairingChanged()
            await session.checkPairing()
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stateTitle)
                        .font(.headline)
                    if let detail = stateDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if session.isPreview || session.active != nil || session.state == .connecting {
                    Button(session.isPreview ? String(localized: "End Preview") : String(localized: "Clear")) {
                        if session.isPreview {
                            session.endPreview()
                        } else {
                            Task { await session.clear() }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var pairingSection: some View {
        Section {
            item("Pairing File", "key.fill", .orange,
                 value: hasPairing ? String(localized: "Imported") : String(localized: "Missing"))
            Button {
                importing = true
            } label: {
                item(hasPairing ? "Replace Pairing File" : "Import Pairing File", "square.and.arrow.down.fill", .blue)
            }
            .foregroundStyle(.primary)
            if hasPairing {
                PairingCheckRow {
                    item("Check Pairing File", "checkmark.shield.fill", .green)
                }
                .foregroundStyle(.primary)
                Button(role: .destructive) {
                    confirmRemove = true
                } label: {
                    item("Remove Pairing File", "trash.fill", .red)
                }
                .foregroundStyle(.red)
            }
            Button {
                showWelcome = true
            } label: {
                item("Setup Steps", "list.number", .gray)
            }
            .foregroundStyle(.primary)
        } header: {
            Text("Pairing")
        } footer: {
            if let pairingMessage {
                ErrorFooter(pairingMessage)
            } else if PairingStore.rejectedDrop {
                ErrorFooter(String(localized: "The pairing file was not valid and has been removed. Run the setup script again."))
            } else {
                Text("Created once with the setup script on a computer.")
            }
        }
    }

    private var mapSection: some View {
        Section {
            Picker(selection: $mapStyle) {
                ForEach(MapStyleOption.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                item("Map Style", "map.fill", .teal)
            }
            Picker(selection: $zoom) {
                ForEach(ZoomOption.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                item("Zoom on Selection", "plus.magnifyingglass", .teal)
            }
            Picker(selection: $coordinateFormat) {
                ForEach(CoordinateFormat.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                item("Coordinate Format", "globe.europe.africa", .teal)
            }
            if coordinateFormat == CoordinateFormat.decimal.rawValue {
                Stepper(value: $precision, in: 3...7) {
                    item("Decimal Places", "number", .teal, value: "\(precision)")
                }
            }
            Toggle(isOn: $autoApply) {
                item("Set on Selection", "location.fill", .red)
            }
            Toggle(isOn: $haptics) {
                item("Haptics", "iphone.radiowaves.left.and.right", .pink)
            }
            Toggle(isOn: $recentsEnabled) {
                item("Recent Locations", "clock.fill", .gray, value: recentsEnabled ? "\(recents.items.count)" : nil)
            }
            .onChange(of: recentsEnabled) { _, on in if !on { recents.clear() } }
            Toggle(isOn: $liveActivity) {
                item("Live Activity", "platter.filled.bottom.iphone", .blue)
            }
            .onChange(of: liveActivity) { _, _ in session.liveActivityChanged() }
        } header: {
            Text("Map")
        } footer: {
            Text("Set on Selection sends a choice right away. Recent Locations keeps the last five.")
        }
    }

    private var connectionSection: some View {
        Section {
            field("Port", "number", .blue, text: $port, placeholder: String(localized: "Auto"))
            field("Hostname", "desktopcomputer", .blue, text: $hostname,
                  placeholder: Defaults.hostname, keyboard: .asciiCapable)
            Stepper(value: $resend, in: 3...60) {
                item("Resend Interval", "arrow.clockwise", .green,
                     value: Duration.seconds(resend).formatted(.units(allowed: [.seconds], width: .abbreviated)))
            }
            Toggle(isOn: $keepAlive) {
                item("Keep Alive in Background", "moon.fill", .indigo)
            }
            .onChange(of: keepAlive) { _, on in session.keepAliveChanged(on) }
        } header: {
            Text("Connection")
        } footer: {
            if !port.isEmpty, UInt16(port).map({ $0 > 0 }) != true {
                ErrorFooter(String(localized: "Port must be a number from 1 to 65535. Leave it empty to find it automatically."))
            } else {
                Text("Connecting needs Wi-Fi, then cellular works too. “Keep Alive in Background” keeps the simulation running in the background.")
            }
        }
    }

    private var ddiSection: some View {
        Section {
            item("Files", "externaldrive.fill", .purple,
                 value: ddiDownloaded ? String(localized: "Downloaded") : String(localized: "Not downloaded"))
            Toggle(isOn: $autoMount) {
                item("Mount Automatically", "arrow.down.circle.fill", .purple)
            }
            if ddiDownloaded {
                Button(role: .destructive) {
                    DDIStore.remove()
                    ddiDownloaded = false
                } label: {
                    item("Delete DDI Files", "trash.fill", .red)
                }
                .foregroundStyle(.red)
            } else {
                Button {
                    downloadDDI()
                } label: {
                    HStack {
                        item("Download DDI Files", "arrow.down.to.line", .purple)
                        if ddiLoading { ProgressView() }
                    }
                }
                .disabled(ddiLoading)
            }
        } header: {
            Text("Developer Disk Image")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let ddiError { ErrorFooter(ddiError) }
                Text("Needed if iOS does not provide it. About 16 MB from GitHub, can be downloaded here in advance.")
            }
        }
    }

    private func downloadDDI() {
        ddiLoading = true
        ddiError = nil
        Task {
            defer { ddiLoading = false }
            do {
                try await session.downloadDDI()
                announce(String(localized: "Developer Disk Image downloaded"))
            } catch {
                ddiError = AppError(error).summary
                announce(ddiError)
            }
            ddiDownloaded = DDIStore.isDownloaded(DDIMethod.current)
        }
    }

    // The result appears in a footer VoiceOver would not reach on its own.
    private func announce(_ text: String?) {
        guard let text else { return }
        AccessibilityNotification.Announcement(text).post()
    }

    private var aboutSection: some View {
        Section {
            item("Version", "info.circle.fill", .gray, value: AppLinks.version)
            item("Commit", "number.circle.fill", .gray, value: AppLinks.commit)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                HStack {
                    item("Language", "globe", .blue, value: AppLinks.languageName)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary)
            NavigationLink {
                AcknowledgementsView()
            } label: {
                item("Acknowledgements", "doc.text.fill", .gray)
            }
            externalLink("Privacy Policy", "hand.raised.fill", .blue, AppLinks.privacy)
            externalLink("Support", "questionmark.circle.fill", .blue, AppLinks.support)
            externalLink("Website", "safari.fill", .blue, AppLinks.website)
            externalLink("Repository", "chevron.left.forwardslash.chevron.right", .indigo, AppLinks.repository)
        } header: {
            // The support page and the problem report point here for version and commit.
            Text("About")
        }
    }

    private func externalLink(_ title: LocalizedStringKey, _ symbol: String, _ color: Color, _ url: URL) -> some View {
        Button {
            webPage = WebPage(url: url)
        } label: {
            HStack {
                item(title, symbol, color)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.primary)
    }

    private func readFiles() {
        hasPairing = PairingStore.exists
        ddiDownloaded = DDIStore.isDownloaded(DDIMethod.current)
    }

    private func item(
        _ title: LocalizedStringKey, _ symbol: String, _ color: Color, value: String? = nil
    ) -> some View {
        // At large text sizes the value goes below the title, which then has the full width.
        let stacked = dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if let value, !stacked { valueText(value) }
            }
            if let value, stacked { valueText(value) }
        }
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private func field(
        _ title: LocalizedStringKey, _ symbol: String, _ color: Color, text: Binding<String>, placeholder: String,
        keyboard: UIKeyboardType = .numbersAndPunctuation
    ) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            item(title, symbol, color)
            TextField(placeholder, text: text)
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(keyboard)
                // Without it VoiceOver reads only the placeholder, e.g. "Auto".
                .accessibilityLabel(Text(title))
        }
    }

    private var stateTitle: String {
        switch session.state {
        case .idle: return String(localized: "Not active")
        case .connecting: return String(localized: "Connecting")
        case .active: return session.isPreview ? String(localized: "Preview") : String(localized: "Active")
        case .reconnecting: return String(localized: "Reconnecting")
        case .failed(let error): return error.title
        }
    }

    private var stateDetail: String? {
        switch session.state {
        case .active:
            var parts: [String] = []
            if let active = session.active { parts.append(CoordinateParser.format(active)) }
            if let port = session.port { parts.append(String(localized: "Port \(Int(port))")) }
            if session.isPreview { parts.append(String(localized: "The location of this iPhone does not change.")) }
            return parts.joined(separator: " · ")
        case .reconnecting(let error), .failed(let error): return error.messageWithCode
        default: return nil
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .active: return .green
        case .failed: return .red
        case .connecting, .reconnecting: return .orange
        case .idle: return .gray
        }
    }
}

/// Observes the log on its own, so Settings is not redrawn for every new line.
private struct LogRow<Label: View>: View {
    @ObservedObject var log: LogStore
    let label: (LocalizedStringKey, String, Color, String?) -> Label

    var body: some View {
        label("Log", "text.alignleft", .gray, "\(log.lines.count)")
    }
}

struct LogView: View {
    @EnvironmentObject private var session: SimulationSession
    @ObservedObject var log: LogStore

    var body: some View {
        ScrollView {
            if log.lines.isEmpty {
                ContentUnavailableView("No Entries", systemImage: "text.alignleft")
                    .padding(.top, 80)
            } else {
                // One text per line: VoiceOver can step through them, and only new lines are laid out.
                // No text selection: the system copy would go through Universal Clipboard.
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(log.lines) { line in
                        Text(line.text)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .defaultScrollAnchor(.bottom)
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    // The log holds coordinates; keep it off the user's other devices.
                    Clipboard.copy(log.text, expiresAfter: 600)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy Log")
                Button(role: .destructive) {
                    session.clearLog()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Clear Log")
            }
        }
    }
}

/// Footer for an error: the icon carries the color, the text stays readable.
struct ErrorFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }
}
