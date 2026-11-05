import SwiftUI
import UniformTypeIdentifiers

/// Setup steps, shown on launch until a pairing file is imported and from Settings.
struct WelcomeView: View {
    @EnvironmentObject private var session: SimulationSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var importing = false
    // Read in onAppear: an initial value here would touch the disk every time the parent redraws.
    @State private var hasPairing = false
    // Copied from PairingStore, which is not observed, so the footer redraws when it changes.
    @State private var rejectedDrop = false
    @State private var message: String?
    /// Opened from Settings rather than on first launch.
    var fromSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Large titles never wrap, so at accessibility sizes the title moves into the list.
                    if dynamicTypeSize.isAccessibilitySize {
                        Text("Welcome to LocSim")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text("A one-time setup with a computer and a USB cable. After that, LocSim works without a computer.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    step(1, "Enable Developer Mode",
                         "Settings > Privacy & Security > Developer Mode. If the switch is missing, the setup guide shows how to make it appear.")
                    step(2, "Allow connections over Wi-Fi",
                         "On the computer, turn on Show this iPhone when on Wi-Fi in Finder or the Apple Devices app.")
                    step(3, "Create the pairing file", "Run the script from the setup guide on a Mac, Windows or Linux computer.") {
                        Link(destination: AppLinks.setupGuide) {
                            Label("Open Setup Guide", systemImage: "arrow.up.right")
                        }
                    }
                    step(4, "Import the pairing file", "The setup script copies it into LocSim. Otherwise, copy it with AirDrop or Finder and import it here.", done: hasPairing) {
                        Button {
                            importing = true
                        } label: {
                            Label(
                                hasPairing ? String(localized: "Replace Pairing File") : String(localized: "Import Pairing File"),
                                systemImage: "square.and.arrow.down")
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if hasPairing {
                        PairingCheckRow {
                            Label("Check Pairing File", systemImage: "checkmark.shield")
                        }
                    }
                    step(5, "Allow the local connection",
                         "When you first set a location, iOS asks to add a VPN configuration. LocSim only uses it to reach this iPhone; no traffic leaves the device through it.")
                } footer: {
                    if let message {
                        ErrorFooter(message)
                    } else if rejectedDrop {
                        ErrorFooter(String(localized: "The pairing file was not valid and has been removed. Run the setup script again."))
                    }
                }
                if !hasPairing {
                    Section {
                        Button {
                            session.startPreview()
                            dismiss()
                        } label: {
                            Label("Try Without a Device", systemImage: "eye")
                        }
                    } footer: {
                        Text("Explore the map, search and favorites without any setup. The location of this iPhone does not change.")
                    }
                }
            }
            .navigationTitle(dynamicTypeSize.isAccessibilitySize ? Text(verbatim: "") : Text("Welcome to LocSim"))
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    (hasPairing ? (fromSettings ? Text("Done") : Text("Get Started")) : Text("Later"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .primaryButton()
                .padding()
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList, .xml, .data]) { result in
                do {
                    try PairingStore.importFile(at: result.get())
                    message = nil
                    pairingReplaced()
                } catch {
                    let deviceError = error as? DeviceError ?? DeviceError(.pairingInvalid, error.localizedDescription)
                    message = AppError(deviceError).summary
                    // Shown below the button, where VoiceOver would not find it on its own.
                    if let message { AccessibilityNotification.Announcement(message).post() }
                }
                readPairing()
            }
            // The setup script copies the file in over USB while this screen is open.
            .task(id: hasPairing) {
                while !hasPairing {
                    // A cancelled task stops here; otherwise it would report the same file twice.
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                    guard scenePhase == .active else { continue }
                    readPairing()
                    if hasPairing { pairingReplaced() }
                }
            }
            .onAppear {
                if PairingStore.adoptNow() { pairingReplaced() }
                readPairing()
            }
            // Picks up a file copied through the Files tab while the app was in the background.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let replaced = PairingStore.adoptNow()
                let hadPairing = hasPairing
                readPairing()
                if replaced || (hasPairing && !hadPairing) { pairingReplaced() }
            }
        }
    }

    private func readPairing() {
        hasPairing = PairingStore.exists
        rejectedDrop = PairingStore.rejectedDrop
    }

    private func pairingReplaced() {
        Task {
            if session.isPreview { session.endPreview() }
            await session.pairingChanged()
            await session.checkPairing()
        }
    }

    private func step<Action: View>(
        _ number: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey, done: Bool = false,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityLabel(String(localized: "Step \(number), done"))
                } else {
                    Text(verbatim: "\(number)").foregroundStyle(.secondary).monospacedDigit()
                        .accessibilityLabel(String(localized: "Step \(number)"))
                }
            }
            .font(.headline)
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                action()
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func step(_ number: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        step(number, title, detail) { EmptyView() }
    }
}

/// Tries the pairing file against the device and shows the result.
struct PairingCheckRow<Title: View>: View {
    @EnvironmentObject private var session: SimulationSession
    /// Off while another row for the same check is on screen.
    var announces = true
    @ViewBuilder let title: () -> Title

    var body: some View {
        Button {
            Task { await session.checkPairing() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    title()
                    Spacer(minLength: 8)
                    if session.pairingCheck == .checking {
                        ProgressView()
                    }
                }
                result
                    .font(.footnote)
            }
        }
        .disabled(session.state == .connecting || session.state.isReconnecting)
        .onChange(of: session.pairingCheck) { _, check in
            guard announces else { return }
            let text: String
            switch check {
            case .valid: text = String(localized: "The pairing file works with this device.")
            case .rejected(let error), .unreachable(let error): text = error.title
            default: return
            }
            AccessibilityNotification.Announcement(text).post()
        }
    }

    @ViewBuilder
    private var result: some View {
        switch session.pairingCheck {
        case .notChecked, .checking:
            EmptyView()
        case .valid:
            resultLabel(String(localized: "The pairing file works with this device."), "checkmark.circle.fill", .green)
        case .rejected(let error):
            resultLabel(error.messageWithCode, "xmark.circle.fill", .red)
        case .unreachable(let error):
            resultLabel(String(localized: "Could not check. Allow the local connection, join a Wi-Fi network and try again. (\(error.code))"),
                   "exclamationmark.triangle.fill", .orange)
        }
    }

    // Only the icon is colored; colored footnote text is too faint to read.
    private func resultLabel(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
    }
}
