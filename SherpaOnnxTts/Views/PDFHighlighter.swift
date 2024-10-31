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
        print("\n🎯 Attempting to highlight lines")
        print("📄 Page number: \(currentPageNumber)")
        print("📝 Lines to highlight: \(lineTexts)")
        
        guard let currentPage = document.page(at: currentPageNumber) else {
            print("❌ Current page not found")
            return false
        }
        
        clearHighlights()
        var didHighlightAny = false
        
        for lineText in lineTexts {
            print("\n📋 Processing line: \"\(lineText)\"")
            var searchVariations = [lineText]
            
            // Handle line breaks and hyphens
            let noLineBreaks = lineText.replacingOccurrences(
                of: "-\\s*\n\\s*",
                with: "",
                options: .regularExpression
            )
            if noLineBreaks != lineText {
                print("  ↩️ Removed line breaks: \"\(noLineBreaks)\"")
                searchVariations.append(noLineBreaks)
            }
            
            // Handle smart quotes
            let normalizedQuotes = lineText
                .replacingOccurrences(of: #"""#, with: "\"")
                .replacingOccurrences(of: #"""#, with: "\"")
            if normalizedQuotes != lineText {
                print("  \" Normalized quotes: \"\(normalizedQuotes)\"")
                searchVariations.append(normalizedQuotes)
            }
            
            // Handle em dashes
            let normalizedDashes = lineText
                .replacingOccurrences(of: "—", with: "-")
                .replacingOccurrences(of: "–", with: "-")
            if normalizedDashes != lineText {
                print("  — Normalized dashes: \"\(normalizedDashes)\"")
                searchVariations.append(normalizedDashes)
            }
            
            // Try each variation
            print("🔍 Will try variations:")
            searchVariations.enumerated().forEach { index, variation in
                print("  \(index + 1). \"\(variation)\"")
            }
            
            for (index, searchText) in searchVariations.enumerated() {
                let normalizedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                print("\n  🔎 Trying variation #\(index + 1): \"\(normalizedText)\"")
                
                // Try with and without regex
                let selections = document.findString(
                    normalizedText,
                    withOptions: [.caseInsensitive]
                )
                print("    Found \(selections.count) potential matches")
                
                if let selection = selections.first(where: { $0.pages.contains(currentPage) }) {
                    let bounds = selection.bounds(for: currentPage)
                    print("    ✅ Match found on current page")
                    print("    📐 Bounds: \(bounds)")
                    
                    let annotation = RoundedHighlightAnnotation(
                        bounds: bounds,
                        forType: .highlight,
                        withProperties: nil
                    )
                    annotation.color = UIColor.yellow.withAlphaComponent(0.3)
                    print("    🎨 Adding line highlight")
                    currentPage.addAnnotation(annotation)
                    PDFHighlighter.currentLineAnnotations.append(annotation)
                    didHighlightAny = true
                    
                    if !word.isEmpty {
                        print("    🔤 Processing word highlight for: \"\(word)\"")
                        handleWordHighlighting(word: word, currentPage: currentPage, lineBounds: bounds)
                    }
                    
                    print("    ✋ Breaking search as match was found")
                    break
                } else {
                    print("    ❌ No matches found with these options")
                }
            }
        }
        
        print("\n📊 Final result: \(didHighlightAny ? "✅ Successfully added highlights" : "❌ No highlights added")")
        return didHighlightAny
    }

    private func handleWordHighlighting(word: String, currentPage: PDFPage, lineBounds: CGRect) {
        let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        print("\n      🔤 Word highlight details:")
        print("      📝 Normalized word: \"\(normalizedWord)\"")
        print("      📐 Line bounds: \(lineBounds)")
        
        let wordSelections = document.findString(
            normalizedWord,
            withOptions: [.caseInsensitive, .diacriticInsensitive]
        )
        
        print("      🔍 Found \(wordSelections.count) potential word matches")
        
        let matchesOnPage = wordSelections.filter { $0.pages.contains(currentPage) }
        print("      📄 \(matchesOnPage.count) matches on current page")
        
        if let wordSelection = matchesOnPage.first(where: { lineBounds.contains($0.bounds(for: currentPage)) }) {
            let wordBounds = wordSelection.bounds(for: currentPage)
            print("      ✅ Word found within line bounds")
            print("      📐 Word bounds: \(wordBounds)")
            
            let wordAnnotation = RoundedHighlightAnnotation(
                bounds: wordBounds,
                forType: .highlight,
                withProperties: nil
            )
            wordAnnotation.color = UIColor.orange.withAlphaComponent(0.3)
            print("      🎨 Adding word highlight")
            currentPage.addAnnotation(wordAnnotation)
            PDFHighlighter.currentWordAnnotation = wordAnnotation
        } else {
            print("      ❌ Word not found within line bounds")
            
            // Debug word positions
            matchesOnPage.enumerated().forEach { index, selection in
                let bounds = selection.bounds(for: currentPage)
                print("      📍 Match #\(index + 1):")
                print("         Bounds: \(bounds)")
                print("         Within line?: \(lineBounds.contains(bounds))")
            }
        }
    }
}
