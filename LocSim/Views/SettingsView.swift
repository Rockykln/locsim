import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(SettingsKey.hostname) private var hostname = Defaults.hostname
    @AppStorage(SettingsKey.port) private var port = ""
    @AppStorage(SettingsKey.resend) private var resend = Defaults.resend
    @AppStorage(SettingsKey.keepAlive) private var keepAlive = true
    @AppStorage(SettingsKey.autoMount) private var autoMount = true
    @AppStorage(SettingsKey.mapStyle) private var mapStyle = MapStyleOption.standard.rawValue
    @AppStorage(SettingsKey.precision) private var precision = 5
    @AppStorage(SettingsKey.coordinateFormat) private var coordinateFormat = CoordinateFormat.decimal.rawValue
    @AppStorage(SettingsKey.zoom) private var zoom = ZoomOption.block.rawValue
    @AppStorage(SettingsKey.autoApply) private var autoApply = false
    @AppStorage(SettingsKey.haptics) private var haptics = true

    @State private var importing = false
    @State private var hasPairing = PairingStore.exists
    @State private var ddiDownloaded = DDIStore.isDownloaded(DDIMethod.current)
    @State private var pairingMessage: String?
    @State private var showWelcome = false

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
                        LogView().environmentObject(session)
                    } label: {
                        item("Log", "text.alignleft", .gray, value: "\(session.log.count)")
                    }
                }
                aboutSection
            }
            .onChange(of: session.state) { _, _ in
                hasPairing = PairingStore.exists
                ddiDownloaded = DDIStore.isDownloaded(DDIMethod.current)
            }
            .sheet(isPresented: $showWelcome, onDismiss: {
                hasPairing = PairingStore.exists
                pairingMessage = nil
            }) {
                WelcomeView().environmentObject(session)
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
                    Task { await session.checkPairing() }
                } catch {
                    let deviceError = error as? DeviceError ?? DeviceError(.pairingInvalid, error.localizedDescription)
                    let appError = AppError(deviceError)
                    pairingMessage = "\(appError.title): \(appError.message) (\(appError.code))"
                }
                hasPairing = PairingStore.exists
            }
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)
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
                Spacer(minLength: 0)
                if session.active != nil || session.state == .connecting {
                    Button("Disconnect") { Task { await session.disconnect() } }
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
                    PairingStore.remove()
                    hasPairing = false
                    session.resetPairingCheck()
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
                Text(pairingMessage).foregroundStyle(.red)
            } else if !hasPairing, PairingStore.rejectedDrop {
                Text("The pairing file in Files was not valid and has been removed. Create a new one with tools/make-pairing.sh.")
                    .foregroundStyle(.red)
            } else {
                Text("Create the RPPairing file with tools/make-pairing.sh.")
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
                item("Zoom on Select", "plus.magnifyingglass", .teal)
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
                item("Haptic Feedback", "iphone.radiowaves.left.and.right", .pink)
            }
        } header: {
            Text("Map")
        } footer: {
            Text("Set on Selection sends a search result or favorite immediately.")
        }
    }

    private var connectionSection: some View {
        Section {
            field("Port", "number", .blue, text: $port, placeholder: String(localized: "Auto"))
            field("Hostname", "desktopcomputer", .blue, text: $hostname,
                  placeholder: Defaults.hostname, keyboard: .asciiCapable)
            Stepper(value: $resend, in: 3...60) {
                item("Resend Interval", "arrow.clockwise", .green, value: "\(resend) s")
            }
            Toggle(isOn: $keepAlive) {
                item("Keep Alive in Background", "moon.fill", .indigo)
            }
            .onChange(of: keepAlive) { _, on in session.keepAliveChanged(on) }
        } header: {
            Text("Connection")
        } footer: {
            Text("Wi-Fi is only needed to connect, no internet required. While connected, locations can be changed on cellular. The local connection only reaches this iPhone and carries no other traffic.")
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
                    Label("Delete DDI Files", systemImage: "trash")
                }
            }
        } header: {
            Text("Developer Disk Image")
        } footer: {
            Text("Only downloaded if the device does not provide it. About 16 MB.")
        }
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
                }
            }
            .foregroundStyle(.primary)
            NavigationLink {
                AcknowledgementsView()
            } label: {
                item("Acknowledgements", "doc.text.fill", .gray)
            }
            Link(destination: AppLinks.website) {
                HStack {
                    item("Website", "safari.fill", .blue)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            Link(destination: AppLinks.repository) {
                HStack {
                    item("Repository", "chevron.left.forwardslash.chevron.right", Color(white: 0.25))
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private func item(
        _ title: LocalizedStringKey, _ symbol: String, _ color: Color, value: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func field(
        _ title: LocalizedStringKey, _ symbol: String, _ color: Color, text: Binding<String>, placeholder: String,
        keyboard: UIKeyboardType = .numbersAndPunctuation
    ) -> some View {
        HStack(spacing: 12) {
            item(title, symbol, color)
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(keyboard)
        }
    }

    private var stateTitle: String {
        switch session.state {
        case .idle: return String(localized: "Not connected")
        case .connecting: return String(localized: "Connecting")
        case .active: return String(localized: "Active")
        case .reconnecting: return String(localized: "Reconnecting")
        case .failed(let error): return error.title
        }
    }

    private var stateDetail: String? {
        switch session.state {
        case .active:
            var parts: [String] = []
            if let active = session.active { parts.append(CoordinateParser.format(active)) }
            if let port = session.port { parts.append("\(String(localized: "port")) \(port)") }
            return parts.joined(separator: " · ")
        case .reconnecting(let error), .failed(let error): return "\(error.message) (\(error.code))"
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

struct LogView: View {
    @EnvironmentObject private var session: SpoofSession

    var body: some View {
        ScrollView {
            if session.log.isEmpty {
                ContentUnavailableView("No Entries", systemImage: "text.alignleft")
                    .padding(.top, 80)
            } else {
                Text(session.log.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
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
                    UIPasteboard.general.string = session.log.joined(separator: "\n")
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
