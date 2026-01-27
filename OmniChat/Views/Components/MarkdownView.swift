import SwiftUI
import WebKit

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
                case .displayLatex(let latex):
                    DynamicLaTeXView(latex: latex, displayMode: true)
                }
            }
        }
    }

    private func renderText(_ text: String) -> some View {
        // Check if text contains inline LaTeX ($...$)
        if containsInlineLatex(text) {
            return AnyView(DynamicMixedContentView(text: text))
        }

        // Parse markdown for headers and other block elements
        return AnyView(MarkdownTextView(text: text))
    }

    private func containsInlineLatex(_ text: String) -> Bool {
        // Check for $...$ pattern (but not $$)
        let pattern = #"(?<!\$)\$(?!\$)([^\$]+)\$(?!\$)"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private enum Block {
        case text(String)
        case codeBlock(language: String?, code: String)
        case displayLatex(String)
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        var remaining = content

        while !remaining.isEmpty {
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

            // Check for display LaTeX: $$...$$ (can span multiple lines)
            let displayLatexPattern = #"\$\$([\s\S]*?)\$\$"#
            if let match = remaining.range(of: displayLatexPattern, options: .regularExpression) {
                if firstMatch == nil || match.lowerBound < firstMatch!.range.lowerBound {
                    let matchedString = String(remaining[match])
                    if let latex = extractLatexContent(from: matchedString, pattern: displayLatexPattern) {
                        firstMatch = (match, "displayLatex", latex)
                    }
                }
            }

            // Check for display LaTeX: \[...\]
            let displayLatexPattern2 = #"\\\[([\s\S]*?)\\\]"#
            if let match = remaining.range(of: displayLatexPattern2, options: .regularExpression) {
                if firstMatch == nil || match.lowerBound < firstMatch!.range.lowerBound {
                    let matchedString = String(remaining[match])
                    if let latex = extractLatexContent(from: matchedString, pattern: displayLatexPattern2) {
                        firstMatch = (match, "displayLatex", latex)
                    }
                }
            }

            if let found = firstMatch {
                let textBefore = String(remaining[..<found.range.lowerBound])
                if !textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(textBefore.trimmingCharacters(in: .newlines)))
                }

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

// MARK: - Markdown Text View (handles headers, bold, italic, etc.)
struct MarkdownTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                renderLine(line)
            }
        }
    }

    @ViewBuilder
    private func renderLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("### ") {
            Text(trimmed.dropFirst(4))
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.top, 4)
        } else if trimmed.hasPrefix("## ") {
            Text(trimmed.dropFirst(3))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 6)
        } else if trimmed.hasPrefix("# ") {
            Text(trimmed.dropFirst(2))
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 8)
        } else if !trimmed.isEmpty {
            if let attributed = try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed)
                    .textSelection(.enabled)
            } else {
                Text(line)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Dynamic LaTeX View (self-sizing)
struct DynamicLaTeXView: View {
    let latex: String
    let displayMode: Bool

    @State private var height: CGFloat = 50

    var body: some View {
        LaTeXWebView(latex: latex, displayMode: displayMode, height: $height)
            .frame(height: height)
    }
}

struct LaTeXWebView: NSViewRepresentable {
    let latex: String
    let displayMode: Bool
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "heightUpdate")

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 50), configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(generateHTML(), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat

        init(height: Binding<CGFloat>) {
            _height = height
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightUpdate", let h = message.body as? CGFloat, h > 0 {
                DispatchQueue.main.async {
                    self.height = h + 16
                }
            }
        }

        private func updateHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let h = result as? CGFloat, h > 0 {
                    DispatchQueue.main.async {
                        self.height = h + 16
                    }
                }
            }
        }
    }

    private func generateHTML() -> String {
        let escapedLatex = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                    background: transparent;
                    overflow-x: auto;
                    overflow-y: hidden;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    display: flex;
                    justify-content: \(displayMode ? "center" : "flex-start");
                    align-items: center;
                    padding: 8px;
                }
                #latex { color: inherit; }
                @media (prefers-color-scheme: dark) { #latex { color: #fff; } }
                @media (prefers-color-scheme: light) { #latex { color: #000; } }
            </style>
        </head>
        <body>
            <div id="latex"></div>
            <script>
                try {
                    katex.render('\(escapedLatex)', document.getElementById('latex'), {
                        throwOnError: false,
                        displayMode: \(displayMode ? "true" : "false"),
                        trust: true
                    });
                } catch (e) {
                    document.getElementById('latex').textContent = 'Error: ' + e.message;
                }
                setTimeout(function() {
                    window.webkit.messageHandlers.heightUpdate.postMessage(document.body.scrollHeight);
                }, 100);
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - Dynamic Mixed Content View (text + inline LaTeX)
struct DynamicMixedContentView: View {
    let text: String

    @State private var height: CGFloat = 30

    var body: some View {
        MixedContentWebView(text: text, height: $height)
            .frame(minHeight: height)
    }
}

struct MixedContentWebView: NSViewRepresentable {
    let text: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "heightUpdate")

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 30), configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(generateHTML(), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat

        init(height: Binding<CGFloat>) {
            _height = height
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightUpdate", let h = message.body as? CGFloat, h > 0 {
                DispatchQueue.main.async {
                    self.height = h + 8
                }
            }
        }

        private func updateHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let h = result as? CGFloat, h > 0 {
                    DispatchQueue.main.async {
                        self.height = h + 8
                    }
                }
            }
        }
    }

    private func generateHTML() -> String {
        // Process each line for markdown headers and other elements
        let lines = text.components(separatedBy: "\n")
        var htmlLines: [String] = []

        for line in lines {
            var processedLine = line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")

            let trimmed = processedLine.trimmingCharacters(in: .whitespaces)

            // Check for markdown headers
            if trimmed.hasPrefix("### ") {
                let content = String(trimmed.dropFirst(4))
                htmlLines.append("<h3>\(content)</h3>")
            } else if trimmed.hasPrefix("## ") {
                let content = String(trimmed.dropFirst(3))
                htmlLines.append("<h2>\(content)</h2>")
            } else if trimmed.hasPrefix("# ") {
                let content = String(trimmed.dropFirst(2))
                htmlLines.append("<h1>\(content)</h1>")
            } else {
                // Convert markdown bold **text** to <strong>
                processedLine = processedLine.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
                // Convert markdown italic *text* to <em> (but not **)
                processedLine = processedLine.replacingOccurrences(of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, with: "<em>$1</em>", options: .regularExpression)
                htmlLines.append(processedLine)
            }
        }

        let html = htmlLines.joined(separator: "<br>")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"></script>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                    background: transparent;
                    overflow-x: auto;
                    overflow-y: hidden;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 15px;
                    line-height: 1.6;
                }
                #content {
                    color: inherit;
                    word-wrap: break-word;
                }
                h1 { font-size: 1.8em; font-weight: bold; margin-top: 12px; margin-bottom: 8px; }
                h2 { font-size: 1.5em; font-weight: bold; margin-top: 10px; margin-bottom: 6px; }
                h3 { font-size: 1.2em; font-weight: 600; margin-top: 8px; margin-bottom: 4px; }
                .katex { font-size: 1.05em; }
                @media (prefers-color-scheme: dark) { body { color: #fff; } }
                @media (prefers-color-scheme: light) { body { color: #000; } }
            </style>
        </head>
        <body>
            <div id="content">\(html)</div>
            <script>
                renderMathInElement(document.getElementById('content'), {
                    delimiters: [
                        {left: '$$', right: '$$', display: true},
                        {left: '$', right: '$', display: false}
                    ],
                    throwOnError: false,
                    trust: true
                });
                setTimeout(function() {
                    window.webkit.messageHandlers.heightUpdate.postMessage(document.body.scrollHeight);
                }, 150);
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - Code Block View
struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            Text(code)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
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

        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isCopied = false }
        }
    }
}

#Preview {
    ScrollView {
        MarkdownView(content: """
        abracadabra!
        
        # Header 1

        ## Header 2

        ### Header 3

        This is **bold** and *italic* text.

        Here's an inline equation: We set $a=1$ from now on. And $E = mc^2$ is famous.

        ### Working modulo $p$

        When working in a field $\\mathbb{F}_p$, we have $a^p = a$ for all $a$.

        ## The Quadratic Formula $x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$

        Display math:

        $$
        \\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}
        $$

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
    .frame(width: 600, height: 800)
}
