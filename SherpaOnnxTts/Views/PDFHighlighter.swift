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

    mutating func highlightLineInDocument(lineText: String, word: String) -> Bool {
        guard let currentPage = document.page(at: currentPageNumber) else {
            print("❌ Invalid page number")
            return false
        }

        clearHighlights()
        
        // Search for the exact line text in the document
        let normalizedLineText = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineSelections = document.findString(
            normalizedLineText,
            withOptions: [.caseInsensitive, .diacriticInsensitive]
        )
        
        // Filter selections to only those on the current page
        if let lineSelection = lineSelections.first(where: { $0.pages.contains(currentPage) }) {
            let lineBounds = lineSelection.bounds(for: currentPage)
            
            let lineAnnotation = PDFAnnotation(
                bounds: lineBounds,
                forType: .highlight,
                withProperties: nil
            )
            lineAnnotation.color = UIColor.yellow.withAlphaComponent(0.5)
            currentPage.addAnnotation(lineAnnotation)
            PDFHighlighter.currentLineAnnotation = lineAnnotation
            
            // Handle word highlighting
            if !word.isEmpty {
                let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
                let wordSelections = document.findString(
                    normalizedWord,
                    withOptions: [.caseInsensitive, .diacriticInsensitive]
                )
                
                if let wordSelection = wordSelections.first(where: { 
                    $0.pages.contains(currentPage) && 
                    lineBounds.contains($0.bounds(for: currentPage))
                }) {
                    let wordBounds = wordSelection.bounds(for: currentPage)
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
            
            return true
        } else {
            print("❌ Line not found in document")
            return false
        }
    }
}
