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

    // Additional properties
    var pdfDocument: PDFDocument?
    var currentSentence: String = ""
    var currentWord: String = ""
    var spokenText: String = ""
    var isTracking: Bool = false

    // Word timing properties
    private var wordTrackingDisplayLink: CADisplayLink?
    private var audioStartTime: UInt64 = 0
    private let wordHighlightLeadTime: Double = 0.1 // Increased to 100ms lead time

    // Original text for sentence matching
    private var originalText: String = ""

    private var currentWordIndex: Int = 0

    // Audio engine latency
    private var audioEngineLatency: Double = 0.0

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

    private func generateAudioBuffer(for utterance: TTSUtterance) async
        -> (buffer: AVAudioPCMBuffer, sampleRate: Int)? {
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
                    sampleRate: Double(audio.sampleRate),
                    channels: hwFormat.channelCount,
                    interleaved: false
                )!

                let frameCount = UInt32(audio.samples.count)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    continuation.resume(returning: nil)
                    return
                }
                buffer.frameLength = frameCount

                // Copy samples to all channels
                if let channelData = buffer.floatChannelData {
                    audio.samples.withUnsafeBufferPointer { samples in
                        for channel in 0 ..< Int(format.channelCount) {
                            for i in 0 ..< Int(frameCount) {
                                channelData[channel][i] = samples[i]
                            }
                        }
                    }
                }

                let sampleRate = Int(audio.sampleRate)

                continuation.resume(returning: (buffer: buffer, sampleRate: sampleRate))
            }
        }
    }

    private func playNextPreprocessedBuffer() {
        guard !preprocessedBuffers.isEmpty else {
            isSpeaking = false
            currentUtterance = nil
            return
        }

        let (utterance, buffer) = preprocessedBuffers.first!
        currentUtterance = utterance
        scheduleBuffer(buffer, for: utterance)
        isSpeaking = true

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func startWordTracking(for utterance: TTSUtterance) {
        DispatchQueue.main.async {
            self.delegate?.ttsManager(self, willSpeakWord: "", atIndex: -1)
        }

        print("Starting word tracking for utterance: \(utterance.text)")
        wordTrackingDisplayLink?.invalidate()

        currentWord = ""
        currentWordIndex = 0

        // Calculate syllable-based timing with refined estimation
        let totalSyllables = utterance.words.reduce(0) { $0 + syllableCount(for: $1) }
        let averageWordLength = utterance.words.reduce(0) { $0 + $1.count } / utterance.words.count
        let durationPerSyllable = utterance.duration / Double(max(totalSyllables, 1))

        var accumulatedTime: Double = 0.0

        // Adjust pause durations based on punctuation
        let punctuationPauseDurations: [Character: Double] = [
            ",": 0.2,
            ".": 0.4,
            "!": 0.4,
            "?": 0.4,
            ";": 0.3,
            ":": 0.3,
        ]

        // Create word infos with timing
        utterance.wordInfos = utterance.words.map { word in
            let syllables = syllableCount(for: word)
            let wordLengthFactor = Double(word.count) / Double(averageWordLength)
            let wordDuration = max(
                durationPerSyllable * Double(syllables) * wordLengthFactor,
                0.05
            ) // Minimum duration
            let timestamp = accumulatedTime

            accumulatedTime += wordDuration

            // Add pause after punctuation
            if let lastChar = word.last, let pause = punctuationPauseDurations[lastChar] {
                accumulatedTime += pause
            }

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
            self.wordTrackingDisplayLink = CADisplayLink(
                target: self,
                selector: #selector(self.updateWordTracking)
            )
            self.wordTrackingDisplayLink?.preferredFramesPerSecond = 60
            self.wordTrackingDisplayLink?.add(to: .main, forMode: .default)
        }
    }
    
    func AudioTimeStampToSeconds(_ hostTime: UInt64) -> Double {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanoseconds = (hostTime * UInt64(timebaseInfo.numer)) / UInt64(timebaseInfo.denom)
        return Double(nanoseconds) / 1_000_000_000.0
    }
    
    private func hostTimeToSeconds(_ hostTime: UInt64) -> Double {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanoseconds = (hostTime * UInt64(timebaseInfo.numer)) / UInt64(timebaseInfo.denom)
        return Double(nanoseconds) / 1_000_000_000.0
    }

    @objc private func updateWordTracking() {
        guard let utterance = currentUtterance else {
            wordTrackingDisplayLink?.invalidate()
            return
        }

        // Get the current host time
        let nowHostTime = mach_absolute_time()

        // Calculate elapsed time since audioStartTime
        var elapsedTime = hostTimeToSeconds(nowHostTime - audioStartTime)

        // Adjust for output latency if available
        let outputLatency = audioEngine.outputNode.outputPresentationLatency
        if outputLatency > 0 {
            elapsedTime -= outputLatency
        } else {
            // Adjust for audio engine latency if output latency is not available
            elapsedTime -= audioEngineLatency
        }

        // Debug logging
        print("UpdateWordTracking - Current playback time: \(elapsedTime)")

        // Check if elapsedTime exceeds utterance duration
        if elapsedTime >= (utterance.duration + 0.1) {
            wordTrackingDisplayLink?.invalidate()
            DispatchQueue.main.async {
                self.delegate?.ttsManager(self, willSpeakWord: "", atIndex: -1)
            }
            print("UpdateWordTracking - Exceeded utterance duration. Stopping word tracking.")
            return
        }

        // Find the current word based on timing
        for (index, wordInfo) in utterance.wordInfos.enumerated() {
            let wordEndTime = wordInfo.timestamp + wordInfo.duration

            // Log expected vs. actual times
            print("Expected word start time: \(wordInfo.timestamp), Current playback time: \(elapsedTime)")

            if elapsedTime >= wordInfo.timestamp && elapsedTime < wordEndTime {
                if currentWordIndex != index {
                    currentWord = wordInfo.word
                    currentWordIndex = index
                    print("🗣️ Word timing - word: \(wordInfo.word), start: \(wordInfo.timestamp), end: \(wordEndTime)")
                    DispatchQueue.main.async {
                        self.delegate?.ttsManager(self, willSpeakWord: wordInfo.word, atIndex: index)
                    }
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

        // Install audio tap to measure latency and get precise timing
        installAudioTapIfNeeded()

        // Capture the current host time
        let startTime = mach_absolute_time()

        // Schedule the buffer to play immediately
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.wordTrackingDisplayLink?.invalidate()
                self.delegate?.ttsManager(self, didFinishUtterance: utterance)
                print("Finished utterance: \(utterance.text)")

                // Remove the played buffer
                if !self.preprocessedBuffers.isEmpty {
                    self.preprocessedBuffers.removeFirst()
                }

                // Schedule next buffer if available
                if let nextBuffer = self.preprocessedBuffers.first {
                    self.delegate?.ttsManager(self, willSpeakUtterance: nextBuffer.0)
                    self.scheduleBuffer(nextBuffer.1, for: nextBuffer.0)
                } else {
                    // Remove audio tap when done
                    self.removeAudioTap()
                }
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        // Set audioStartTime to the captured host time
        audioStartTime = startTime
        print("Audio start time set to: \(audioStartTime)")
    }

    // MARK: - Audio Tap Methods

    private func installAudioTapIfNeeded() {
        // Install tap only if not already installed
        if !isAudioTapInstalled {
            converterNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] _, time in
                guard let self = self else { return }
                // Calculate audio engine latency once
                if self.audioEngineLatency == 0.0 {
                    if let outputTime = self.audioEngine.outputNode.lastRenderTime {
                        // Cast sampleTime to Double before division
                        let outputSampleTime = Double(outputTime.sampleTime)
                        let tapSampleTime = Double(time.sampleTime)

                        let latency = (outputSampleTime / outputTime.sampleRate) -
                            (tapSampleTime / time.sampleRate)
                        self.audioEngineLatency = latency
                        print("Audio engine latency measured: \(self.audioEngineLatency)")
                    }
                }
            }
            isAudioTapInstalled = true
            print("Audio tap installed.")
        }
    }

    private func removeAudioTap() {
        converterNode.removeTap(onBus: 0)
        isAudioTapInstalled = false
        audioEngineLatency = 0.0
        print("Audio tap removed.")
    }

    private var isAudioTapInstalled: Bool = false

    // MARK: - Stop, Pause, Continue

    func stopSpeaking() {
        // Stop word tracking
        wordTrackingDisplayLink?.invalidate()
        wordTrackingDisplayLink = nil

        // Remove audio tap
        removeAudioTap()

        // Reset timers and flags
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
            do {
                try audioEngine.start()
            } catch {
                print("Failed to restart audio engine: \(error)")
            }
        }

        print("Stopped speaking.")
    }

    func pauseSpeaking() {
        guard isSpeaking else { return }
        playerNode.pause()
        isPaused = true
        print("Paused speaking.")
    }

    func continueSpeaking() {
        guard isPaused else { return }
        playerNode.play()
        isPaused = false
        print("Continued speaking.")
    }

    // MARK: - Private Methods
    private func setupAudioEngine() {
        // Attach both nodes
        audioEngine.attach(playerNode)
        audioEngine.attach(converterNode)

        // Get the hardware output format
        let hwFormat = audioEngine.outputNode.outputFormat(forBus: 0)

        // Create format for TTS output
        let ttsSampleRate = 22050.0 // Replace with actual sample rate if different
        let ttsFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: ttsSampleRate,
            channels: hwFormat.channelCount,
            interleaved: false
        )!

        // Connect player -> converter -> output with appropriate formats
        audioEngine.connect(playerNode, to: converterNode, format: ttsFormat)
        audioEngine.connect(converterNode, to: audioEngine.mainMixerNode, format: hwFormat)

        do {
            try audioEngine.start()
            print("Audio engine started.")
        } catch {
            print("Failed to start audio engine: \(error)")
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
        print("Preprocessed sentences:")
        sentences.forEach { print(" - \($0)") }

        for sentence in sentences {
            guard !isStopRequested else { break }

            if let utterance = await preprocessUtterance(sentence, pageNumber: pageNumber) {
                guard let (buffer, sampleRate) = await generateAudioBuffer(for: utterance) else { continue }

                // Calculate utterance duration based on sample count and sample rate
                utterance.duration = Double(buffer.frameLength) / Double(sampleRate)
                print("Generated audio buffer for sentence: \(utterance.text)")
                print(" - Duration: \(utterance.duration) seconds")
                print(" - Sample Rate: \(sampleRate)")
                print(" - Frame Length: \(buffer.frameLength)")

                // Add to preprocessed buffers
                preprocessedBuffers.append((utterance, buffer))

                // If this is the first buffer, start playing
                if preprocessedBuffers.count == 1 {
                    DispatchQueue.main.async {
                        self.delegate?.ttsManager(self, willSpeakUtterance: utterance)
                    }
                    scheduleBuffer(buffer, for: utterance)
                }
            }
        }
    }

    private func findOriginalSentences(processed: String, in originalText: String) -> [String] {
        // Placeholder implementation for findOriginalSentences
        return [processed]
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
