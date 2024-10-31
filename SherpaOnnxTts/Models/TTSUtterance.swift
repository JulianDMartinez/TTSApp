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
        
        // Initialize word tokenizer
        let wordTokenizer = NLTokenizer(unit: .word)
        wordTokenizer.string = processedText
        
        // Get word tokens with their ranges
        var words: [String] = []
        wordTokenizer.enumerateTokens(in: processedText.startIndex..<processedText.endIndex) { range, attributes in
            let word = String(processedText[range])
            if !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                words.append(word)
            }
            return true
        }
        
        self.words = words
        self.pageNumber = pageNumber
        
        // Detect if this is a title based on characteristics
        self.isTitle = originalTexts.allSatisfy { text in
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedText.split(separator: "\n").count == 1 && 
                   !trimmedText.contains(".") && 
                   trimmedText.count < 100 && 
                   !trimmedText.hasSuffix("?") && 
                   !trimmedText.hasSuffix("!")
        }
    }

    var currentWord: String {
        guard currentWordIndex < words.count else { return "" }
        return words[currentWordIndex]
    }
}
