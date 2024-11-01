//
//  PDFHighlighter.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/30/24.
//

import Foundation
import PDFKit

struct PDFHighlighter {
    let document: PDFDocument
    let currentPageNumber: Int
    let highlightWord: String

    static var currentLineAnnotations: [PDFAnnotation] = []
    static var currentWordAnnotation: PDFAnnotation?

    mutating func clearHighlights() {
        guard let page = document.page(at: currentPageNumber) else { return }

        for annotation in PDFHighlighter.currentLineAnnotations {
            page.removeAnnotation(annotation)
        }
        PDFHighlighter.currentLineAnnotations.removeAll()

        if let wordAnnotation = PDFHighlighter.currentWordAnnotation {
            page.removeAnnotation(wordAnnotation)
            PDFHighlighter.currentWordAnnotation = nil
        }
    }

    /// Attempts to highlight specified lines and a word in a PDF document
    /// - Parameters:
    ///   - lineTexts: Array of text lines to highlight
    ///   - word: Optional word to highlight within the found lines
    /// - Returns: Boolean indicating if any highlights were successfully added
    mutating func highlightLinesInDocument(lineTexts: [String], word: String) -> Bool {
        guard let currentPage = document.page(at: currentPageNumber) else { return false }

        clearHighlights()
        var didHighlightAny = false

        // Extract and normalize the page text
        guard let pageContent = currentPage.string else { return false }
        let normalizedPageContent = normalizeText(pageContent)

        for lineText in lineTexts {
            let normalizedSearchText = normalizeText(lineText)

            if let range = normalizedPageContent.range(
                of: normalizedSearchText,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) {
                let nsRange = NSRange(range, in: normalizedPageContent)

                guard extractText(from: pageContent, range: nsRange) != nil else { continue }

                // Map the range back to the original text
                if let originalRange = mapRange(
                    from: normalizedPageContent,
                    to: pageContent,
                    normalizedRange: range
                ) {
                    // Create a PDFSelection for the found range
                    if let selection = currentPage.selection(for: originalRange) {
                        let lineAnnotations = createLineHighlights(
                            selection: selection,
                            currentPage: currentPage
                        )

                        for annotation in lineAnnotations {
                            currentPage.addAnnotation(annotation)
                            PDFHighlighter.currentLineAnnotations.append(annotation)
                        }
                        didHighlightAny = true

                        if !word.isEmpty {
                            handleWordHighlighting(
                                word: word,
                                currentPage: currentPage,
                                lineBounds: selection.bounds(for: currentPage)
                            )
                        }
                        continue
                    }
                }
            }
        }

        return didHighlightAny
    }

    /// Handles highlighting of a specific word within a line's bounds
    /// - Parameters:
    ///   - word: The word to highlight
    ///   - currentPage: The current PDF page
    ///   - lineBounds: The bounds of the line containing the word
    private func handleWordHighlighting(word: String, currentPage: PDFPage, lineBounds: CGRect) {
        let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)

        let wordSelections = document.findString(
            normalizedWord,
            withOptions: [.caseInsensitive, .diacriticInsensitive]
        )

        let matchesOnPage = wordSelections.filter { $0.pages.contains(currentPage) }

        if let wordSelection = matchesOnPage
            .first(where: { lineBounds.contains($0.bounds(for: currentPage)) }) {
            let wordBounds = wordSelection.bounds(for: currentPage)

            let wordAnnotation = RoundedHighlightAnnotation(
                bounds: wordBounds,
                forType: .highlight,
                withProperties: nil
            )
            wordAnnotation.color = UIColor.orange.withAlphaComponent(0.3)
            currentPage.addAnnotation(wordAnnotation)
            PDFHighlighter.currentWordAnnotation = wordAnnotation
        } else {
            // Debug word positions if word not found
            matchesOnPage.enumerated().forEach { _, selection in
                let bounds = selection.bounds(for: currentPage)
                // Store debug info in a log if needed
            }
        }
    }

    private func normalizeText(_ text: String) -> String {
        let normalizedText = text
            // Replace ligatures
            .replacingOccurrences(of: "\u{FB00}", with: "ff")
            .replacingOccurrences(of: "\u{FB01}", with: "fi")
            .replacingOccurrences(of: "\u{FB02}", with: "fl")
            .replacingOccurrences(of: "\u{FB03}", with: "ffi")
            .replacingOccurrences(of: "\u{FB04}", with: "ffl")
            .replacingOccurrences(of: "\u{FB05}", with: "ft")
            .replacingOccurrences(of: "\u{FB06}", with: "st")
            // Handle smart quotes and apostrophes
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            // Replace dashes
            .replacingOccurrences(of: "\u{2014}", with: "--")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            // Normalize line breaks and spaces
            .replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedText
    }

    private func mapRange(
        from normalizedText: String,
        to originalText: String,
        normalizedRange: Range<String.Index>
    ) -> NSRange? {
        // Extract the substring we're looking for from the normalized text
        guard normalizedRange.lowerBound >= normalizedText.startIndex,
              normalizedRange.upperBound <= normalizedText.endIndex else {
            return nil
        }

        let targetSubstring = String(normalizedText[normalizedRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split the substring into words for start/end matching
        let words = targetSubstring.components(separatedBy: .whitespaces)
        guard let firstWord = words.first, let lastWord = words.last else {
            return nil
        }

        // Find all possible ranges of the first word
        var currentSearchStart = originalText.startIndex
        var possibleRanges: [NSRange] = []

        while let firstRange = originalText[currentSearchStart...].range(
            of: firstWord,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            // For each occurrence of the first word, look for the last word in the remaining text
            let remainingTextStart = firstRange.upperBound
            guard remainingTextStart <= originalText.endIndex else { break }

            let remainingText = originalText[remainingTextStart...]
            if let lastRange = remainingText.range(
                of: lastWord,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) {
                // Calculate the full range safely
                let fullRange = Range(
                    uncheckedBounds: (
                        lower: firstRange.lowerBound,
                        upper: originalText.index(
                            remainingTextStart,
                            offsetBy: remainingText.distance(
                                from: remainingText.startIndex,
                                to: lastRange.upperBound
                            ),
                            limitedBy: originalText.endIndex
                        ) ?? originalText.endIndex
                    )
                )

                // Extract and normalize the text in this range
                let extractedText = String(originalText[fullRange])
                let normalizedExtracted = normalizeText(extractedText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Compare normalized versions, ignoring extra whitespace
                if normalizedExtracted.components(separatedBy: .whitespacesAndNewlines)
                    .joined(separator: " ")
                    .lowercased() == targetSubstring.components(separatedBy: .whitespacesAndNewlines)
                    .joined(separator: " ")
                    .lowercased() {
                    // Convert to NSRange safely
                    let utf16View = originalText.utf16
                    let startOffset = utf16View.distance(from: utf16View.startIndex, to: fullRange.lowerBound)
                    let endOffset = utf16View.distance(from: utf16View.startIndex, to: fullRange.upperBound)
                    let possibleRange = NSRange(location: startOffset, length: endOffset - startOffset)
                    possibleRanges.append(possibleRange)
                }
            }

            // Move search start to just after this occurrence of first word
            currentSearchStart = firstRange.upperBound

            // Safety check to prevent infinite loop
            if currentSearchStart >= originalText.endIndex {
                break
            }
        }

        return possibleRanges.first
    }

    private func createLineHighlights(
        selection: PDFSelection,
        currentPage: PDFPage
    ) -> [PDFAnnotation] {
        var annotations: [PDFAnnotation] = []

        // Get all line rects for this selection
        let lineRects = selection.selectionsByLine()
            .map { $0.bounds(for: currentPage) }
            .filter { !$0.isEmpty }

        // Create an annotation for each line
        for lineRect in lineRects {
            let annotation = RoundedHighlightAnnotation(
                bounds: lineRect,
                forType: .highlight,
                withProperties: nil
            )
            annotation.color = UIColor.yellow.withAlphaComponent(0.3)
            annotations.append(annotation)
        }

        return annotations
    }

    private func extractText(from originalText: String, range: NSRange) -> String? {
        guard let stringRange = Range(range, in: originalText) else { return nil }

        // Validate range bounds before extraction
        guard stringRange.lowerBound >= originalText.startIndex,
              stringRange.upperBound <= originalText.endIndex else { return nil }

        return String(originalText[stringRange])
    }
}
