//
//  TTSUtterance.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/29/24.
//

import Foundation
import NaturalLanguage

public struct WordInfo {
    let word: String
    let timestamp: Double
    let duration: Double
    let syllableCount: Int
}

class TTSUtterance {
    let originalTexts: [String]
    let text: String
    let words: [String]
    var wordTimestamps: [(word: String, timestamp: Double)] = []
    var wordInfos: [WordInfo] = []
    var duration: Double = 0.0
    let pageNumber: Int?
    
    init(originalTexts: [String], processedText: String, pageNumber: Int? = nil) {
        self.originalTexts = originalTexts
        self.text = processedText
        self.pageNumber = pageNumber
        
        let wordTokenizer = NLTokenizer(unit: .word)
        wordTokenizer.string = processedText
        
        var words: [String] = []
        let range = processedText.startIndex..<processedText.endIndex
        
        wordTokenizer.enumerateTokens(in: range) { tokenRange, _ in
            let word = String(processedText[tokenRange])
            if !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                words.append(word)
            }
            return true
        }
        
        self.words = words
    }
}
