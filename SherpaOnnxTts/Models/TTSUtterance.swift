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
    var currentWordIndex: Int = 0
    var range: Range<String.Index>?
    var isTitle: Bool = false
    var pageNumber: Int?
    var characterRange: NSRange?

    init(_ text: String, pageNumber: Int? = nil) {
        self.text = text
        // Split text into words, preserving punctuation
        self.words = text.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        self.pageNumber = pageNumber
    }
    
    var currentWord: String {
        guard currentWordIndex < words.count else { return "" }
        return words[currentWordIndex]
    }
}
