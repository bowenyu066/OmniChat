import Foundation

/// Represents a file snippet retrieved from a workspace
struct FileSnippet {
    let relativePath: String
    let content: String
    let startLine: Int
    let endLine: Int
    let score: Double
    let reason: String  // Why this snippet was included

    /// Returns a citation in the format "file.swift:10-50"
    var citation: String {
        "\(relativePath):\(startLine)-\(endLine)"
    }
}

/// Service for retrieving relevant file snippets from workspace
final class FileRetriever {
    static let shared = FileRetriever()

    private init() {}

    /// Common words to ignore in keyword extraction
    private let stopwords = Set([
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "should",
        "could", "may", "might", "must", "can", "this", "that", "these", "those",
        "i", "you", "he", "she", "it", "we", "they", "what", "which", "who",
        "when", "where", "why", "how", "all", "each", "every", "both", "few",
        "more", "most", "other", "some", "such", "no", "not", "only", "own",
        "same", "so", "than", "too", "very"
    ])

    /// Retrieves relevant file snippets for a given prompt
    /// - Parameters:
    ///   - prompt: The user's prompt to search for
    ///   - workspace: The workspace to search in
    ///   - limit: Maximum number of snippets to return (default: 5)
    /// - Returns: Array of file snippets sorted by relevance
    func retrieveSnippets(
        for prompt: String,
        workspace: Workspace,
        limit: Int = 5
    ) -> [FileSnippet] {
        // Extract keywords from prompt
        let keywords = extractKeywords(from: prompt)

        guard !keywords.isEmpty else { return [] }

        // Score all chunks across all files
        var scoredSnippets: [(snippet: FileSnippet, score: Double)] = []

        for entry in workspace.fileEntries {
            for chunk in entry.chunks {
                let (score, matchedKeywords) = scoreChunk(
                    chunk.content,
                    keywords: keywords,
                    filePath: entry.relativePath
                )

                if score > 0 {
                    let reason: String
                    if matchedKeywords.count == 1 {
                        reason = "Matched: \(matchedKeywords[0])"
                    } else if matchedKeywords.count <= 3 {
                        reason = "Matched: \(matchedKeywords.joined(separator: ", "))"
                    } else {
                        reason = "Matched \(matchedKeywords.count) keywords"
                    }

                    let snippet = FileSnippet(
                        relativePath: entry.relativePath,
                        content: chunk.content,
                        startLine: chunk.startLine,
                        endLine: chunk.endLine,
                        score: score,
                        reason: reason
                    )

                    scoredSnippets.append((snippet, score))
                }
            }
        }

        // Sort by score (highest first) and take top N
        return scoredSnippets
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.snippet }
    }

    /// Extracts meaningful keywords from text
    private func extractKeywords(from text: String) -> [String] {
        // Tokenize: split on whitespace and punctuation, lowercase
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // Filter out stopwords and short words
        let keywords = words
            .filter { !stopwords.contains($0) && $0.count > 2 }

        // Remove duplicates while preserving order
        var seen = Set<String>()
        return keywords.filter { seen.insert($0).inserted }
    }

    /// Scores a chunk based on keyword matches
    /// - Returns: Tuple of (score, matched keywords)
    private func scoreChunk(
        _ content: String,
        keywords: [String],
        filePath: String
    ) -> (score: Double, matchedKeywords: [String]) {
        let contentLower = content.lowercased()
        let filePathLower = filePath.lowercased()

        var score: Double = 0
        var matchedKeywords: [String] = []

        for keyword in keywords {
            var keywordScore: Double = 0

            // Check file path (higher weight)
            if filePathLower.contains(keyword) {
                keywordScore += 3.0
            }

            // Check content
            let occurrences = contentLower.components(separatedBy: keyword).count - 1
            if occurrences > 0 {
                // Score based on occurrences, with diminishing returns
                keywordScore += min(Double(occurrences) * 1.0, 5.0)
                matchedKeywords.append(keyword)
            }

            score += keywordScore
        }

        // Boost score for files with certain extensions (code files)
        let ext = (filePath as NSString).pathExtension.lowercased()
        let codeExtensions = ["swift", "py", "js", "ts", "jsx", "tsx", "go", "rs", "java", "c", "cpp"]
        if codeExtensions.contains(ext) {
            score *= 1.2
        }

        return (score, matchedKeywords)
    }
}
