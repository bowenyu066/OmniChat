import SwiftUI
import WebKit

struct LaTeXView: NSViewRepresentable {
    let latex: String
    let displayMode: Bool

    init(_ latex: String, displayMode: Bool = false) {
        self.latex = latex
        self.displayMode = displayMode
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML()
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func generateHTML() -> String {
        let escapedLatex = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let displayModeJS = displayMode ? "true" : "false"

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    background: transparent;
                    display: flex;
                    align-items: center;
                    justify-content: \(displayMode ? "center" : "flex-start");
                    min-height: 100%;
                    padding: \(displayMode ? "8px 0" : "0");
                }
                #latex {
                    color: inherit;
                }
                @media (prefers-color-scheme: dark) {
                    #latex { color: #fff; }
                }
                @media (prefers-color-scheme: light) {
                    #latex { color: #000; }
                }
            </style>
        </head>
        <body>
            <div id="latex"></div>
            <script>
                try {
                    katex.render('\(escapedLatex)', document.getElementById('latex'), {
                        throwOnError: false,
                        displayMode: \(displayModeJS),
                        trust: true
                    });
                } catch (e) {
                    document.getElementById('latex').textContent = 'LaTeX Error: ' + e.message;
                }
            </script>
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Adjust height based on content
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let height = result as? CGFloat {
                    webView.frame.size.height = height
                }
            }
        }
    }
}

// A view that combines text and LaTeX rendering
struct MixedContentView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseContent().enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed)
                            .textSelection(.enabled)
                    } else {
                        Text(text)
                            .textSelection(.enabled)
                    }
                case .displayLatex(let latex):
                    LaTeXView(latex, displayMode: true)
                        .frame(minHeight: 40, maxHeight: 200)
                case .inlineLatex(let latex):
                    LaTeXView(latex, displayMode: false)
                        .frame(height: 24)
                }
            }
        }
    }

    private enum ContentSegment {
        case text(String)
        case displayLatex(String)
        case inlineLatex(String)
    }

    private func parseContent() -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var remaining = content

        // Pattern for display math: $$...$$ or \[...\]
        let displayPatterns = [
            #"\$\$([^\$]+)\$\$"#,
            #"\\\[([^\]]+)\\\]"#
        ]

        // Pattern for inline math: $...$ or \(...\)
        let inlinePatterns = [
            #"\$([^\$]+)\$"#,
            #"\\\(([^)]+)\\\)"#
        ]

        // Process display math first
        for pattern in displayPatterns {
            while let match = remaining.range(of: pattern, options: .regularExpression) {
                let textBefore = String(remaining[..<match.lowerBound])
                if !textBefore.isEmpty {
                    segments.append(.text(textBefore))
                }

                let matchedString = String(remaining[match])
                if let latex = extractLatex(from: matchedString, pattern: pattern) {
                    segments.append(.displayLatex(latex))
                }

                remaining = String(remaining[match.upperBound...])
            }
        }

        // If no display math was found, check for inline math
        if segments.isEmpty {
            for pattern in inlinePatterns {
                while let match = remaining.range(of: pattern, options: .regularExpression) {
                    let textBefore = String(remaining[..<match.lowerBound])
                    if !textBefore.isEmpty {
                        segments.append(.text(textBefore))
                    }

                    let matchedString = String(remaining[match])
                    if let latex = extractLatex(from: matchedString, pattern: pattern) {
                        segments.append(.inlineLatex(latex))
                    }

                    remaining = String(remaining[match.upperBound...])
                }
            }
        }

        // Add any remaining text
        if !remaining.isEmpty {
            segments.append(.text(remaining))
        }

        // If no LaTeX found, return original content as text
        if segments.isEmpty {
            return [.text(content)]
        }

        return segments
    }

    private func extractLatex(from string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range])
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Display Math:")
        LaTeXView("E = mc^2", displayMode: true)
            .frame(height: 50)

        Text("Inline Math:")
        LaTeXView("x^2 + y^2 = z^2", displayMode: false)
            .frame(height: 30)

        Text("Complex Formula:")
        LaTeXView("\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}", displayMode: true)
            .frame(height: 60)

        Divider()

        Text("Mixed Content:")
        MixedContentView(content: "The quadratic formula is $$x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$$ which solves equations.")
    }
    .padding()
    .frame(width: 500, height: 400)
}
