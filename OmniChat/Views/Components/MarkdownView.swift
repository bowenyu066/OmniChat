import SwiftUI
import WebKit

/// Custom WKWebView that doesn't capture scroll events
class NonScrollingWebView: WKWebView {
    // Cache the parent scroll view to avoid repeated lookups
    private weak var cachedParentScrollView: NSScrollView?

    override func scrollWheel(with event: NSEvent) {
        // Find and cache the parent NSScrollView
        if cachedParentScrollView == nil {
            cachedParentScrollView = findExternalScrollView()
        }

        if let scrollView = cachedParentScrollView {
            scrollView.scrollWheel(with: event)
        } else {
            // Fallback: pass to next responder
            self.nextResponder?.scrollWheel(with: event)
        }
    }

    private func findExternalScrollView() -> NSScrollView? {
        // Get the WebView's own enclosing scroll view (if any)
        let internalScrollView = self.enclosingScrollView

        // Traverse up from our superview looking for an NSScrollView
        // that is NOT the WebView's internal one
        var current: NSView? = self.superview
        while let view = current {
            if let scrollView = view as? NSScrollView, scrollView !== internalScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}

/// Unified rendering view that renders entire message content in a single WebView
/// Provides consistent styling, proper text selection, and beautiful LaTeX rendering
struct MarkdownView: View {
    let content: String

    @State private var height: CGFloat = 100

    var body: some View {
        UnifiedMessageWebView(content: content, height: $height)
            .frame(minHeight: height)
    }
}

// MARK: - Unified Message WebView
/// Single WebView that renders markdown, LaTeX, and code blocks with consistent styling
struct UnifiedMessageWebView: NSViewRepresentable {
    let content: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> NonScrollingWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "heightUpdate")
        configuration.userContentController.add(context.coordinator, name: "copyCode")

        let webView = NonScrollingWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        // Disable internal scrolling completely
        disableInternalScrolling(for: webView)

        return webView
    }

    private func disableInternalScrolling(for webView: WKWebView) {
        // Disable the enclosing scroll view if it exists
        if let scrollView = webView.enclosingScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
        }

        // Find and disable any internal scroll views within the WKWebView
        disableScrollViewsRecursively(in: webView)
    }

    private func disableScrollViewsRecursively(in view: NSView) {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.verticalScrollElasticity = .none
                scrollView.horizontalScrollElasticity = .none
                scrollView.scrollerStyle = .overlay
            }
            disableScrollViewsRecursively(in: subview)
        }
    }

    func updateNSView(_ webView: NonScrollingWebView, context: Context) {
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
            } else if message.name == "copyCode", let code = message.body as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }
        }

        private func updateHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                guard let self = self, let h = result as? CGFloat, h > 0 else { return }
                DispatchQueue.main.async {
                    self.height = h + 16
                }
            }
        }
    }

    private func generateHTML() -> String {
        let processedContent = preprocessContent(content)

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"></script>
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }

                html, body {
                    background: transparent;
                    overflow-x: hidden;
                    overflow-y: hidden;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 15px;
                    line-height: 1.65;
                    -webkit-font-smoothing: antialiased;
                    pointer-events: auto;
                }

                /* Allow text selection but prevent scroll capture */
                * {
                    -webkit-user-select: text;
                    user-select: text;
                }

                body {
                    padding: 8px 0;
                }

                #content {
                    color: inherit;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }

                /* Typography */
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 1.2em;
                    margin-bottom: 0.6em;
                    font-weight: 600;
                    line-height: 1.3;
                }

                h1 { font-size: 1.8em; }
                h2 { font-size: 1.5em; }
                h3 { font-size: 1.25em; }

                h1:first-child, h2:first-child, h3:first-child {
                    margin-top: 0;
                }

                p {
                    margin: 0.8em 0;
                }

                p:first-child {
                    margin-top: 0;
                }

                p:last-child {
                    margin-bottom: 0;
                }

                /* Inline formatting */
                strong { font-weight: 600; }
                em { font-style: italic; }
                code {
                    font-family: 'SF Mono', Monaco, 'Cascadia Code', Menlo, monospace;
                    font-size: 0.9em;
                    padding: 0.2em 0.4em;
                    background: rgba(128, 128, 128, 0.15);
                    border-radius: 3px;
                }

                /* Lists */
                ul, ol {
                    margin: 0.8em 0;
                    padding-left: 2em;
                }

                li {
                    margin: 0.3em 0;
                }

                /* Horizontal rule */
                hr {
                    margin: 1.5em 0;
                    border: none;
                    border-top: 1px solid rgba(128, 128, 128, 0.3);
                }

                /* Blockquotes */
                blockquote {
                    margin: 1em 0;
                    padding: 0.5em 1em;
                    border-left: 4px solid rgba(128, 128, 128, 0.4);
                    background: rgba(128, 128, 128, 0.05);
                    border-radius: 0 4px 4px 0;
                }

                blockquote p {
                    margin: 0.4em 0;
                }

                blockquote p:first-child {
                    margin-top: 0;
                }

                blockquote p:last-child {
                    margin-bottom: 0;
                }

                /* Code blocks */
                .code-block {
                    margin: 1em 0;
                    border-radius: 8px;
                    overflow: hidden;
                    background: rgba(128, 128, 128, 0.1);
                    border: 1px solid rgba(128, 128, 128, 0.2);
                }

                .code-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    padding: 8px 12px;
                    background: rgba(128, 128, 128, 0.08);
                    border-bottom: 1px solid rgba(128, 128, 128, 0.15);
                }

                .code-language {
                    font-size: 0.8em;
                    opacity: 0.7;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                }

                .copy-button {
                    background: none;
                    border: none;
                    color: inherit;
                    cursor: pointer;
                    font-size: 0.8em;
                    opacity: 0.7;
                    padding: 4px 8px;
                    border-radius: 4px;
                }

                .copy-button:hover {
                    opacity: 1;
                    background: rgba(128, 128, 128, 0.15);
                }

                .code-content {
                    padding: 12px;
                    overflow-x: auto;
                }

                .code-content pre {
                    margin: 0;
                    font-family: 'SF Mono', Monaco, 'Cascadia Code', Menlo, monospace;
                    font-size: 0.9em;
                    line-height: 1.5;
                    white-space: pre;
                }

                /* LaTeX */
                .katex {
                    font-size: 1.05em;
                }

                .katex-display {
                    margin: 1.2em 0;
                    overflow-x: auto;
                    overflow-y: hidden;
                }

                /* Color scheme */
                @media (prefers-color-scheme: dark) {
                    body {
                        color: #e8e8e8;
                    }
                    .code-block {
                        background: rgba(255, 255, 255, 0.05);
                        border-color: rgba(255, 255, 255, 0.1);
                    }
                }

                @media (prefers-color-scheme: light) {
                    body {
                        color: #1a1a1a;
                    }
                }
            </style>
        </head>
        <body>
            <div id="content">\(processedContent)</div>
            <script>
                // Render LaTeX
                renderMathInElement(document.getElementById('content'), {
                    delimiters: [
                        {left: '$$', right: '$$', display: true},
                        {left: '$', right: '$', display: false},
                        {left: '\\\\[', right: '\\\\]', display: true},
                        {left: '\\\\(', right: '\\\\)', display: false}
                    ],
                    throwOnError: false,
                    trust: true
                });

                // Code copy functionality
                document.querySelectorAll('.copy-button').forEach(button => {
                    button.addEventListener('click', function() {
                        const code = this.dataset.code;
                        window.webkit.messageHandlers.copyCode.postMessage(code);

                        const originalText = this.textContent;
                        this.textContent = 'Copied!';
                        setTimeout(() => {
                            this.textContent = originalText;
                        }, 2000);
                    });
                });

                // Update height
                function updateHeight() {
                    window.webkit.messageHandlers.heightUpdate.postMessage(document.body.scrollHeight);
                }

                // Update on load and after LaTeX rendering
                updateHeight();
                setTimeout(updateHeight, 100);
                setTimeout(updateHeight, 300);
            </script>
        </body>
        </html>
        """
    }

    private func preprocessContent(_ text: String) -> String {
        var html = ""
        var remaining = text

        while !remaining.isEmpty {
            // Check for code blocks first: ```language\ncode\n```
            let codePattern = #"```(\w*)\n([\s\S]*?)```"#
            if let codeMatch = remaining.range(of: codePattern, options: .regularExpression) {
                // Add text before code block
                let textBefore = String(remaining[..<codeMatch.lowerBound])
                if !textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    html += convertMarkdownToHTML(textBefore)
                }

                // Parse code block
                if let codeBlock = parseCodeBlock(String(remaining[codeMatch])) {
                    html += renderCodeBlock(language: codeBlock.language, code: codeBlock.code)
                }

                remaining = String(remaining[codeMatch.upperBound...])
                continue
            }

            // No more code blocks, process remaining text
            html += convertMarkdownToHTML(remaining)
            break
        }

        return html
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

        return (language: language?.isEmpty == true ? nil : language, code: code)
    }

    private func renderCodeBlock(language: String?, code: String) -> String {
        let escapedCode = code
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")

        let languageLabel = language ?? ""

        return """
        <div class="code-block">
            <div class="code-header">
                <span class="code-language">\(languageLabel)</span>
                <button class="copy-button" data-code="\(escapedCode.replacingOccurrences(of: "\n", with: "&#10;"))">Copy</button>
            </div>
            <div class="code-content">
                <pre>\(escapedCode)</pre>
            </div>
        </div>
        """
    }

    private func convertMarkdownToHTML(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var htmlLines: [String] = []
        var inParagraph = false
        var currentParagraph: [String] = []
        var inUnorderedList = false
        var inOrderedList = false
        var listItems: [String] = []
        var inBlockquote = false
        var blockquoteLines: [String] = []

        func closeParagraph() {
            if inParagraph {
                htmlLines.append("<p>" + currentParagraph.joined(separator: " ") + "</p>")
                currentParagraph = []
                inParagraph = false
            }
        }

        func closeList() {
            if inUnorderedList {
                htmlLines.append("<ul>")
                htmlLines.append(contentsOf: listItems)
                htmlLines.append("</ul>")
                listItems = []
                inUnorderedList = false
            } else if inOrderedList {
                htmlLines.append("<ol>")
                htmlLines.append(contentsOf: listItems)
                htmlLines.append("</ol>")
                listItems = []
                inOrderedList = false
            }
        }

        func closeBlockquote() {
            if inBlockquote {
                // Process the blockquote content (which may contain its own markdown)
                let blockquoteContent = blockquoteLines.joined(separator: "\n")
                // Don't recursively call convertMarkdownToHTML to avoid escaping issues with LaTeX
                // Instead, just wrap content in paragraphs based on blank lines
                let processedContent = processBlockquoteContent(blockquoteContent)
                htmlLines.append("<blockquote>\(processedContent)</blockquote>")
                blockquoteLines = []
                inBlockquote = false
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for blockquote first (before other processing)
            if trimmed.hasPrefix(">") {
                closeParagraph()
                closeList()
                inBlockquote = true
                // Remove the > and optional space after it
                var content = String(trimmed.dropFirst())
                if content.hasPrefix(" ") {
                    content = String(content.dropFirst())
                }
                blockquoteLines.append(content)
                continue
            }

            // If we were in a blockquote and hit a non-blockquote line, close it
            if inBlockquote && !trimmed.hasPrefix(">") {
                closeBlockquote()
            }

            // Headers
            if trimmed.hasPrefix("### ") {
                closeParagraph()
                closeList()
                let content = escapeHTML(String(trimmed.dropFirst(4)))
                htmlLines.append("<h3>\(processInlineFormatting(content))</h3>")
            } else if trimmed.hasPrefix("## ") {
                closeParagraph()
                closeList()
                let content = escapeHTML(String(trimmed.dropFirst(3)))
                htmlLines.append("<h2>\(processInlineFormatting(content))</h2>")
            } else if trimmed.hasPrefix("# ") {
                closeParagraph()
                closeList()
                let content = escapeHTML(String(trimmed.dropFirst(2)))
                htmlLines.append("<h1>\(processInlineFormatting(content))</h1>")
            } else if isHorizontalRule(trimmed) {
                // Horizontal rule: ---, ***, or ___
                closeParagraph()
                closeList()
                htmlLines.append("<hr>")
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                // Unordered list item
                closeParagraph()
                if inOrderedList {
                    closeList()
                }
                inUnorderedList = true
                let content = escapeHTML(String(trimmed.dropFirst(2)))
                listItems.append("<li>\(processInlineFormatting(content))</li>")
            } else if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                // Ordered list item
                closeParagraph()
                if inUnorderedList {
                    closeList()
                }
                inOrderedList = true
                let content = escapeHTML(String(trimmed[match.upperBound...]))
                listItems.append("<li>\(processInlineFormatting(content))</li>")
            } else if trimmed.isEmpty {
                // Empty line ends paragraph or list
                closeParagraph()
                closeList()
            } else {
                // Regular text - accumulate into paragraph
                closeList()
                currentParagraph.append(escapeHTML(line))
                inParagraph = true
            }
        }

        // Close final paragraph, list, or blockquote if needed
        closeParagraph()
        closeList()
        closeBlockquote()

        return htmlLines.map { processInlineFormatting($0) }.joined(separator: "\n")
    }

    /// Process blockquote content - handles paragraphs and preserves LaTeX
    private func processBlockquoteContent(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var currentPara: [String] = []

        func closePara() {
            if !currentPara.isEmpty {
                let paraContent = currentPara.joined(separator: " ")
                // Escape HTML but preserve $ for LaTeX
                let escaped = paraContent
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                result.append("<p>\(processInlineFormatting(escaped))</p>")
                currentPara = []
            }
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                closePara()
            } else {
                currentPara.append(line)
            }
        }
        closePara()

        return result.joined(separator: "\n")
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        // Horizontal rule: ---, ***, or ___ (3 or more)
        let patterns = [
            "^-{3,}$",     // ---
            "^\\*{3,}$",   // ***
            "^_{3,}$"      // ___
        ]

        for pattern in patterns {
            if line.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func processInlineFormatting(_ text: String) -> String {
        var result = text

        // Bold: **text**
        result = result.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic: *text* (but not **)
        result = result.replacingOccurrences(
            of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Inline code: `code`
        result = result.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "<code>$1</code>",
            options: .regularExpression
        )

        return result
    }
}

#Preview {
    ScrollView {
        MarkdownView(content: """
        In special relativity, the energy–momentum relation (also called the "mass-shell" relation) is

        $$E^2 = (pc)^2 + (mc^2)^2$$

        where:

        - $E$ is the total (relativistic) energy,
        - $p$ is the magnitude of the relativistic momentum,
        - $m$ is the invariant (rest) mass,
        - $c$ is the speed of light.

        Common special cases:

        - **Particle at rest** ($p = 0$):

        $$E = mc^2$$

        - **Massless particle** ($m = 0$, e.g., a photon):

        $$E = pc$$

        Equivalently, it can be written as an invariant:

        $$E^2 - (pc)^2 = (mc^2)^2$$

        This is **bold** and *italic* text with inline math like $\\alpha = \\beta + 1$.

        ```python
        def hello_world():
            print("Hello, World!")
            return 42
        ```

        And here's some more text after the code block.
        """)
        .padding()
    }
    .frame(width: 700, height: 800)
}
