import SwiftUI

struct SidebarView: View {
    let conversations: [Conversation]
    @Binding var selectedConversation: Conversation?
    let onNewChat: () -> Void
    let onDelete: (Conversation) -> Void
    let onOpenMemoryPanel: () -> Void
    let onOpenWorkspacePanel: () -> Void

    @State private var searchText = ""
    @State private var editingConversationId: UUID?

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    /// Group conversations by date category
    private var groupedConversations: [(key: DateGroup, conversations: [Conversation])] {
        let grouped = Dictionary(grouping: filteredConversations) { conversation in
            DateGroup.from(date: conversation.updatedAt)
        }

        // Sort groups: Today first, then Yesterday, then by date descending
        return grouped.sorted { a, b in
            a.key < b.key
        }.map { (key: $0.key, conversations: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedConversation) {
                ForEach(groupedConversations, id: \.key) { group in
                    Section {
                        ForEach(group.conversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isEditing: Binding(
                                    get: { editingConversationId == conversation.id },
                                    set: { newValue in
                                        editingConversationId = newValue ? conversation.id : nil
                                    }
                                )
                            )
                            .tag(conversation)
                            .contextMenu {
                                Button {
                                    editingConversationId = conversation.id
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    onDelete(conversation)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(group.key.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search chats")

            Divider()

            // Panels section at the bottom
            VStack(spacing: 0) {
                Button(action: onOpenMemoryPanel) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                        Text("Memory Panel")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                Button(action: onOpenWorkspacePanel) {
                    HStack {
                        Image(systemName: "folder.badge.gearshape")
                        Text("Workspace Panel")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onNewChat) {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

// MARK: - Date Grouping

/// Represents a date group for conversation organization
enum DateGroup: Hashable, Comparable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case date(year: Int, month: Int)  // For older conversations

    var displayName: String {
        switch self {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .thisWeek:
            return "This Week"
        case .lastWeek:
            return "Last Week"
        case .thisMonth:
            return "This Month"
        case .date(let year, let month):
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMMM yyyy"
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            if let date = Calendar.current.date(from: components) {
                return dateFormatter.string(from: date)
            }
            return "\(month)/\(year)"
        }
    }

    /// Sort order value (lower = appears first)
    private var sortOrder: Int {
        switch self {
        case .today: return 0
        case .yesterday: return 1
        case .thisWeek: return 2
        case .lastWeek: return 3
        case .thisMonth: return 4
        case .date: return 5
        }
    }

    static func < (lhs: DateGroup, rhs: DateGroup) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        // For date groups, sort by date descending (more recent first)
        if case .date(let lyear, let lmonth) = lhs,
           case .date(let ryear, let rmonth) = rhs {
            if lyear != ryear {
                return lyear > ryear  // More recent year first
            }
            return lmonth > rmonth  // More recent month first
        }
        return false
    }

    static func from(date: Date) -> DateGroup {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return .today
        }

        if calendar.isDateInYesterday(date) {
            return .yesterday
        }

        // Check if within this week (last 7 days, excluding today/yesterday)
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
           date > weekAgo {
            return .thisWeek
        }

        // Check if within last week (7-14 days ago)
        if let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now),
           date > twoWeeksAgo {
            return .lastWeek
        }

        // Check if within this month
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return .thisMonth
        }

        // Otherwise group by year-month
        let components = calendar.dateComponents([.year, .month], from: date)
        return .date(year: components.year ?? 0, month: components.month ?? 0)
    }
}

#Preview {
    SidebarView(
        conversations: [
            Conversation(title: "Test Chat 1"),
            Conversation(title: "Another conversation"),
        ],
        selectedConversation: .constant(nil),
        onNewChat: {},
        onDelete: { _ in },
        onOpenMemoryPanel: {},
        onOpenWorkspacePanel: {}
    )
}
