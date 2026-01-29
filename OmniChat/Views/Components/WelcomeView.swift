import SwiftUI

struct WelcomeView: View {
    let onNewChat: () -> Void

    private let suggestions = [
        ("lightbulb", "Explain a concept", "Help me understand quantum computing"),
        ("doc.text", "Write content", "Draft an email to my team about..."),
        ("desktopcomputer", "Write code", "Create a Python script that..."),
        ("chart.bar", "Analyze data", "What insights can you find in..."),
    ]

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Logo and title
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("OmniChat")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your unified AI assistant")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Suggestion cards
            VStack(spacing: 12) {
                Text("Try asking about...")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(suggestions, id: \.0) { icon, title, example in
                        SuggestionCard(icon: icon, title: title, example: example)
                    }
                }
                .frame(maxWidth: 500)
            }

            // New chat button
            Button(action: onNewChat) {
                Label("Start a new chat", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("n", modifiers: .command)

            Spacer()

            // Footer
            Text("Press ⌘N anytime to start a new conversation")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SuggestionCard: View {
    let icon: String
    let title: String
    let example: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .fontWeight(.medium)
            }

            Text(example)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    WelcomeView(onNewChat: {})
}
