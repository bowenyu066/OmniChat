import SwiftUI
import AppKit
import PDFKit

/// Display view for attachments in sent messages
struct AttachmentDisplayView: View {
    let attachment: Attachment

    @State private var isExpanded = false

    var body: some View {
        Group {
            switch attachment.type {
            case .image:
                ImageAttachmentView(
                    data: attachment.data,
                    isExpanded: $isExpanded
                )
            case .pdf:
                PDFAttachmentView(
                    data: attachment.data,
                    filename: attachment.filename,
                    isExpanded: $isExpanded
                )
            }
        }
        .sheet(isPresented: $isExpanded) {
            ExpandedAttachmentView(attachment: attachment)
        }
    }
}

/// Image thumbnail that expands on click
struct ImageAttachmentView: View {
    let data: Data
    @Binding var isExpanded: Bool

    private let maxThumbnailWidth: CGFloat = 300
    private let maxThumbnailHeight: CGFloat = 200

    var body: some View {
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxThumbnailWidth, maxHeight: maxThumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onTapGesture {
                    isExpanded = true
                }
                .contextMenu {
                    Button("Save Image...") {
                        saveImage(nsImage)
                    }
                    Button("Copy Image") {
                        copyImage(nsImage)
                    }
                }
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 100, height: 100)
            Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }

    private func saveImage(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "image.png"

        if panel.runModal() == .OK, let url = panel.url {
            if let tiffData = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }

    private func copyImage(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

/// PDF thumbnail with page count
struct PDFAttachmentView: View {
    let data: Data
    let filename: String?
    @Binding var isExpanded: Bool

    var body: some View {
        Button(action: { isExpanded = true }) {
            HStack(spacing: 12) {
                // PDF icon/thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 48, height: 56)

                    if let pdfDocument = PDFDocument(data: data),
                       let firstPage = pdfDocument.page(at: 0) {
                        // Show first page thumbnail
                        PDFPageThumbnail(page: firstPage)
                            .frame(width: 44, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(filename ?? "PDF Document")
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let pdfDocument = PDFDocument(data: data) {
                        Text("\(pdfDocument.pageCount) page\(pdfDocument.pageCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 280)
        .contextMenu {
            Button("Save PDF...") {
                savePDF()
            }
        }
    }

    private func savePDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = filename ?? "document.pdf"

        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}

/// PDF page thumbnail using PDFKit
struct PDFPageThumbnail: NSViewRepresentable {
    let page: PDFPage

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let pageRect = page.bounds(for: .mediaBox)
        let scale = min(44 / pageRect.width, 52 / pageRect.height)
        let thumbnailSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

        let thumbnail = page.thumbnail(of: thumbnailSize, for: .mediaBox)
        imageView.image = thumbnail

        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
}

/// Full-screen expanded view for attachments
struct ExpandedAttachmentView: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(attachment.filename ?? (attachment.type == .image ? "Image" : "PDF"))
                    .font(.headline)

                Spacer()

                Button("Save") {
                    saveAttachment()
                }
                .buttonStyle(.bordered)

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            Divider()

            // Content
            Group {
                switch attachment.type {
                case .image:
                    ExpandedImageView(data: attachment.data)
                case .pdf:
                    ExpandedPDFView(data: attachment.data)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private func saveAttachment() {
        let panel = NSSavePanel()

        switch attachment.type {
        case .image:
            panel.allowedContentTypes = [.png, .jpeg]
            panel.nameFieldStringValue = attachment.filename ?? "image.png"
        case .pdf:
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = attachment.filename ?? "document.pdf"
        }

        if panel.runModal() == .OK, let url = panel.url {
            try? attachment.data.write(to: url)
        }
    }
}

/// Expanded image view with zoom
struct ExpandedImageView: View {
    let data: Data

    @State private var scale: CGFloat = 1.0

    var body: some View {
        if let nsImage = NSImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .bottomTrailing) {
                HStack {
                    Button(action: { scale = max(0.5, scale - 0.25) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Text("\(Int(scale * 100))%")
                        .monospacedDigit()
                        .frame(width: 50)
                    Button(action: { scale = min(3.0, scale + 0.25) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    Button(action: { scale = 1.0 }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                }
                .padding(8)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
            }
        } else {
            Text("Unable to display image")
                .foregroundStyle(.secondary)
        }
    }
}

/// Expanded PDF view using PDFKit
struct ExpandedPDFView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }

        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}

#Preview {
    VStack(spacing: 20) {
        // These will show placeholders since we don't have real data
        AttachmentDisplayView(attachment: Attachment(type: .image, mimeType: "image/png", data: Data(), filename: "screenshot.png"))

        AttachmentDisplayView(attachment: Attachment(type: .pdf, mimeType: "application/pdf", data: Data(), filename: "document.pdf"))
    }
    .padding()
    .frame(width: 400)
}
