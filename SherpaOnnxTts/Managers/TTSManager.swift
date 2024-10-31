//
//  TTSManager.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/28/24.
//

import AVFoundation
import Combine
import Foundation
import NaturalLanguage
import PDFKit

enum InputMode {
    case text
    case pdf
}

@Observable final class TTSManager {
    // MARK: - Properties
    private var tts = createOfflineTts()
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var converterNode: AVAudioMixerNode
    private let processingQueue = DispatchQueue(
        label: "com.sherpaonnxtts.processing",
        qos: .userInitiated
    )

    private var currentUtterance: TTSUtterance?
    private var utteranceQueue: [TTSUtterance] = []
    private var processingTask: Task<Void, Never>?

    var rate: Float = 1.0
    var speakerId: Int = 0
    var volume: Float = 1.0 {
        didSet { playerNode.volume = volume }
    }

    var isPaused: Bool = false
    var isSpeaking: Bool = false

    weak var delegate: TTSManagerDelegate?

    private var isStopRequested: Bool = false

    private var preprocessingTask: Task<Void, Never>?
    private var preprocessedBuffers: [(TTSUtterance, AVAudioPCMBuffer)] = []
    private let maxPreprocessedBuffers = 2 // Keep at most 2 sentences preprocessed
    private let preprocessingQueue = DispatchQueue(
        label: "com.sherpaonnxtts.preprocessing",
        qos: .userInitiated
    )

    var inputMode: InputMode = .text
    private let pdfManager = PDFManager()

    // Add new properties
    var pdfDocument: PDFDocument?
    var currentSentence: String = ""
    var currentWord: String = ""
    var spokenText: String = ""
    var isTracking: Bool = false

    // Add new property for word timing
    private var wordTimer: Timer?
    private var estimatedWordsPerSecond: Double = 3.0 // Adjust based on speech rate

    // Add new properties
    private var wordTrackingDisplayLink: CADisplayLink?
    private var audioStartTime: Double = 0

    private let wordHighlightLeadTime: Double = 0.2 // Adjust the lead time as needed

    // MARK: - Initialization
    init() {
        converterNode = AVAudioMixerNode()
        setupAudioEngine()
    }

    // MARK: - Public Methods
    func speak(_ text: String, pageNumber: Int? = nil) {
        // Stop any existing speech and processing
        stopSpeaking()
        processingTask?.cancel()
        preprocessingTask?.cancel()

        // Reset stop flag
        isStopRequested = false

        // Preprocess text into sentences
        let sentences = preprocessText(text)
        guard !sentences.isEmpty else { return }

        // Reset tracking variables
        spokenText = ""
        currentSentence = ""
        currentWord = ""

        // Start preprocessing with text tracking
        preprocessingTask = Task { [weak self] in
            guard let self = self else { return }

            for sentence in sentences {
                guard !Task.isCancelled else { break }

                while !self.isStopRequested && self.preprocessedBuffers.count >= self.maxPreprocessedBuffers {
                    try? await Task.sleep(nanoseconds: 100000000)
                }

                guard !Task.isCancelled && !self.isStopRequested else { break }

                let utterance = TTSUtterance(sentence, pageNumber: pageNumber)

                if let buffer = await self.generateAudioBuffer(for: utterance) {
                    Task {
                        self.preprocessedBuffers.append((utterance, buffer))
                        if !self.isSpeaking {
                            self.playNextPreprocessedBuffer()
                        }
                    }
                }
            }
        }

        if let pageNumber = pageNumber {
            pdfManager.setCurrentPage(pageNumber)
        }
    }

    private func generateAudioBuffer(for utterance: TTSUtterance) async -> AVAudioPCMBuffer? {
        return await withCheckedContinuation { continuation in
            self.preprocessingQueue.async {
                let audio = self.tts.generate(
                    text: utterance.text,

                    sid: self.speakerId,

                    speed: self.rate
                )

                // Get hardware format for channel count
                let hwFormat = self.audioEngine.outputNode.outputFormat(forBus: 0)

                // Create buffer with TTS format matching hardware channels
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 22050,
                    channels: hwFormat.channelCount,
                    interleaved: false
                )!

                let frameCount = UInt32(audio.samples.count)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
                buffer.frameLength = frameCount

                // Copy samples to all channels
                let samples = audio.samples.withUnsafeBufferPointer { $0 }
                if let channelData = buffer.floatChannelData {
                    for channel in 0 ..< Int(format.channelCount) {
                        for i in 0 ..< Int(frameCount) {
                            channelData[channel][i] = samples[i]
                        }
                    }
                }

                continuation.resume(returning: buffer)
            }
        }
    }

    private func playNextPreprocessedBuffer() {
        guard !preprocessedBuffers.isEmpty else {
            isSpeaking = false
            currentUtterance = nil
            return
        }

        let (utterance, buffer) = preprocessedBuffers.removeFirst()
        currentUtterance = utterance
        scheduleBuffer(buffer, for: utterance)
        isSpeaking = true

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func startWordTracking(for utterance: TTSUtterance) {
        wordTrackingDisplayLink?.invalidate()

        // Estimate word durations based on word length
        let totalDuration = utterance.duration
        let totalCharacters = utterance.words.reduce(0) { $0 + $1.count }

        // Calculate timestamps for each word
        var accumulatedTime: Double = 0.0
        utterance.wordTimestamps = utterance.words.map { word in
            let proportion = Double(word.count) / Double(totalCharacters)
            let wordDuration = totalDuration * proportion
            let timestamp = max(0, accumulatedTime - wordHighlightLeadTime)
            accumulatedTime += wordDuration
            return (word: word, timestamp: timestamp)
        }

        audioStartTime = CACurrentMediaTime()

        wordTrackingDisplayLink = CADisplayLink(target: self, selector: #selector(updateWordTracking))
        wordTrackingDisplayLink?.preferredFramesPerSecond = 120
        wordTrackingDisplayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateWordTracking() {
        guard let utterance = currentUtterance,
              !utterance.wordTimestamps.isEmpty else {
            wordTrackingDisplayLink?.invalidate()
            return
        }

        let currentTime = CACurrentMediaTime() - audioStartTime
        let totalDuration = utterance.duration

        // Ensure we don't exceed the total duration
        if currentTime >= totalDuration {
            wordTrackingDisplayLink?.invalidate()
            return
        }

        // Find the word that should be highlighted at the current time
        var wordFound = false
        for (index, wordInfo) in utterance.wordTimestamps.enumerated() {
            let wordStartTime = wordInfo.timestamp
            let wordEndTime = (index < utterance.wordTimestamps.count - 1) ?
                utterance.wordTimestamps[index + 1].timestamp : totalDuration

            if currentTime >= wordStartTime && currentTime < wordEndTime {
                if currentWord != wordInfo.word {
                    currentWord = wordInfo.word
                    delegate?.ttsManager(self, willSpeakWord: wordInfo.word)
                }
                wordFound = true
                break
            }
        }

        // Handle cases where currentTime is before the first word's timestamp
        if !wordFound && currentTime < utterance.wordTimestamps.first!.timestamp {
            currentWord = utterance.words.first!
            delegate?.ttsManager(self, willSpeakWord: currentWord)
        }
    }

    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer, for utterance: TTSUtterance) {
        playerNode.volume = volume

        // Calculate utterance duration
        utterance.duration = Double(buffer.frameLength) / buffer.format.sampleRate

        // Start word tracking before playing
        startWordTracking(for: utterance)

        // Schedule the main buffer
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self else { return }

            // No silence buffer, proceed immediately
            Task {
                self.delegate?.ttsManager(self, didFinishUtterance: utterance)

                // Access the next utterance
                if let nextUtterance = self.preprocessedBuffers.first?.0 {
                    self.delegate?.ttsManager(self, willSpeakUtterance: nextUtterance)
                }

                // Start word-level tracking
                self.startWordTracking(for: utterance)

                self.playNextPreprocessedBuffer()
            }
        }
    }

    func stopSpeaking() {
        // Stop word tracking
        wordTrackingDisplayLink?.invalidate()
        wordTrackingDisplayLink = nil

        // Rest of the existing stop implementation
        // Reference existing implementation:
        wordTimer?.invalidate()
        wordTimer = nil
        // Set stop flag first
        isStopRequested = true

        // Cancel all processing tasks
        processingTask?.cancel()
        preprocessingTask?.cancel()
        processingTask = nil
        preprocessingTask = nil

        // Reset all state
        isSpeaking = false
        isPaused = false
        currentUtterance = nil
        preprocessedBuffers.removeAll()

        // Stop the player node and reset its scheduled buffers
        playerNode.stop()
        playerNode.reset()

        // Reset the audio engine if needed
        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
    }

    func pauseSpeaking() {
        guard isSpeaking else { return }
        playerNode.pause()
        isPaused = true
    }

    func continueSpeaking() {
        guard isPaused else { return }
        playerNode.play()
        isPaused = false
    }

    // MARK: - Private Methods
    private func setupAudioEngine() {
        // Attach both nodes
        audioEngine.attach(playerNode)
        audioEngine.attach(converterNode)

        // Get the hardware output format
        let hwFormat = audioEngine.outputNode.outputFormat(forBus: 0)

        // Create format for TTS output (22.05kHz, match hardware channels)
        let ttsFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 22050,
            channels: hwFormat.channelCount,
            interleaved: false
        )!

        // Connect player -> converter -> output with appropriate formats
        audioEngine.connect(playerNode, to: converterNode, format: ttsFormat)
        audioEngine.connect(converterNode, to: audioEngine.mainMixerNode, format: hwFormat)

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func updatePlaybackRate() {
        // AVAudioUnitTimePitch.rate ranges from 0.25 to 4.0
        // Ensure 'rate' is within this range
        let clampedRate = max(0.25, min(rate, 4.0))
        print("Playback rate updated to \(clampedRate)")
    }

    private func createAudioBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        // This method is now integrated into the 'speak' method for clarity
        return nil
    }

    private func processNextUtterance() {
        guard isSpeaking, let utterance = utteranceQueue.first else {
            isSpeaking = false
            return
        }

        currentUtterance = utterance
        isSpeaking = true

        // Generate audio for the entire utterance
        let audio = tts.generate(text: utterance.text, sid: speakerId, speed: rate)

        // Calculate utterance duration based on sample count and sample rate
        utterance.duration = Double(audio.samples.count) / 22050.0 // Using known sample rate

        // Calculate word timings
        let wordsCount = Double(utterance.words.count)
        let timePerWord = utterance.duration / wordsCount

        // Create timestamps for each word
        utterance.wordTimestamps = utterance.words.enumerated().map { index, word in
            let timestamp = timePerWord * Double(index)
            return (word: word, timestamp: max(0, timestamp))
        }

        // Create and schedule audio buffer
        let mainMixerFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: mainMixerFormat.sampleRate,
            channels: mainMixerFormat.channelCount,
            interleaved: false
        )!

        let frameCount = UInt32(audio.samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        // Copy samples to buffer
        if let channelData = buffer.floatChannelData {
            audio.samples.withUnsafeBufferPointer { samples in
                for channel in 0 ..< Int(format.channelCount) {
                    for i in 0 ..< Int(frameCount) {
                        channelData[channel][i] = samples[i]
                    }
                }
            }
        }

        // Start word tracking before playing
        startWordTracking(for: utterance)

        playerNode.volume = volume
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.wordTrackingDisplayLink?.invalidate()
                self.delegate?.ttsManager(self, didFinishUtterance: utterance)
                if !self.utteranceQueue.isEmpty {
                    self.utteranceQueue.removeFirst()
                }
                self.processNextUtterance()
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func loadPDF(from url: URL) -> [String] {
        return pdfManager.loadPDF(from: url)
    }

    private func preprocessText(_ text: String) -> [String] {
        // Initialize sentence tokenizer
        let sentenceTokenizer = NLTokenizer(unit: .sentence)

        // Process text to handle line breaks and hyphenation
        var processedText = text

        // Handle hyphenated words split across lines
        processedText = processedText.replacingOccurrences(
            of: "-\\s*\n\\s*",
            with: "",
            options: .regularExpression,
            range: nil
        )

        // Split text into lines for title detection
        let lines = processedText.components(separatedBy: "\n")
        var sentences: [String] = []
        var currentParagraph: [String] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty { continue }

            // Title detection heuristics
            let isTitle = isTitleLine(trimmedLine)

            if isTitle {
                // If we have a pending paragraph, process it first
                if !currentParagraph.isEmpty {
                    let paragraphText = currentParagraph.joined(separator: " ")
                    sentences.append(contentsOf: tokenizeSentences(paragraphText, sentenceTokenizer))
                    currentParagraph.removeAll()
                }
                // Add the title as a separate sentence
                sentences.append(trimmedLine)
            } else {
                currentParagraph.append(trimmedLine)
            }
        }

        // Process any remaining paragraph text
        if !currentParagraph.isEmpty {
            let paragraphText = currentParagraph.joined(separator: " ")
            sentences.append(contentsOf: tokenizeSentences(paragraphText, sentenceTokenizer))
        }

        return sentences.filter { !$0.isEmpty }
    }

    private func isTitleLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.isEmpty { return false }

        // Check for common title indicators
        let startsWithKeyword = trimmedLine.lowercased().hasPrefix("book") ||
            trimmedLine.lowercased().hasPrefix("chapter")

        // Check if all significant words are capitalized
        let words = trimmedLine.split(separator: " ")
        let isTitleCase = words.count <= 7 && words.allSatisfy { word in
            guard let first = word.first else { return false }
            // Ignore small words like "a", "the", "in", etc.
            let smallWords = ["a", "an", "the", "in", "on", "at", "to", "for", "of", "and"]
            return first.isUppercase || smallWords.contains(word.lowercased())
        }

        // Check for sentence-ending punctuation
        let hasEndPunctuation = trimmedLine.hasSuffix(".") ||
            trimmedLine.hasSuffix("?") ||
            trimmedLine.hasSuffix("!")

        return (startsWithKeyword || isTitleCase) && !hasEndPunctuation
    }

    private func tokenizeSentences(_ text: String, _ tokenizer: NLTokenizer) -> [String] {
        var sentences: [String] = []
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        return sentences
    }
}

// MARK: - Delegate Protocol
protocol TTSManagerDelegate: AnyObject {
    func ttsManager(_ manager: TTSManager, didFinishUtterance utterance: TTSUtterance)
    func ttsManager(_ manager: TTSManager, willSpeakUtterance utterance: TTSUtterance)
    func ttsManager(_ manager: TTSManager, willSpeakWord word: String)
}
