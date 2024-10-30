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
        if let sentenceSelections = document.findString(normalizedSentence, withOptions: .caseInsensitive), !sentenceSelections.isEmpty {
            let sentenceSelection = sentenceSelections[0]
            
            // Highlight the sentence if it's new
            if PDFHighlighter.currentSentenceText != normalizedSentence {
                clearHighlights()
                sentenceSelection.color = .systemGray.withAlphaComponent(0.2)
                currentPage.addAnnotation(PDFAnnotation(bounds: sentenceSelection.bounds(for: currentPage), forType: .highlight, withProperties: nil))
                PDFHighlighter.currentSentenceAnnotation = sentenceSelection.annotations?.first
                PDFHighlighter.currentSentenceText = normalizedSentence
            }
            
            // Find and highlight the word within the sentence selection
            if let wordSelection = sentenceSelection.copy() as? PDFSelection {
                wordSelection.extend(atEnd: -wordSelection.string!.count + normalizedWord.count)
                wordSelection.extend(atStart: wordSelection.string!.startIndex.distance(to: wordSelection.string!.range(of: normalizedWord, options: .caseInsensitive)?.lowerBound ?? wordSelection.string!.startIndex))
                wordSelection.color = .systemBlue.withAlphaComponent(0.5)
                
                // Remove previous word highlight
                if let oldWordAnnotation = PDFHighlighter.currentWordAnnotation {
                    currentPage.removeAnnotation(oldWordAnnotation)
                }
                
                // Add new word highlight
                currentPage.addAnnotation(PDFAnnotation(bounds: wordSelection.bounds(for: currentPage), forType: .highlight, withProperties: nil))
                PDFHighlighter.currentWordAnnotation = wordSelection.annotations?.first
                
                return true
            }
        } else {
            // If sentence not found, clear highlights
            clearHighlights()
        }
        
        return false
    }
}
