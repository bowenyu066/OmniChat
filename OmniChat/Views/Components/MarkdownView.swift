import SwiftUI

struct MarkdownView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    renderText(text)
                case .codeBlock(let language, let code):
                    CodeBlockView(language: language, code: code)
                case .inlineCode(let code):
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                case .displayLatex(let latex):
                    LaTeXView(latex, displayMode: true)
                        .frame(minHeight: 40, maxHeight: 200)
                case .inlineLatex(let latex):
                    HStack(spacing: 0) {
                        LaTeXView(latex, displayMode: false)
                            .frame(height: 24)
                    }
                }
            }
        }
    }

    private func renderText(_ text: String) -> some View {
        // Check if text contains inline LaTeX ($...$)
        if containsInlineLatex(text) {
            return AnyView(renderTextWithInlineLatex(text))
        }

        return AnyView(Group {
            if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed)
                    .textSelection(.enabled)
            } else {
                Text(text)
                    .textSelection(.enabled)
            }
        })
    }

    private func containsInlineLatex(_ text: String) -> Bool {
        // Check for $...$ pattern (but not $$)
        let pattern = #"(?<!\$)\$(?!\$)([^\$]+)\$(?!\$)"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private func renderTextWithInlineLatex(_ text: String) -> some View {
        let segments = parseInlineLatex(text)
        return HStack(alignment: .center, spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let str):
                    if let attributed = try? AttributedString(markdown: str, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed)
                            .textSelection(.enabled)
                    } else {
                        Text(str)
                            .textSelection(.enabled)
                    }
                case .latex(let latex):
                    LaTeXView(latex, displayMode: false)
                        .frame(height: 20)
                }
            }
        }
    }

    private enum InlineSegment {
        case text(String)
        case latex(String)
    }

    private func parseInlineLatex(_ text: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        let pattern = #"(?<!\$)\$(?!\$)([^\$]+)\$(?!\$)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(text)]
        }

        var lastEnd = text.startIndex
        let nsRange = NSRange(text.startIndex..., in: text)

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match = match,
                  let fullRange = Range(match.range, in: text),
                  let latexRange = Range(match.range(at: 1), in: text) else { return }

            // Add text before this match
            if lastEnd < fullRange.lowerBound {
                let textBefore = String(text[lastEnd..<fullRange.lowerBound])
                if !textBefore.isEmpty {
                    segments.append(.text(textBefore))
                }
            }

            // Add the LaTeX
            segments.append(.latex(String(text[latexRange])))
            lastEnd = fullRange.upperBound
        }

        // Add remaining text
        if lastEnd < text.endIndex {
            segments.append(.text(String(text[lastEnd...])))
        }

        return segments.isEmpty ? [.text(text)] : segments
    }

    private enum Block {
        case text(String)
        case codeBlock(language: String?, code: String)
        case inlineCode(String)
        case displayLatex(String)
        case inlineLatex(String)
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        var remaining = content

        // Combined pattern that matches code blocks and display LaTeX
        // Order matters: process in order of appearance
        while !remaining.isEmpty {
            // Find the first match of any type
            var firstMatch: (range: Range<String.Index>, type: String, content: Any)? = nil

            // Check for code block: ```language\ncode\n```
            let codeBlockPattern = #"```(\w*)\n([\s\S]*?)```"#
            if let match = remaining.range(of: codeBlockPattern, options: .regularExpression) {
                let codeBlockString = String(remaining[match])
                if let parsed = parseCodeBlock(codeBlockString) {
                    if firstMatch == nil || match.lowerBound < firstMatch!.range.lowerBound {
                        firstMatch = (match, "code", parsed)
                    }
                }
            }

            // Check for display LaTeX: $$...$$
            let displayLatexPattern = #"\$\$([^\$]+)\$\$"#
            if let match = remaining.range(of: displayLatexPattern, options: .regularExpression) {
                if firstMatch == nil || match.lowerBound < firstMatch!.range.lowerBound {
                    let matchedString = String(remaining[match])
                    if let latex = extractLatexContent(from: matchedString, pattern: displayLatexPattern) {
                        firstMatch = (match, "displayLatex", latex)
                    }
                }
            }

            // Check for display LaTeX: \[...\]
            let displayLatexPattern2 = #"\\\[([^\]]+)\\\]"#
            if let match = remaining.range(of: displayLatexPattern2, options: .regularExpression) {
                if firstMatch == nil || match.lowerBound < firstMatch!.range.lowerBound {
                    let matchedString = String(remaining[match])
                    if let latex = extractLatexContent(from: matchedString, pattern: displayLatexPattern2) {
                        firstMatch = (match, "displayLatex", latex)
                    }
                }
            }

            if let found = firstMatch {
                // Add text before the match
                let textBefore = String(remaining[..<found.range.lowerBound])
                if !textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(textBefore.trimmingCharacters(in: .newlines)))
                }

                // Add the matched block
                switch found.type {
                case "code":
                    if let parsed = found.content as? (language: String?, code: String) {
                        blocks.append(.codeBlock(language: parsed.language, code: parsed.code))
                    }
                case "displayLatex":
                    if let latex = found.content as? String {
                        blocks.append(.displayLatex(latex))
                    }
                default:
                    break
                }

                remaining = String(remaining[found.range.upperBound...])
            } else {
                // No more special blocks, add remaining as text
                if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(remaining.trimmingCharacters(in: .newlines)))
                }
                break
            }
        }

        return blocks
    }

    private func extractLatexContent(from string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseCodeBlock(_ block: String) -> (language: String?, code: String)? {
        let pattern = #"```(\w*)\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)) else {
            return nil
        }

        let languageRange = Range(match.range(at: 1), in: block)
        let codeRange = Range(match.range(at: 2), in: block)

        let language = languageRange.map { String(block[$0]) }
        let code = codeRange.map { String(block[$0]) } ?? ""

        return (language: language?.isEmpty == true ? nil : language, code: code.trimmingCharacters(in: .newlines))
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                if let lang = language {
                    Text(lang)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copyToClipboard()
                } label: {
                    Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

#Preview {
    ScrollView {
        MarkdownView(content: """
        # Hello World

        This is **bold** and *italic* text.

        Here's some `inline code` in a sentence.

        ```swift
        func greet(name: String) -> String {
            return "Hello, \\(name)!"
        }
        ```

        And a list:
        - Item 1
        - Item 2
        - Item 3

        ```python
        def factorial(n):
            if n <= 1:
                return 1
            return n * factorial(n - 1)
        ```

        That's all!
        """)
        .padding()
    }
    .frame(width: 500, height: 600)
}
