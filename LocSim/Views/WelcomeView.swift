import SwiftUI
import UniformTypeIdentifiers

/// Setup steps, shown on launch until a pairing file is imported and from Settings.
struct WelcomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var hasPairing = PairingStore.exists
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A one-time setup with a computer and a USB cable. After that, LocSim works without a computer.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    step(1, "Enable Developer Mode",
                         "Settings > Privacy & Security > Developer Mode. If the switch is missing, the setup guide shows how to make it appear.")
                    step(2, "Create a pairing file", "Run the script from the setup guide on a Mac, Windows or Linux computer.") {
                        Link(destination: AppLinks.setupGuide) {
                            Label("Open Setup Guide", systemImage: "arrow.up.right")
                        }
                    }
                    step(3, "Allow the local connection",
                         "After the import, iOS asks once to add a VPN configuration. LocSim only uses it to reach this iPhone's own developer services while a location is active. It carries no other traffic, nothing leaves the device through it and no data is collected.")
                    step(4, "Import the pairing file", "Copy it to this device with AirDrop or Finder, then import it here.", done: hasPairing) {
                        Button {
                            importing = true
                        } label: {
                            Label(
                                hasPairing ? String(localized: "Replace Pairing File") : String(localized: "Import Pairing File"),
                                systemImage: "square.and.arrow.down")
                        }
                    }
                    if hasPairing {
                        PairingCheckRow {
                            Label("Check Pairing File", systemImage: "checkmark.shield")
                        }
                    }
                } footer: {
                    if let message {
                        Text(message).foregroundStyle(.red)
                    } else if !hasPairing, PairingStore.rejectedDrop {
                        Text("The pairing file in Files was not valid and has been removed. Create a new one with tools/make-pairing.sh.")
                            .foregroundStyle(.red)
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
            .navigationTitle("Welcome to LocSim")
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    (hasPairing ? Text("Get Started") : Text("Later"))
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
                    Task { await session.checkPairing() }
                } catch {
                    let deviceError = error as? DeviceError ?? DeviceError(.pairingInvalid, error.localizedDescription)
                    let appError = AppError(deviceError)
                    message = "\(appError.title): \(appError.message) (\(appError.code))"
                }
                hasPairing = PairingStore.exists
            }
            // Picks up a file copied through the Files tab while the app was in the background.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let hadPairing = hasPairing
                hasPairing = PairingStore.exists
                if hasPairing, !hadPairing { Task { await session.checkPairing() } }
            }
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
                } else {
                    Text(verbatim: "\(number)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.headline)
            .frame(width: 22)
            .accessibilityHidden(true)
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
    @EnvironmentObject private var session: SpoofSession
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
    }

    @ViewBuilder
    private var result: some View {
        switch session.pairingCheck {
        case .notChecked, .checking:
            EmptyView()
        case .valid:
            Label("The pairing file works with this device.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .rejected(let error):
            Label(String("\(error.message) (\(error.code))"), systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .unreachable(let error):
            Label("Could not check. Allow the local connection, join a Wi-Fi network and try again. (\(error.code))",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
