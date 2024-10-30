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
    let spokenText: String
    let highlightWord: String
    
    static var currentSentenceText: String?
    static var currentSentenceAnnotation: PDFAnnotation?
    static var currentWordAnnotation: PDFAnnotation?
    
    mutating func clearHighlights() {
        if let page = document.page(at: currentPageNumber) {
            PDFHighlighter.currentSentenceAnnotation = nil
            PDFHighlighter.currentWordAnnotation = nil
            PDFHighlighter.currentSentenceText = nil
            
            let highlight = PDFAnnotationSubtype.highlight.rawValue
            let annotations = page.annotations.filter { $0.type == String(highlight.dropFirst()) }
            for annotation in annotations {
                page.removeAnnotation(annotation)
            }
        }
    }
    
    @discardableResult
    mutating func highlightTextInDocument(sentence: String, word: String) -> Bool {
        guard !word.isEmpty, let currentPage = document.page(at: currentPageNumber) else {
            return false
        }
        
        // Normalize sentence and word
        let normalizedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find the sentence in the document
        let sentenceSelections = document.findString(normalizedSentence, withOptions: .caseInsensitive)
        if !sentenceSelections.isEmpty {
            let sentenceSelection = sentenceSelections[0]
            let sentenceBounds = sentenceSelection.bounds(for: currentPage)
            
            // Highlight the sentence if it's new
            if PDFHighlighter.currentSentenceText != normalizedSentence {
                clearHighlights()
                let sentenceAnnotation = PDFAnnotation(bounds: sentenceBounds, forType: .highlight, withProperties: nil)
                sentenceAnnotation.color = .systemGray.withAlphaComponent(0.2)
                currentPage.addAnnotation(sentenceAnnotation)
                PDFHighlighter.currentSentenceAnnotation = sentenceAnnotation
                PDFHighlighter.currentSentenceText = normalizedSentence
            }
            
            // Find and highlight the word
            let wordSelections = document.findString(normalizedWord, withOptions: .caseInsensitive)
            if !wordSelections.isEmpty {
                let wordSelection = wordSelections[0]
                let wordBounds = wordSelection.bounds(for: currentPage)
                
                // Only highlight if the word is within the sentence bounds
                if sentenceBounds.contains(wordBounds) {
                    // Remove previous word highlight
                    if let oldWordAnnotation = PDFHighlighter.currentWordAnnotation {
                        currentPage.removeAnnotation(oldWordAnnotation)
                    }
                    
                    // Add new word highlight
                    let wordAnnotation = PDFAnnotation(bounds: wordBounds, forType: .highlight, withProperties: nil)
                    wordAnnotation.color = .systemBlue.withAlphaComponent(0.5)
                    currentPage.addAnnotation(wordAnnotation)
                    PDFHighlighter.currentWordAnnotation = wordAnnotation
                    
                    return true
                }
            }
            return true // Return true if sentence is highlighted even if word highlight fails
        } else {
            clearHighlights()
        }
        
        return false
    }
}
