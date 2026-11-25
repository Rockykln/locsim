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
    @State private var notes = PairingNotes()
    @State private var appeared = false
    /// Opened from Settings rather than on first launch.
    var fromSettings = false

    private var hasPairing: Bool { notes.hasPairing }

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
                         "When you first set a location, iOS asks to add a VPN configuration. LocSim only uses it to reach this iPhone; no traffic leaves the device through it. If another VPN is selected, iOS turns it off.")
                } footer: {
                    PairingFooter(notes: notes)
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
            .pairingImporter(isPresented: $importing, notes: $notes)
            // The setup script copies the file in over USB while this screen is open.
            .task(id: hasPairing) {
                while !hasPairing {
                    // A cancelled task stops here; otherwise it would report the same file twice.
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                    guard scenePhase == .active else { continue }
                    readPairing()
                }
            }
            .onAppear(perform: readPairing)
            // Picks up a file copied through the Files tab while the app was in the background.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                readPairing()
            }
        }
    }

    /// Takes in a file the setup script dropped into Documents and shows the current state.
    private func readPairing() {
        let adopted = session.adoptDroppedPairing()
        let had = notes.hasPairing
        notes.refresh()
        // A file taken in replaces whatever an earlier import failed with.
        if adopted { notes.message = nil }
        // A file the setup script copied in over USB: the checkmark alone is not announced.
        if appeared, !had, notes.hasPairing {
            AccessibilityNotification.Announcement(String(localized: "Pairing file imported")).post()
        }
        appeared = true
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
                // Each step has at most one action, so the whole row can take the tap: the
                // button alone is less than 44 pt high.
                action()
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
    @State private var vpnNotice = false

    var body: some View {
        Button {
            // The check starts the local connection, which may add the VPN configuration for the first time.
            Task {
                if await session.needsVPNNotice() { vpnNotice = true } else { await session.checkPairing() }
            }
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
        .disabled(session.state == .connecting || session.state.isReconnecting || session.pairingCheck == .checking)
        .alert(AppError(DeviceError(.vpnNotice, "")).title, isPresented: $vpnNotice) {
            // Only Continue: a notice before a system prompt must lead to it (guideline 5.1.1).
            // The prompt itself can be declined.
            Button("Continue") {
                session.acceptVPNNotice()
                Task { await session.checkPairing() }
            }
        } message: {
            Text(AppError(DeviceError(.vpnNotice, "")).message)
        }
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
        case .unreachable(let error) where [AppError.otherVPNCode, "LS-208", AppError.vpnNoticeCode].contains(error.code):
            // These have one clear fix, which the general text below would not name. With the
            // title: "LocSim's local connection replaces it" needs "Another VPN is selected".
            resultLabel(error.summary, "exclamationmark.triangle.fill", .orange)
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

/// The state of the pairing file as both the setup steps and Settings show it.
/// Copied from PairingStore, which is not observed, so the footer redraws when it changes.
struct PairingNotes {
    var hasPairing = false
    var rejectedDrop = false
    var lockdownDrop = false
    var copiesInFiles: [String] = []
    /// The error of the last import from Files.
    var message: String?
    /// A file picked in Files was imported; it stays where it was.
    var pickedFile = false

    mutating func refresh() {
        let had = hasPairing
        hasPairing = PairingStore.exists
        rejectedDrop = PairingStore.rejectedDrop
        lockdownDrop = PairingStore.lockdownDrop
        copiesInFiles = PairingStore.copiesInDocuments
        // An import error no longer applies once a file arrived or was removed another way.
        if hasPairing != had { message = nil }
        if !hasPairing { pickedFile = false }
    }
}

/// Hints about the pairing file, the same in the setup steps and in Settings.
struct PairingFooter: View {
    let notes: PairingNotes
    var fallback: LocalizedStringKey?

    var body: some View {
        if let message = notes.message {
            ErrorFooter(message)
        } else if notes.rejectedDrop {
            ErrorFooter(String(localized: "The pairing file was not valid and has been removed. Run the setup script again."))
        } else if notes.lockdownDrop, !notes.hasPairing {
            // Kept: it may be the user's own file for another tool.
            ErrorFooter(String(localized: "This is a lockdown pairing file. LocSim needs the RPPairing file from the setup script."))
        } else if !notes.copiesInFiles.isEmpty {
            // Never deleted by LocSim: they may be the user's own copies. Orange text would be too faint.
            let names = notes.copiesInFiles.formatted(.list(type: .and))
            Label {
                if notes.copiesInFiles.count == 1 {
                    Text("A pairing file is still in LocSim's folder in Files: \(names). It contains a key for this device and is part of device backups. Delete it there if you no longer need it.")
                } else {
                    Text("Pairing files are still in LocSim's folder in Files: \(names). They contain a key for this device and are part of device backups. Delete them there if you no longer need them.")
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        } else if notes.pickedFile {
            Text("The file you picked stays where it was. It contains a key for this device; delete it if it is in iCloud Drive or another shared place.")
        } else if let fallback {
            Text(fallback)
        }
    }
}

extension View {
    /// Picks a pairing file in Files and imports it. While a location may be simulated, the
    /// import waits for a confirmation, as removing the file does: it ends the simulation.
    func pairingImporter(isPresented: Binding<Bool>, notes: Binding<PairingNotes>) -> some View {
        modifier(PairingImporter(isPresented: isPresented, notes: notes))
    }
}

private struct PairingImporter: ViewModifier {
    @EnvironmentObject private var session: SimulationSession
    @Binding var isPresented: Bool
    @Binding var notes: PairingNotes
    @State private var pending: URL?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.propertyList, .xml, .data]) { result in
                if case .success(let url) = result, session.mayStillBeSimulated {
                    // After the picker has gone: a dialog asked for while it closes may not appear.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        pending = url
                    }
                } else {
                    finish(result)
                }
            }
            .alert(
                "Replace the pairing file?",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                presenting: pending
            ) { url in
                Button("Replace Pairing File", role: .destructive) {
                    finish(.success(url))
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("A running simulation stops.")
            }
    }

    private func finish(_ result: Result<URL, Error>) {
        let error = session.importPairing(result)
        notes.refresh()
        notes.message = error
        notes.pickedFile = error == nil
        // Shown below the button, where VoiceOver would not find it on its own.
        AccessibilityNotification.Announcement(error ?? String(localized: "Pairing file imported")).post()
    }
}
