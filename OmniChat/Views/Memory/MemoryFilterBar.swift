import SwiftUI

struct MemoryFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedType: MemoryType?
    @Binding var showOnlyPinned: Bool
    @Binding var scopeFilter: ScopeFilter

    enum ScopeFilter: String, CaseIterable {
        case all = "All"
        case global = "Global"
        case workspace = "Workspace"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search memories...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Type filter
                    FilterChip(
                        title: "All",
                        isSelected: selectedType == nil,
                        action: { selectedType = nil }
                    )

                    ForEach(MemoryType.allCases, id: \.self) { type in
                        FilterChip(
                            title: type.rawValue,
                            icon: type.icon,
                            isSelected: selectedType == type,
                            action: { selectedType = type }
                        )
                    }

                    Divider()
                        .frame(height: 20)

                    // Scope filter
                    ForEach(ScopeFilter.allCases, id: \.self) { scope in
                        FilterChip(
                            title: scope.rawValue,
                            isSelected: scopeFilter == scope,
                            action: { scopeFilter = scope }
                        )
                    }

                    Divider()
                        .frame(height: 20)

                    // Pinned filter
                    FilterChip(
                        title: "Pinned",
                        icon: "pin.fill",
                        isSelected: showOnlyPinned,
                        action: { showOnlyPinned.toggle() }
                    )
                }
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}
