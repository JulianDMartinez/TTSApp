//
//  ContentViewModel.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/28/24.
//

import Foundation
import PDFKit

@Observable
class ContentViewModel {
    // MARK: - Published Properties for UI Binding
    var spokenText: String = ""
    var currentSentence: String = ""
    var currentWord: String = ""
    var isTracking: Bool = false
    var pdfDocument: PDFDocument?
    var currentPage: Int = 0
    var pdfPages: [String] = []
    var inputMode: InputMode = .text
    var isSpeaking: Bool = false
    var isPaused: Bool = false
    var currentSentenceOriginals: [String] = []
    var pdfHighlighter: PDFHighlighter?

    // MARK: - TTS Manager
    var ttsManager: TTSManager

    init() {
        ttsManager = TTSManager()
        ttsManager.delegate = self
    }

    // MARK: - Additional Methods

    func speakText(_ text: String) {
        ttsManager.speak(text)
    }

    func speakPage(_ pageNumber: Int) {
        guard let document = pdfDocument else { return }
        if let page = document.page(at: pageNumber), let text = page.string {
            ttsManager.speak(text, pageNumber: pageNumber)
        }
    }

    func loadPDF(from url: URL) {
        pdfPages = ttsManager.loadPDF(from: url)
        if !pdfPages.isEmpty {
            inputMode = .pdf
            speakPage(currentPage)
        }
    }

    func loadPDFDocument(from url: URL) {
        if let document = PDFDocument(url: url) {
            pdfDocument = document
            pdfHighlighter = PDFHighlighter(
                document: document,
                currentPageNumber: currentPage
            )
            inputMode = .pdf
            if let text = document.page(at: 0)?.string {
                ttsManager.speak(text, pageNumber: 0)
            }
        }
    }

    func pauseSpeaking() {
        ttsManager.pauseSpeaking()
        isPaused = true
    }

    func continueSpeaking() {
        ttsManager.continueSpeaking()
        isPaused = false
    }

    func stopSpeaking() {
        ttsManager.stopSpeaking()
        isSpeaking = false
        isPaused = false
    }
}

extension ContentViewModel: TTSManagerDelegate {
    // MARK: - TTSManagerDelegate Methods

    func ttsManager(_ manager: TTSManager, willSpeakUtterance utterance: TTSUtterance) {
        print("\n📢 Will speak utterance")
        print("Original texts: \"\(utterance.originalTexts.joined(separator: "\n"))\"")
        print("Processed text: \"\(utterance.text)\"")
        
        DispatchQueue.main.async {
            // Clear previous sentence highlights before starting new utterance
            self.pdfHighlighter?.highlightLinesInDocument(lineTexts: utterance.originalTexts)
            
            self.currentSentenceOriginals = utterance.originalTexts.isEmpty ? [utterance.text] : utterance.originalTexts
            self.currentSentence = utterance.text
            self.currentWord = ""
            self.spokenText += utterance.text + " "
            self.isTracking = true
            self.isSpeaking = true
            self.isPaused = false
        }
    }

    func ttsManager(_ manager: TTSManager, didFinishUtterance utterance: TTSUtterance) {
        DispatchQueue.main.async {
            // Clear highlights when utterance is finished
            self.pdfHighlighter?.clearSentenceHighlights()
            self.pdfHighlighter?.clearWordHighlight()
            
            self.isTracking = false
            self.currentWord = ""
            self.isSpeaking = false
            self.isPaused = false
        }
    }

    func ttsManager(_ manager: TTSManager, willSpeakWord word: String, atIndex index: Int) {
        print("\n🗣️ Will speak word: \"\(word)\" at index \(index)")
        
        DispatchQueue.main.async {
            self.currentWord = word
            self.pdfHighlighter?.updateWordHighlight(word: word, atIndex: index)
        }
    }
}
