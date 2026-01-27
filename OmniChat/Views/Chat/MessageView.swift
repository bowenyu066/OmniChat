import SwiftUI

struct MessageView: View {
    let message: Message

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if !isUser {
                AvatarView(isUser: false, modelUsed: message.modelUsed)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Role label
                HStack(spacing: 6) {
                    Text(isUser ? "You" : modelDisplayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Attachments (if any)
                if message.hasAttachments {
                    VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                        ForEach(message.attachments, id: \.id) { attachment in
                            AttachmentDisplayView(attachment: attachment)
                        }
                    }
                }

                // Message content
                if isUser {
                    // User messages: plain text with bubble (only if there's text)
                    if !message.content.isEmpty {
                        Text(message.content)
                            .textSelection(.enabled)
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(userMessageBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .foregroundStyle(.white)
                    }
                } else {
                    // Assistant messages: markdown rendering
                    MarkdownView(content: message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
            .frame(maxWidth: isUser ? 500 : .infinity, alignment: isUser ? .trailing : .leading)

            if isUser {
                AvatarView(isUser: true, modelUsed: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 20)
    }

    private var userMessageBackground: some ShapeStyle {
        LinearGradient(
            colors: [Color.blue, Color.blue.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var modelDisplayName: String {
        guard let modelUsed = message.modelUsed else { return "Assistant" }
        return AIModel(rawValue: modelUsed)?.displayName ?? modelUsed
    }
}

struct AvatarView: View {
    let isUser: Bool
    let modelUsed: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarBackground)
                .frame(width: 32, height: 32)

            Image(systemName: avatarIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(avatarIconColor)
        }
    }

    private var avatarBackground: some ShapeStyle {
        if isUser {
            return AnyShapeStyle(Color.blue.opacity(0.15))
        } else {
            return AnyShapeStyle(providerGradient)
        }
    }

    private var providerGradient: LinearGradient {
        let provider = modelUsed.flatMap { AIModel(rawValue: $0)?.provider }
        switch provider {
        case .openAI:
            return LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .anthropic:
            return LinearGradient(colors: [.orange, .brown], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .google:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .none:
            return LinearGradient(colors: [.gray, .gray.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var avatarIcon: String {
        isUser ? "person.fill" : "brain"
    }

    private var avatarIconColor: Color {
        isUser ? .blue : .white
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            MessageView(message: Message(role: .user, content: "Can you show me a Python function?"))
            MessageView(message: Message(role: .assistant, content: """
            Sure! Here's a simple Python function:

            ```python
            def greet(name):
                return f"Hello, {name}!"

            # Usage
            print(greet("World"))
            ```

            This function takes a `name` parameter and returns a greeting string.
            
            ### Key features $mlp$
            
            this doesn't look right with some weird paddings and spacing
            """, modelUsed: "gpt-4.1"))
        }
        .padding()
    }
    .frame(width: 700, height: 500)
}
