import SwiftUI

// Equatable: the map screen redraws on every resend and would otherwise rebuild this list with it.
struct FavoritesView: View, Equatable {
    @EnvironmentObject private var favorites: FavoriteList
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Favorite?
    @State private var newName = ""
    @State private var copied = 0
    @AppStorage(SettingsKey.haptics) private var haptics = true
    let onSelect: (Favorite) -> Void

    nonisolated static func == (lhs: FavoritesView, rhs: FavoritesView) -> Bool { true }

    var body: some View {
        NavigationStack {
            Group {
                if favorites.items.isEmpty {
                    ContentUnavailableView(
                        "No Favorites",
                        systemImage: "star",
                        description: Text("Save a place with the star next to its coordinates."))
                } else {
                    list
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !favorites.items.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { rename() }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
        // Scene changes report keyboard frames without a keyboard, which would shift the rows.
        .ignoresSafeArea(.keyboard)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var list: some View {
        List {
            ForEach(favorites.items) { favorite in
                Button {
                    onSelect(favorite)
                } label: {
                    row(favorite)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(.secondarySystemGroupedBackground))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        favorites.items.removeAll { $0.id == favorite.id }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        newName = favorite.name
                        renaming = favorite
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    Button {
                        Clipboard.copy(CoordinateParser.format(favorite.coordinate))
                        copied += 1
                    } label: {
                        Label("Copy Coordinates", systemImage: "doc.on.doc")
                    }
                    Button {
                        newName = favorite.name
                        renaming = favorite
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        favorites.items.removeAll { $0.id == favorite.id }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete { favorites.items.remove(atOffsets: $0) }
            .onMove { favorites.items.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.insetGrouped)
        .sensoryFeedback(trigger: copied) { _, _ in haptics ? .success : nil }
    }

    private func row(_ favorite: Favorite) -> some View {
        HStack(spacing: 14) {
            PinGlyph(height: 26)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(favorite.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(CoordinateParser.format(favorite.coordinate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(CoordinateParser.spoken(favorite.coordinate))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func rename() {
        guard let target = renaming,
              let index = favorites.items.firstIndex(where: { $0.id == target.id }) else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { favorites.items[index].name = name }
        renaming = nil
    }
}
