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

    mutating func highlightLinesInDocument(lineTexts: [String], word: String) -> Bool {
        guard let currentPage = document.page(at: currentPageNumber) else {
            return false
        }

        clearHighlights()
        var didHighlightAny = false

        for lineText in lineTexts {
            let normalizedLineText = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineSelections = document.findString(
                normalizedLineText,
                withOptions: [.caseInsensitive, .diacriticInsensitive]
            )
            
            if let lineSelection = lineSelections.first(where: { $0.pages.contains(currentPage) }) {
                let lineBounds = lineSelection.bounds(for: currentPage)
                
                let lineAnnotation = RoundedHighlightAnnotation(
                    bounds: lineBounds,
                    forType: .highlight,
                    withProperties: nil
                )
                lineAnnotation.color = UIColor.yellow.withAlphaComponent(0.3)
                currentPage.addAnnotation(lineAnnotation)
                PDFHighlighter.currentLineAnnotations.append(lineAnnotation)
                didHighlightAny = true
                
                // Handle word highlighting
                if !word.isEmpty {
                    handleWordHighlighting(word: word, currentPage: currentPage, lineBounds: lineBounds)
                }
            }
        }
        
        return didHighlightAny
    }

    private func handleWordHighlighting(word: String, currentPage: PDFPage, lineBounds: CGRect) {
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
            let wordAnnotation = RoundedHighlightAnnotation(
                bounds: wordBounds,
                forType: .highlight,
                withProperties: nil
            )
            wordAnnotation.color = UIColor.orange.withAlphaComponent(0.3)
            currentPage.addAnnotation(wordAnnotation)
            PDFHighlighter.currentWordAnnotation = wordAnnotation
        }
    }
}
