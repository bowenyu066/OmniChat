import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.omnichat.app", category: "Conversation")

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isTitleGenerating: Bool = false
    var hasTitleBeenGenerated: Bool = false  // Track if title was already generated

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(id: UUID = UUID(), title: String = "New Chat", createdAt: Date = Date(), updatedAt: Date = Date(), messages: [Message] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    /// Generate title using conversation context (user + assistant), without setting a temporary title first.
    /// Only generates title once - after the first assistant response.
    @MainActor
    func generateTitleFromContextAsync() {
        // Skip if already generating or already generated
        if isTitleGenerating || hasTitleBeenGenerated { return }
        isTitleGenerating = true

        let sortedMessages = messages.sorted(by: { $0.timestamp < $1.timestamp })
        let chatMessages = sortedMessages.map { ChatMessage(from: $0) }

        Task {
            let generatedTitle = await TitleGenerationService.shared.generateTitle(for: chatMessages)
            await MainActor.run {
                self.isTitleGenerating = false
                self.hasTitleBeenGenerated = true  // Mark as generated (even if fallback)
                if let title = generatedTitle {
                    self.title = title
                    logger.info("Title updated to: \(title)")
                } else {
                    // Fallback only on failure
                    if let firstUserMessage = sortedMessages.first(where: { $0.role == .user }) {
                        let trimmed = firstUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            let maxLength = 50
                            self.title = trimmed.count > maxLength ? String(trimmed.prefix(maxLength)) + "..." : trimmed
                        } else if firstUserMessage.hasAttachments {
                            let images = firstUserMessage.attachments.filter { $0.type == .image }.count
                            let pdfs = firstUserMessage.attachments.filter { $0.type == .pdf }.count
                            if images > 0 && pdfs == 0 {
                                self.title = images == 1 ? "Image" : "Images \(images)"
                            } else if pdfs > 0 && images == 0 {
                                if pdfs == 1 {
                                    self.title = firstUserMessage.attachments.first(where: { $0.type == .pdf })?.filename ?? "PDF"
                                } else {
                                    self.title = "PDFs \(pdfs)"
                                }
                            } else {
                                self.title = "Attachments"
                            }
                        } else {
                            self.title = "New Chat"
                        }
                    } else {
                        self.title = "New Chat"
                    }
                    logger.warning("Title generation failed; applied fallback title: \(self.title)")
                }
            }
        }
    }
}
