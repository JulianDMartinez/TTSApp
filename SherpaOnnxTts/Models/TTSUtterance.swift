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

struct ChunkInfo {
    let chunk: String
    let timestamp: Double
    let duration: Double
}

class TTSUtterance {
    let originalTexts: [String]
    let text: String
    var chunks: [String] = []
    var chunkInfos: [ChunkInfo] = []
    var duration: Double = 0.0
    let pageNumber: Int?
    
    init(originalTexts: [String], processedText: String, pageNumber: Int? = nil) {
        self.originalTexts = originalTexts
        self.text = processedText
        self.pageNumber = pageNumber
        
        // Tokenize the sentence into chunks
        self.chunks = tokenizeSentenceIntoChunks(processedText)
    }
}

func tokenizeSentenceIntoChunks(_ sentence: String) -> [String] {
    // Define a list of punctuation marks and conjunctions that often correspond to pauses
    let pauseIndicators = [",", ";", ":", ".", "!", "?", "—", "–", "…", "and", "but", "or", "so", "because", "however", "therefore", "although"]

    // Escape special regex characters in pause indicators
    let escapedPauseIndicators = pauseIndicators.map { NSRegularExpression.escapedPattern(for: $0) }

    // Create a pattern to match these indicators
    let pattern = "\\b(?:\(escapedPauseIndicators.joined(separator: "|")))(?=\\s)|(?<=\\s)(?:\(escapedPauseIndicators.joined(separator: "|")))\\b|[.,;:!?—–…]"

    // Compile the regex safely
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        print("⚠️ Invalid regex pattern: \(pattern)")
        return [sentence] // Return the whole sentence if regex fails
    }

    let nsSentence = sentence as NSString
    let matches = regex.matches(in: sentence, options: [], range: NSRange(location: 0, length: nsSentence.length))

    var chunks: [String] = []
    var lastIndex = 0

    for match in matches {
        let range = NSRange(location: lastIndex, length: match.range.location - lastIndex)
        if range.length > 0 {
            let chunk = nsSentence.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
        }
        lastIndex = match.range.location + match.range.length
    }

    // Add any remaining text as a chunk
    if lastIndex < nsSentence.length {
        let range = NSRange(location: lastIndex, length: nsSentence.length - lastIndex)
        let chunk = nsSentence.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        if !chunk.isEmpty {
            chunks.append(chunk)
        }
    }

    return chunks
}
