import SwiftUI
import AppKit

/// Preview card for pending attachments in the input area
struct AttachmentPreviewView: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    private let cardSize: CGFloat = 80

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail
            Group {
                switch attachment.type {
                case .image:
                    if let nsImage = NSImage(data: attachment.data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        imagePlaceholder
                    }
                case .pdf:
                    pdfThumbnail
                }
            }
            .frame(width: cardSize, height: cardSize)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, Color.secondary)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }

    private var imagePlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var pdfThumbnail: some View {
        ZStack {
            Color.red.opacity(0.1)
            VStack(spacing: 4) {
                Image(systemName: "doc.fill")
                    .font(.title)
                    .foregroundStyle(.red)
                if let filename = attachment.filename {
                    Text(filename)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else {
                    Text("PDF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Row of attachment previews
struct AttachmentPreviewRow: View {
    @Binding var attachments: [PendingAttachment]

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        AttachmentPreviewView(
                            attachment: attachment,
                            onRemove: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    attachments.removeAll { $0.id == attachment.id }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    VStack {
        // Preview with sample image data (placeholder since we can't load real images in preview)
        AttachmentPreviewRow(attachments: .constant([
            PendingAttachment(type: .image, mimeType: "image/png", data: Data(), filename: "screenshot.png"),
            PendingAttachment(type: .pdf, mimeType: "application/pdf", data: Data(), filename: "document.pdf"),
            PendingAttachment(type: .image, mimeType: "image/jpeg", data: Data(), filename: nil)
        ]))
    }
    .padding()
    .frame(width: 400)
}
