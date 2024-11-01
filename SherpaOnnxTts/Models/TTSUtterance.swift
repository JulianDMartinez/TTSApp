//
//  TTSUtterance.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/29/24.
//

import Foundation
import NaturalLanguage

class TTSUtterance {
    let originalTexts: [String]  // Array of original texts as they appear in PDF
    let text: String            // Processed text for TTS
    let words: [String]
    var wordTimestamps: [(word: String, timestamp: Double)] = []
    var currentWordIndex: Int = 0
    var isTitle: Bool = false
    var pageNumber: Int?
    var duration: Double = 0.0

    init(originalTexts: [String], processedText: String, pageNumber: Int? = nil) {
        self.originalTexts = originalTexts
        self.text = processedText
        self.pageNumber = pageNumber
        
        // Initialize word tokenizer with better options
        let wordTokenizer = NLTokenizer(unit: .word)
        wordTokenizer.string = processedText
        
        // Get word tokens with their ranges
        var words: [String] = []
        let range = processedText.startIndex..<processedText.endIndex
        
        wordTokenizer.enumerateTokens(in: range) { tokenRange, attributes in
            let word = String(processedText[tokenRange])
            // Only include actual words, not whitespace or punctuation
            if !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !word.trimmingCharacters(in: .punctuationCharacters).isEmpty {
                words.append(word)
            }
            return true
        }
        
        self.words = words
        
        // Detect if this is a title
        self.isTitle = originalTexts.allSatisfy { text in
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedText.split(separator: "\n").count == 1 &&
                   !trimmedText.hasSuffix(".") &&
                   !trimmedText.hasSuffix("?") &&
                   !trimmedText.hasSuffix("!") &&
                   trimmedText.count < 100
        }
    }

    var currentWord: String {
        guard currentWordIndex < words.count else { return "" }
        return words[currentWordIndex]
    }
}
