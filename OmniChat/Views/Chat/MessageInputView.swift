import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool
    
    // 配置项：最大显示多少行，超过则显示滚动条
    private let maxLineLimit: Int = 8

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            
            // --- 核心修改区域 Start ---
            TextField("Message...", text: $text, axis: .vertical)
                // 关键点 1: 启用垂直轴向，允许换行
                .lineLimit(1...maxLineLimit)
                // 关键点 2: 去除 macOS 默认的输入框样式（光晕/边框），完全自定义
                .textFieldStyle(.plain)
                .font(.body)
                // 关键点 3: 通过 Padding 撑起圆角矩形，文字天然居中
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .focused($isFocused)
            // --- 核心修改区域 End ---

            // Send button
            Button(action: {
                if canSend {
                    onSend()
                }
            }) {
                Image(systemName: isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend || isLoading ? Color.accentColor : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!canSend && !isLoading)
            .keyboardShortcut(.return, modifiers: .command) // Command + Enter 发送
            .help(isLoading ? "Stop generating" : "Send message (⌘↩)")
        }
        .onAppear {
            isFocused = true
        }
        // 保持此通知监听，以便外部可以重新聚焦输入框
        .onReceive(NotificationCenter.default.publisher(for: .focusMessageInput)) { _ in
            isFocused = true
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
}

// 保留 notification name 扩展，防止报错
// extension Notification.Name {
//    static let focusMessageInput = Notification.Name("focusMessageInput")
// }

#Preview {
    VStack(spacing: 20) {
        MessageInputView(
            text: .constant(""),
            isLoading: false,
            onSend: {}
        )

        MessageInputView(
            text: .constant("Hello, this fits nicely."),
            isLoading: false,
            onSend: {}
        )
        
        // 测试长文本滚动效果
        MessageInputView(
            text: .constant("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur."),
            isLoading: false,
            onSend: {}
        )
    }
    .padding()
    .frame(width: 400)
    .background(Color.gray.opacity(0.1))
}
