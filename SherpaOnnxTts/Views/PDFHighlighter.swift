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

    static var currentLineAnnotation: PDFAnnotation?
    static var currentWordAnnotation: PDFAnnotation?

    mutating func clearHighlights() {
        guard let page = document.page(at: currentPageNumber) else { return }

        if let lineAnnotation = PDFHighlighter.currentLineAnnotation {
            page.removeAnnotation(lineAnnotation)
            PDFHighlighter.currentLineAnnotation = nil
        }

        if let wordAnnotation = PDFHighlighter.currentWordAnnotation {
            page.removeAnnotation(wordAnnotation)
            PDFHighlighter.currentWordAnnotation = nil
        }
    }

    @discardableResult
    mutating func highlightLineInDocument(lineText: String, word: String) -> Bool {
        print("\n=== Starting highlight for ===")
        print("Line: \"\(lineText)\"")
        print("Word: \"\(word)\"")

        guard let currentPage = document.page(at: currentPageNumber) else {
            print("❌ Guard check failed: no page")
            return false
        }

        // Remove previous highlights
        clearHighlights()

        let normalizedLine = lineText.trimmingCharacters(in: .whitespacesAndNewlines)

        print("\n🔍 Searching for line: \"\(normalizedLine)\"")

        // Find and highlight the line
        let lineSelections = document.findString(
            normalizedLine,
            withOptions: [.caseInsensitive, .diacriticInsensitive]
        )

        if let lineSelection = lineSelections.first {
            let lineBounds = lineSelection.bounds(for: currentPage)
            let lineAnnotation = PDFAnnotation(
                bounds: lineBounds,
                forType: .highlight,
                withProperties: nil
            )
            lineAnnotation.color = UIColor.yellow.withAlphaComponent(0.5)
            currentPage.addAnnotation(lineAnnotation)
            PDFHighlighter.currentLineAnnotation = lineAnnotation

            // Highlight the word within the line
            if !word.isEmpty {
                let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
                let wordSelections = document.findString(
                    normalizedWord,
                    withOptions: [.caseInsensitive, .diacriticInsensitive]
                )

                // Find the word within the line bounds
                if let wordSelection = wordSelections.first {
                    let wordBounds = wordSelection.bounds(for: currentPage)

                    if lineBounds.contains(wordBounds) {
                        let wordAnnotation = PDFAnnotation(
                            bounds: wordBounds,
                            forType: .highlight,
                            withProperties: nil
                        )
                        wordAnnotation.color = UIColor.orange.withAlphaComponent(0.5)
                        currentPage.addAnnotation(wordAnnotation)
                        PDFHighlighter.currentWordAnnotation = wordAnnotation
                    }
                }
            }

            print("\n=== Highlighting Results ===")
            print("Line highlighted: \(PDFHighlighter.currentLineAnnotation != nil)")
            print("Word highlighted: \(PDFHighlighter.currentWordAnnotation != nil)")
            print("Final bounds: \(PDFHighlighter.currentLineAnnotation?.bounds ?? .zero)")

            return true
        } else {
            print("❌ Line not found in document")
            return false
        }
    }
}
