//
//  PDFHighlighter.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/30/24.
//

import Foundation
import PDFKit
import NaturalLanguage

struct PDFHighlighter {
    let document: PDFDocument
    var currentPageNumber: Int

    static var currentSentenceAnnotations: [PDFAnnotation] = []
    static var currentWordAnnotation: PDFAnnotation?
    static var currentChunkAnnotations: [PDFAnnotation] = []

    var lastHighlightedRange: NSRange?

    // Add new property to track current sentence bounds
    private var currentSentenceBounds: CGRect?

    // Add new property to store word ranges
    private var wordRangesInSentence: [NSRange] = []

    // Add property to store chunk ranges
    private var chunkRangesInSentence: [NSRange] = []

    init(document: PDFDocument, currentPageNumber: Int) {
        self.document = document
        self.currentPageNumber = currentPageNumber
    }

    mutating func clearWordHighlight() {
        guard let page = document.page(at: currentPageNumber) else { return }
        
        if let wordAnnotation = PDFHighlighter.currentWordAnnotation {
            page.removeAnnotation(wordAnnotation)
            PDFHighlighter.currentWordAnnotation = nil
        }
        
        // Also clear chunk highlights
        clearChunkHighlights()
    }

    mutating func clearSentenceHighlights() {
        guard let page = document.page(at: currentPageNumber) else { return }
        
        for annotation in PDFHighlighter.currentSentenceAnnotations {
            page.removeAnnotation(annotation)
        }
        PDFHighlighter.currentSentenceAnnotations.removeAll()
        lastHighlightedRange = nil
    }

    /// Attempts to highlight specified lines and a word in a PDF document
    /// - Parameters:
    ///   - lineTexts: Array of text lines to highlight
    /// - Returns: Boolean indicating if any highlights were successfully added
    mutating func highlightLinesInDocument(lineTexts: [String]) -> Bool {
        print("📚 Highlighting lines: \(lineTexts)")
        guard let currentPage = document.page(at: currentPageNumber) else { return false }

        clearSentenceHighlights()
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
                            PDFHighlighter.currentSentenceAnnotations.append(annotation)
                        }
                        didHighlightAny = true
                        
                        // Store the word ranges in the sentence
                        storeWordRangesInSentence(
                            sentenceRange: originalRange,
                            pageContent: pageContent
                        )

                        // Store the chunk ranges in the sentence
                        storeChunkRangesInSentence(
                            sentenceRange: originalRange,
                            pageContent: pageContent
                        )
                        continue
                    }
                }
            }
        }

        // After creating line annotations, set the sentence bounds to encompass all the annotations
        if !PDFHighlighter.currentSentenceAnnotations.isEmpty {
            let sentenceBounds = PDFHighlighter.currentSentenceAnnotations.reduce(PDFHighlighter.currentSentenceAnnotations[0].bounds) { 
                $0.union($1.bounds) 
            }
            setCurrentSentenceBounds(sentenceBounds)
            print("📏 Set sentence bounds from annotations union: \(sentenceBounds)")
        }

        return didHighlightAny
    }

    /// Handles highlighting of a specific word within a line's bounds
    /// - Parameters:
    ///   - word: The word to highlight
    ///   - currentPage: The current PDF page
    ///   - lineBounds: The bounds of the line containing the word
    private mutating func handleWordHighlighting(
        word: String,
        atIndex index: Int,
        currentPage: PDFPage
    ) {
        print("🔍 Handling word highlight for: '\(word)' at index \(index)")
        print("📊 Available word ranges: \(wordRangesInSentence.count)")
        
        clearWordHighlight()
        
        guard index >= 0, index < wordRangesInSentence.count else {
            print("⚠️ Word index \(index) out of bounds (available ranges: 0...\(wordRangesInSentence.count - 1))")
            return
        }
        
        let wordRange = wordRangesInSentence[index]
        print("✨ Using word range: \(wordRange)")
        
        if let selection = currentPage.selection(for: wordRange) {
            let wordBounds = selection.bounds(for: currentPage)
            print("✨ Creating word highlight at bounds: \(wordBounds)")
            
            let wordAnnotation = RoundedHighlightAnnotation(
                bounds: wordBounds,
                forType: .highlight,
                withProperties: nil
            )
            wordAnnotation.color = UIColor.orange.withAlphaComponent(0.3)
            currentPage.addAnnotation(wordAnnotation)
            PDFHighlighter.currentWordAnnotation = wordAnnotation
        } else {
            print("⚠️ Could not create selection for word at index \(index)")
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

    mutating func updateWordHighlight(word: String, atIndex index: Int) {
        guard let currentPage = document.page(at: currentPageNumber) else { return }
        clearWordHighlight()
        handleWordHighlighting(
            word: word,
            atIndex: index,
            currentPage: currentPage
        )
    }

    // Add method to set current sentence bounds
    mutating func setCurrentSentenceBounds(_ bounds: CGRect) {
        print("📏 Setting current sentence bounds: \(bounds)")
        currentSentenceBounds = bounds
    }

    // Add this method after setCurrentSentenceBounds:
    private func debugSentenceBounds() {
        if let bounds = currentSentenceBounds {
            print("""
            🔍 Current sentence bounds:
            x: \(bounds.origin.x), y: \(bounds.origin.y)
            width: \(bounds.size.width), height: \(bounds.size.height)
            """)
        } else {
            print("⚠️ No sentence bounds set")
        }
    }

    private mutating func storeWordRangesInSentence(
        sentenceRange: NSRange,
        pageContent: String
    ) {
        guard let stringRange = Range(sentenceRange, in: pageContent) else { return }
        let sentenceText = String(pageContent[stringRange])
        
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = sentenceText
        wordRangesInSentence.removeAll()
        
        // Enumerate through each word token and calculate its range
        tokenizer.enumerateTokens(in: sentenceText.startIndex..<sentenceText.endIndex) { tokenRange, _ in
            // Convert the token range to NSRange relative to the sentence text
            let nsRange = NSRange(tokenRange, in: sentenceText) 
            
            // Adjust the range to be relative to the page content
            let adjustedRange = NSRange(
                location: sentenceRange.location + nsRange.location,
                length: nsRange.length
            )
            wordRangesInSentence.append(adjustedRange)
            print("📝 Stored word range: \(adjustedRange) for word: '\(sentenceText[tokenRange])'")
            return true
        }
        
        print("📚 Total word ranges stored: \(wordRangesInSentence.count)")
    }

    private mutating func storeChunkRangesInSentence(
        sentenceRange: NSRange,
        pageContent: String
    ) {
        guard let stringRange = Range(sentenceRange, in: pageContent) else { return }
        let sentenceText = String(pageContent[stringRange])
        
        let chunks = tokenizeSentenceIntoChunks(sentenceText)
        
        var currentLocation = sentenceRange.location
        chunkRangesInSentence.removeAll()
        
        for chunk in chunks {
            let chunkLength = (chunk as NSString).length
            let adjustedRange = NSRange(location: currentLocation, length: chunkLength)
            chunkRangesInSentence.append(adjustedRange)
            print("📝 Stored chunk range: \(adjustedRange) for chunk: '\(chunk)'")
            currentLocation += chunkLength + 1 // +1 for the delimiter
        }
        
        print("📚 Total chunk ranges stored: \(chunkRangesInSentence.count)")
    }

    mutating func updateChunkHighlight(chunk: String, atIndex index: Int) {
        guard let currentPage = document.page(at: currentPageNumber) else { return }
        clearWordHighlight()
        handleChunkHighlighting(
            chunk: chunk,
            atIndex: index,
            currentPage: currentPage
        )
    }

    private mutating func handleChunkHighlighting(
        chunk: String,
        atIndex index: Int,
        currentPage: PDFPage
    ) {
        print("🔍 Handling chunk highlight for: '\(chunk)' at index \(index)")
        print("📊 Available chunk ranges: \(chunkRangesInSentence.count)")
        
        // Clear existing chunk highlights
        clearChunkHighlights()
        
        guard index >= 0, index < chunkRangesInSentence.count else {
            print("⚠️ Chunk index \(index) out of bounds")
            return
        }
        
        let chunkRange = chunkRangesInSentence[index]
        print("✨ Using chunk range: \(chunkRange)")
        
        if let selection = currentPage.selection(for: chunkRange) {
            // Split selection into lines
            let lineSelections = selection.selectionsByLine()
            var annotations: [PDFAnnotation] = []
            
            for lineSelection in lineSelections {
                let lineBounds = lineSelection.bounds(for: currentPage)
                print("✨ Creating chunk highlight at line bounds: \(lineBounds)")
                
                let chunkAnnotation = RoundedHighlightAnnotation(
                    bounds: lineBounds,
                    forType: .highlight,
                    withProperties: nil
                )
                chunkAnnotation.color = UIColor.orange.withAlphaComponent(0.3)
                currentPage.addAnnotation(chunkAnnotation)
                annotations.append(chunkAnnotation)
            }
            
            // Store annotations for later removal
            PDFHighlighter.currentChunkAnnotations = annotations
        } else {
            print("⚠️ Could not create selection for chunk at index \(index)")
        }
    }

    mutating func clearChunkHighlights() {
        guard let page = document.page(at: currentPageNumber) else { return }
        
        for annotation in PDFHighlighter.currentChunkAnnotations {
            page.removeAnnotation(annotation)
        }
        PDFHighlighter.currentChunkAnnotations.removeAll()
    }
}
