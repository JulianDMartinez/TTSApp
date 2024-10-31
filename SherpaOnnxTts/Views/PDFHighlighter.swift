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
        
        // Extract and normalize the page text
        guard let pageContent = currentPage.string else {
            print("❌ Unable to extract page content")
            return false
        }
        let normalizedPageContent = normalizeText(pageContent)
        print("📝 Normalized page content: \"\(normalizedPageContent)\"")
        
        for lineText in lineTexts {
            print("\n📋 Processing line: \"\(lineText)\"")
            
            // Normalize the search text
            let normalizedSearchText = normalizeText(lineText)
            print("  🔄 Normalized search text: \"\(normalizedSearchText)\"")
            
            // Use regular expressions to search within normalized page content
            if let range = normalizedPageContent.range(
                of: NSRegularExpression.escapedPattern(for: normalizedSearchText),
                options: [.regularExpression, .caseInsensitive]
            ) {
                print("  ✅ Match found in normalized page content")

                // Map the range back to the original text
                if let originalRange = mapRange(
                    from: normalizedPageContent,
                    to: pageContent,
                    normalizedRange: range
                ) {
                    print("  🔄 Mapped range in original text: \(originalRange)")

                    // Create a PDFSelection for the found range
                    if let selection = currentPage.selection(for: originalRange) {
                        let lineAnnotations = createLineHighlights(
                            selection: selection,
                            currentPage: currentPage
                        )
                        
                        print("    🎨 Adding \(lineAnnotations.count) line highlights")
                        for annotation in lineAnnotations {
                            currentPage.addAnnotation(annotation)
                            PDFHighlighter.currentLineAnnotations.append(annotation)
                        }
                        didHighlightAny = true
                        
                        if !word.isEmpty {
                            print("    🔤 Processing word highlight for: \"\(word)\"")
                            handleWordHighlighting(word: word, currentPage: currentPage, lineBounds: selection.bounds(for: currentPage))
                        }
                        
                        print("    ✋ Breaking search as match was found")
                        continue
                    } else {
                        print("    ❌ Could not create selection for found range")
                    }
                } else {
                    print("    ❌ Could not map normalized range to original content")
                }
            } else {
                print("  ❌ No matches found in normalized page content")
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

    private func normalizeText(_ text: String) -> String {
        let normalizedText = text
            // Replace ligatures
            .replacingOccurrences(of: "\u{FB00}", with: "ff") // ﬀ
            .replacingOccurrences(of: "\u{FB01}", with: "fi") // ﬁ
            .replacingOccurrences(of: "\u{FB02}", with: "fl") // ﬂ
            .replacingOccurrences(of: "\u{FB03}", with: "ffi") // ﬃ
            .replacingOccurrences(of: "\u{FB04}", with: "ffl") // ﬄ
            .replacingOccurrences(of: "\u{FB05}", with: "ft") // ﬅ
            .replacingOccurrences(of: "\u{FB06}", with: "st") // ﬆ
            // Handle smart quotes and apostrophes
            .replacingOccurrences(of: "\u{201C}", with: "\"") // Left double quotation mark
            .replacingOccurrences(of: "\u{201D}", with: "\"") // Right double quotation mark
            .replacingOccurrences(of: "\u{2018}", with: "'")  // Left single quotation mark
            .replacingOccurrences(of: "\u{2019}", with: "'")  // Right single quotation mark
            // Replace dashes
            .replacingOccurrences(of: "\u{2014}", with: "--") // Em dash
            .replacingOccurrences(of: "\u{2013}", with: "-")  // En dash
            // Remove hyphenation at line breaks
            .replacingOccurrences(of: "-\n", with: "")        // Remove hyphen and line break
            // Replace line breaks with spaces
            .replacingOccurrences(of: "\n", with: " ")
            // Normalize unicode
            .applyingTransform(.init("NFKD; [:Nonspacing Mark:] Remove;"), reverse: false) ?? text
            // Replace multiple spaces with a single space
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() // Make text case-insensitive
        
        return normalizedText
    }

    private func mapRange(
        from normalizedText: String,
        to originalText: String,
        normalizedRange: Range<String.Index>
    ) -> NSRange? {
        // Extract the substring we're looking for from the normalized text
        let targetSubstring = String(normalizedText[normalizedRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        print("    🔍 Looking for: \"\(targetSubstring)\"")
        
        // Split the substring into words for start/end matching
        let words = targetSubstring.components(separatedBy: .whitespaces)
        guard let firstWord = words.first, let lastWord = words.last else {
            print("    ❌ No words found in substring")
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
            let remainingText = originalText[firstRange.upperBound...]
            if let lastRange = remainingText.range(
                of: lastWord,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) {
                // Get the full text range from start of first word to end of last word
                let fullRange = firstRange.lowerBound...originalText.index(firstRange.upperBound, offsetBy: remainingText.distance(
                    from: remainingText.startIndex,
                    to: lastRange.upperBound
                ))
                
                // Extract and normalize the text in this range
                let extractedText = String(originalText[fullRange])
                let normalizedExtracted = normalizeText(extractedText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("    📝 Checking range: \"\(extractedText)\"")
                print("    🔄 Normalized: \"\(normalizedExtracted)\"")
                
                // Compare normalized versions, ignoring extra whitespace
                if normalizedExtracted.components(separatedBy: .whitespacesAndNewlines)
                    .joined(separator: " ")
                    .lowercased() == targetSubstring.components(separatedBy: .whitespacesAndNewlines)
                    .joined(separator: " ")
                    .lowercased() {
                    // Convert to NSRange
                    let utf16View = originalText.utf16
                    let startOffset = utf16View.distance(from: utf16View.startIndex, to: fullRange.lowerBound)
                    let endOffset = utf16View.distance(from: utf16View.startIndex, to: fullRange.upperBound)
                    let possibleRange = NSRange(location: startOffset, length: endOffset - startOffset)
                    possibleRanges.append(possibleRange)
                    print("    ✅ Found exact match")
                } else {
                    print("    ❌ Normalized text doesn't match exactly")
                }
            }
            
            // Move search start to just after this occurrence of first word
            currentSearchStart = firstRange.upperBound
            
            // Safety check to prevent infinite loop
            if currentSearchStart >= originalText.endIndex {
                break
            }
        }
        
        print("    📍 Found \(possibleRanges.count) exact matches")
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
}
