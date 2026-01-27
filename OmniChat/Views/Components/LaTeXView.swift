import SwiftUI
import WebKit

// This file is kept for backwards compatibility
// Main LaTeX rendering is now in MarkdownView.swift (DynamicLaTeXView)

struct LaTeXView: NSViewRepresentable {
    let latex: String
    let displayMode: Bool

    init(_ latex: String, displayMode: Bool = false) {
        self.latex = latex
        self.displayMode = displayMode
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 500, height: 50), configuration: configuration)
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
                    overflow: hidden;
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
            </script>
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let height = result as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        webView.frame.size.height = height
                    }
                }
            }
        }
    }
}
