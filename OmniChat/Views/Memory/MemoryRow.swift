import SwiftUI

struct MemoryRow: View {
    let memory: MemoryItem
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: memory.type.icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 20)

                Text(memory.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if memory.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                Button(action: onEdit) {
                    Text("Edit")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            Text(memory.bodyPreview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack {
                if !memory.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(memory.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }

                Spacer()

                Text(memory.relativeTimeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
