//
//  TTSUtterance.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/29/24.
//

import Foundation

class TTSUtterance {
    let text: String
    let words: [String]
    var wordTimestamps: [(word: String, timestamp: Double)] = []
    var currentWordIndex: Int = 0
    var isTitle: Bool = false
    var pageNumber: Int?
    var duration: Double = 0.0

    init(_ text: String, pageNumber: Int? = nil) {
        self.text = text
        // Use a regular expression to split text into words, including punctuation attached to words
        let regexPattern = "[\\w'-]+|[.,!?;:]"
        let regex = try? NSRegularExpression(pattern: regexPattern, options: [])
        let matches = regex?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? []

        self.words = matches.compactMap {
            if let range = Range($0.range, in: text) {
                return String(text[range])
            }
            return nil
        }
        self.pageNumber = pageNumber
    }

    var currentWord: String {
        guard currentWordIndex < words.count else { return "" }
        return words[currentWordIndex]
    }
}
