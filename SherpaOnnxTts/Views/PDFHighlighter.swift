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
        
        // Use the original sentence text for highlighting
        let normalizedSentence = sentence.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let normalizedWord = word.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        // Find the sentence in the document
        let sentenceSelections = document.findString(normalizedSentence, withOptions: [.caseInsensitive, .diacriticInsensitive])
        
        // If we can't find the exact sentence, try finding it by parts
        if sentenceSelections.isEmpty {
            // Find all occurrences of the first and last words of the sentence
            let words = normalizedSentence.components(separatedBy: CharacterSet.whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            
            guard let firstWord = words.first,
                  let lastWord = words.last else {
                return false
            }
            
            let firstWordSelections = document.findString(firstWord, withOptions: [.caseInsensitive, .diacriticInsensitive])
            let lastWordSelections = document.findString(lastWord, withOptions: [.caseInsensitive, .diacriticInsensitive])
            
            // Find the correct pair of first and last word occurrences that contain our sentence
            var sentenceBounds: CGRect?
            
            for firstSelection in firstWordSelections {
                let firstBounds = firstSelection.bounds(for: currentPage)
                
                for lastSelection in lastWordSelections {
                    let lastBounds = lastSelection.bounds(for: currentPage)
                    
                    // Only consider pairs where the last word comes after the first word
                    if lastBounds.minY >= firstBounds.minY {
                        let potentialBounds = CGRect(
                            x: min(firstBounds.minX, lastBounds.minX),
                            y: firstBounds.minY,
                            width: max(firstBounds.maxX, lastBounds.maxX) - min(firstBounds.minX, lastBounds.minX),
                            height: lastBounds.maxY - firstBounds.minY
                        )
                        
                        // Create a selection for the entire region
                        if let pageSelection = currentPage.selection(for: potentialBounds),
                           let selectionString = pageSelection.string?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                           selectionString.contains(firstWord) && selectionString.contains(lastWord) {
                            sentenceBounds = potentialBounds
                            break
                        }
                    }
                }
                
                if sentenceBounds != nil {
                    break
                }
            }
            
            guard let bounds = sentenceBounds else {
                return false
            }
            
            // Highlight the sentence if it's new
            if PDFHighlighter.currentSentenceText != normalizedSentence {
                clearHighlights()
                let sentenceAnnotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                sentenceAnnotation.color = .systemGray.withAlphaComponent(0.2)
                currentPage.addAnnotation(sentenceAnnotation)
                PDFHighlighter.currentSentenceAnnotation = sentenceAnnotation
                PDFHighlighter.currentSentenceText = normalizedSentence
            }
            
        } else {
            // Use the found sentence selection
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
        }
        
        // Find and highlight the word
        let wordSelections = document.findString(normalizedWord, withOptions: [.caseInsensitive, .diacriticInsensitive])
        if !wordSelections.isEmpty {
            let wordSelection = wordSelections[0]
            let wordBounds = wordSelection.bounds(for: currentPage)
            
            // Only highlight if the word is within the sentence bounds
            if let currentAnnotation = PDFHighlighter.currentSentenceAnnotation,
               currentAnnotation.bounds.contains(wordBounds) {
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
    }
}
