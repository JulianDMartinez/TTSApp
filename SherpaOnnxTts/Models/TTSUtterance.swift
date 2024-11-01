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
    // Split the sentence into words
    let words = sentence.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
    
    var chunks: [String] = []
    var currentChunk = ""
    let maxWordsPerChunk = 5 // Adjust as needed
    
    for word in words {
        currentChunk += currentChunk.isEmpty ? word : " \(word)"
        if currentChunk.components(separatedBy: .whitespaces).count >= maxWordsPerChunk {
            chunks.append(currentChunk)
            currentChunk = ""
        }
    }
    
    if !currentChunk.isEmpty {
        chunks.append(currentChunk)
    }
    
    return chunks
}
