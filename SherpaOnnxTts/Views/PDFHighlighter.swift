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
    
    private static var currentSentenceText: String?
    private static var currentSentenceAnnotation: PDFAnnotation?
    private static var currentWordAnnotation: PDFAnnotation?
    
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
        
        // Find the sentence in the document
        if let sentenceSelection = document.findString(sentence, withOptions: .caseInsensitive).first {
            let sentenceBounds = sentenceSelection.bounds(for: currentPage)
            
            // Only create new sentence highlight if it's a different sentence
            if PDFHighlighter.currentSentenceText != sentence {
                // Clear previous highlights when switching sentences
                clearHighlights()
                
                // Create new sentence highlight
                let annotation = PDFAnnotation(bounds: sentenceBounds, forType: .highlight, withProperties: nil)
                annotation.color = .systemGray.withAlphaComponent(0.2)
                currentPage.addAnnotation(annotation)
                PDFHighlighter.currentSentenceAnnotation = annotation
                PDFHighlighter.currentSentenceText = sentence
            }
            
            // Find and highlight the word within the sentence bounds
            if let wordSelection = document.findString(word, withOptions: .caseInsensitive).first {
                let wordBounds = wordSelection.bounds(for: currentPage)
                
                // Only highlight if the word is within the sentence bounds
                if sentenceBounds.contains(wordBounds) {
                    // Remove previous word highlight if it exists
                    if let oldWordAnnotation = PDFHighlighter.currentWordAnnotation {
                        currentPage.removeAnnotation(oldWordAnnotation)
                    }
                    
                    // Create new word highlight
                    let annotation = PDFAnnotation(bounds: wordBounds, forType: .highlight, withProperties: nil)
                    annotation.color = .systemBlue.withAlphaComponent(0.5)
                    currentPage.addAnnotation(annotation)
                    PDFHighlighter.currentWordAnnotation = annotation
                    
                    return true
                }
            }
            return true // Return true if sentence is highlighted even if word highlight fails
        } else {
            // Clear highlights only if we can't find the sentence
            clearHighlights()
        }
        
        return false
    }
}
