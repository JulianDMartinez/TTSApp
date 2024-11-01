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

    private let wordHighlightLeadTime: Double = 0.05 // 50ms lead time

    // Add property to store original text
    private var originalText: String = ""

    private var currentWordIndex: Int = 0

    // MARK: - Initialization
    init() {
        converterNode = AVAudioMixerNode()
        setupAudioEngine()
    }

    // MARK: - Public Methods
    func speak(_ text: String, pageNumber: Int? = nil) {
        // Store the original text when speaking
        originalText = text

        print("originalText: \(originalText)")
        Task {
            await processText(text, pageNumber: pageNumber)
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
        delegate?.ttsManager(self, willSpeakWord: "", atIndex: -1)
        
        print("Starting word tracking for utterance: \(utterance.text)")
        wordTrackingDisplayLink?.invalidate()
        
        currentWord = ""
        currentWordIndex = 0
        
        // Calculate syllable-based timing with improved accuracy
        let totalSyllables = utterance.words.reduce(0) { $0 + syllableCount(for: $1) }
        let durationPerSyllable = utterance.duration / Double(max(totalSyllables, 1))
        
        var accumulatedTime: Double = 0.0
        let pauseDuration: Double = 0.15 // Slightly reduced pause duration
        
        // Create word infos with timing
        utterance.wordInfos = utterance.words.map { word in
            let syllables = syllableCount(for: word)
            let wordDuration = max(durationPerSyllable * Double(syllables), 0.05) // Minimum duration
            let timestamp = accumulatedTime
            
            // Add pause after punctuation
            if word.last?.isPunctuation == true {
                accumulatedTime += pauseDuration
            }
            
            accumulatedTime += wordDuration
            
            return WordInfo(
                word: word,
                timestamp: max(0, timestamp - wordHighlightLeadTime),
                duration: wordDuration,
                syllableCount: syllables
            )
        }
        
        // Debug log word timings
        print("Word timing breakdown:")
        utterance.wordInfos.forEach { info in
            print("Word: \(info.word), Start: \(info.timestamp), Duration: \(info.duration)")
        }
        
        currentUtterance = utterance
        
        DispatchQueue.main.async {
            self.wordTrackingDisplayLink = CADisplayLink(target: self, selector: #selector(self.updateWordTracking))
            self.wordTrackingDisplayLink?.preferredFramesPerSecond = 60
            self.wordTrackingDisplayLink?.add(to: .main, forMode: .default)
        }
    }

    @objc private func updateWordTracking() {
        guard let utterance = currentUtterance,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            wordTrackingDisplayLink?.invalidate()
            return
        }
        
        let currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
        
        // Add debug logging
        print("Current playback time: \(currentTime)")
        
        // Check if currentTime exceeds utterance duration (with a small buffer)
        if currentTime >= (utterance.duration + 0.1) {
            wordTrackingDisplayLink?.invalidate()
            delegate?.ttsManager(self, willSpeakWord: "", atIndex: -1)
            return
        }
        
        // Find the current word based on timing
        for (index, wordInfo) in utterance.wordInfos.enumerated() {
            let wordEndTime = wordInfo.timestamp + wordInfo.duration
            
            if currentTime >= wordInfo.timestamp && currentTime < wordEndTime {
                if currentWordIndex != index {
                    currentWord = wordInfo.word
                    currentWordIndex = index
                    print("🗣️ Word timing - word: \(wordInfo.word), start: \(wordInfo.timestamp), end: \(wordEndTime)")
                    delegate?.ttsManager(self, willSpeakWord: wordInfo.word, atIndex: index)
                }
                return
            }
        }
    }

    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer, for utterance: TTSUtterance) {
        DispatchQueue.main.async {
            self.currentUtterance = utterance
            self.startWordTracking(for: utterance)
        }
        
        playerNode.volume = volume
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.wordTrackingDisplayLink?.invalidate()
                self.delegate?.ttsManager(self, didFinishUtterance: utterance)

                // Remove the played buffer
                if !self.preprocessedBuffers.isEmpty {
                    self.preprocessedBuffers.removeFirst()
                }

                // Schedule next buffer if available
                if let nextBuffer = self.preprocessedBuffers.first {
                    self.delegate?.ttsManager(self, willSpeakUtterance: nextBuffer.0)
                    self.scheduleBuffer(nextBuffer.1, for: nextBuffer.0)
                }
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
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

    private func findOriginalSentences(processed: String, in originalText: String) -> [String] {
        print("\n🔄 Finding original sentences")
        print("Processed text: \"\(processed)\"")

        // Normalize the processed text
        let normalizedProcessed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: " ")
            .lowercased()

        // Split original text into sentences with word boundaries
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = originalText

        var bestMatch: (sentences: [String], score: Double) = ([], 0.0)
        var currentSequence: [String] = []

        // Lower threshold for better matching
        let threshold = max(0.6, Double(normalizedProcessed.count) / 100.0)

        // Handle hyphenated words and sentence fragments
        var isHyphenated = false
        var lastSentenceFragment = ""

        sentenceTokenizer.enumerateTokens(in: originalText.startIndex ..< originalText.endIndex) { range, _ in
            let sentence = String(originalText[range])
            var normalizedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)

            // If we have a fragment from previous iteration, prepend it
            if !lastSentenceFragment.isEmpty {
                normalizedSentence = lastSentenceFragment + " " + normalizedSentence
                lastSentenceFragment = ""
            }

            // Check if sentence ends with hyphen
            if normalizedSentence.hasSuffix("-") {
                isHyphenated = true
                currentSequence.append(normalizedSentence)
                return true
            }

            // Handle incomplete sentences
            if !normalizedSentence.hasSuffix(".") &&
                !normalizedSentence.hasSuffix("!") &&
                !normalizedSentence.hasSuffix("?") {
                lastSentenceFragment = normalizedSentence
                return true
            }

            let finalSentence = isHyphenated ?
                currentSequence.joined() + normalizedSentence :
                normalizedSentence

            currentSequence.append(finalSentence)
            isHyphenated = false

            // Calculate similarity score with word-level comparison
            let score = calculateSimilarityScore(
                between: normalizedProcessed,
                and: finalSentence.lowercased()
            )

            if score > threshold {
                bestMatch = ([finalSentence], score)
                return false
            }

            return true
        }

        // Handle any remaining fragment
        if !lastSentenceFragment.isEmpty {
            let finalSentence = currentSequence.last ?? ""
            let combinedSentence = finalSentence + " " + lastSentenceFragment
            let score = calculateSimilarityScore(
                between: normalizedProcessed,
                and: combinedSentence.lowercased()
            )

            if score > threshold {
                bestMatch = ([combinedSentence], score)
            }
        }

        return bestMatch.score > 0.0 ? bestMatch.sentences : [processed]
    }

    private func calculateSimilarityScore(between str1: String, and str2: String) -> Double {
        let normalized1 = str1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized2 = str2.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Use Levenshtein distance for better accuracy
        let distance = levenshteinDistance(between: normalized1, and: normalized2)
        let maxLength = Double(max(normalized1.count, normalized2.count))

        // Calculate similarity score (1.0 means perfect match, 0.0 means completely different)
        return 1.0 - (Double(distance) / maxLength)
    }

    private func levenshteinDistance(between str1: String, and str2: String) -> Int {
        let str1Array = Array(str1)
        let str2Array = Array(str2)
        let m = str1Array.count
        let n = str2Array.count

        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0 ... m {
            matrix[i][0] = i
        }

        for j in 0 ... n {
            matrix[0][j] = j
        }

        for i in 1 ... m {
            for j in 1 ... n {
                if str1Array[i - 1] == str2Array[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = min(
                        matrix[i - 1][j] + 1, // deletion
                        matrix[i][j - 1] + 1, // insertion
                        matrix[i - 1][j - 1] + 1 // substitution
                    )
                }
            }
        }

        return matrix[m][n]
    }

    private func preprocessUtterance(_ sentence: String, pageNumber: Int?) async -> TTSUtterance? {
        guard !isStopRequested else { return nil }
        
        let originalSentences = findOriginalSentences(
            processed: sentence,
            in: originalText
        )
        
        return TTSUtterance(
            originalTexts: originalSentences.isEmpty ? [sentence] : originalSentences,
            processedText: sentence,
            pageNumber: pageNumber
        )
    }

    private func processText(_ text: String, pageNumber: Int?) async {
        // Reset stop flag and clear any existing buffers
        isStopRequested = false
        preprocessedBuffers.removeAll()

        // Store original text for sentence matching
        originalText = text

        // Preprocess text into sentences
        let sentences = preprocessText(text)

        for sentence in sentences {
            guard !isStopRequested else { break }

            if let utterance = await preprocessUtterance(sentence, pageNumber: pageNumber) {
                let audio = tts.generate(text: utterance.text, sid: speakerId, speed: rate)

                let mainMixerFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: mainMixerFormat.sampleRate,
                    channels: mainMixerFormat.channelCount,
                    interleaved: false
                )!

                let frameCount = UInt32(audio.samples.count)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    continue
                }

                buffer.frameLength = frameCount

                if let channelData = buffer.floatChannelData {
                    audio.samples.withUnsafeBufferPointer { samples in
                        for channel in 0 ..< Int(format.channelCount) {
                            for i in 0 ..< Int(frameCount) {
                                channelData[channel][i] = samples[i]
                            }
                        }
                    }
                }

                // Calculate utterance duration based on sample count and sample rate
                utterance.duration = Double(audio.samples.count) / Double(audio.sampleRate)

                // Remove wordTimestamps
                // No need for wordTimestamps; rely solely on wordInfos in startWordTracking

                // Add to preprocessed buffers
                preprocessedBuffers.append((utterance, buffer))

                // If this is the first buffer, start playing
                if preprocessedBuffers.count == 1 {
                    delegate?.ttsManager(self, willSpeakUtterance: utterance)
                    scheduleBuffer(buffer, for: utterance)
                }
            }
        }
    }

    private func syllableCount(for word: String) -> Int {
        let vowels = "aeiouy"
        let word = word.lowercased()
        var count = 0
        var lastWasVowel = false
        
        for char in word {
            if vowels.contains(char) {
                if !lastWasVowel {
                    count += 1
                    lastWasVowel = true
                }
            } else {
                lastWasVowel = false
            }
        }
        
        // Adjust for silent 'e' at the end
        if word.hasSuffix("e") {
            count = max(count - 1, 1)
        }
        
        return max(count, 1)
    }
}

// MARK: - Delegate Protocol
protocol TTSManagerDelegate: AnyObject {
    func ttsManager(_ manager: TTSManager, didFinishUtterance utterance: TTSUtterance)
    func ttsManager(_ manager: TTSManager, willSpeakUtterance utterance: TTSUtterance)
    func ttsManager(_ manager: TTSManager, willSpeakWord word: String, atIndex index: Int)
}
