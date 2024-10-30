//
//  TTSManager.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/28/24.
//

import Foundation
import AVFoundation
import Combine
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
    private let processingQueue = DispatchQueue(label: "com.sherpaonnxtts.processing",
                                              qos: .userInitiated)
    
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
    private let preprocessingQueue = DispatchQueue(label: "com.sherpaonnxtts.preprocessing",
                                                qos: .userInitiated)
    
    var inputMode: InputMode = .text
    private let pdfManager = PDFManager()
    
    // Add new properties
    var pdfDocument: PDFDocument?
    var currentSentence: String = ""
    var currentWord: String = ""
    var spokenText: String = ""
    var isTracking: Bool = false
    
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
        
        // Split text into lines first to identify titles
        let lines = text.components(separatedBy: .newlines)
        var processedText = ""
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLine.isEmpty {
                // If line doesn't end with sentence endings and is followed by more text,
                // it might be a title - add a special marker
                if !trimmedLine.hasSuffix(".") && !trimmedLine.hasSuffix("!") && 
                   !trimmedLine.hasSuffix("?") && index < lines.count - 1 {
                    processedText += trimmedLine + ".|" // Special marker for titles
                } else {
                    processedText += trimmedLine + " "
                }
            }
        }
        
        // Split text into sentences, now handling our special title marker
        let sentences = processedText.components(separatedBy: CharacterSet(charactersIn: ".|!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !sentences.isEmpty else { return }
        
        // Update spoken text tracking
        spokenText = ""
        currentSentence = ""
        currentWord = ""
        
        // Start preprocessing with text tracking
        preprocessingTask = Task { [weak self] in
            guard let self = self else { return }
            
            for (_, sentence) in sentences.enumerated() {
                guard !Task.isCancelled else { break }
                
                while !self.isStopRequested && self.preprocessedBuffers.count >= self.maxPreprocessedBuffers {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                
                guard !Task.isCancelled && !self.isStopRequested else { break }
                
                let utterance = TTSUtterance(sentence)
                // Mark if this was a title (ended with our special marker in the original text)
                utterance.isTitle = processedText.contains(sentence + ".|")
                
                let buffer = await self.generateAudioBuffer(for: utterance)
                
                if let buffer = buffer {
                    Task {
                        self.currentWord = utterance.text
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
                let audio = self.tts.generate(text: utterance.text, 
                                           sid: self.speakerId, 
                                           speed: self.rate)
                
                // Get hardware format for channel count
                let hwFormat = self.audioEngine.outputNode.outputFormat(forBus: 0)
                
                // Create buffer with TTS format matching hardware channels
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 22050,
                    channels: hwFormat.channelCount,
                    interleaved: false)!
                
                let frameCount = UInt32(audio.samples.count)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
                buffer.frameLength = frameCount
                
                // Copy samples to all channels
                let samples = audio.samples.withUnsafeBufferPointer { $0 }
                if let channelData = buffer.floatChannelData {
                    for channel in 0..<Int(format.channelCount) {
                        for i in 0..<Int(frameCount) {
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
    
    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer, for utterance: TTSUtterance) {
        playerNode.volume = volume
        
        // Create a silence buffer with appropriate duration
        let silenceBuffer: AVAudioPCMBuffer?
        if utterance.isTitle {
            silenceBuffer = createSilenceBuffer(duration: 0.1)
        } else if utterance.text.trimmingCharacters(in: .whitespaces).hasSuffix(".") {
            // Normal sentence pause (0.4 seconds)
            silenceBuffer = createSilenceBuffer(duration: 1.8)
        } else {
            silenceBuffer = nil
        }
        
        // Schedule the main buffer
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self else { return }
            
            // If we have a silence buffer, schedule it
            if let silenceBuffer = silenceBuffer {
                self.playerNode.scheduleBuffer(silenceBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    guard let self = self, !self.isStopRequested else { return }
                    
                    Task {
                        self.delegate?.ttsManager(self, didFinishUtterance: utterance)
                        print("Finished playing '\(utterance.text)'")
                        
                        // Access the next utterance
                        if let nextUtterance = self.preprocessedBuffers.first?.0 {
                            print("Next utterance: '\(nextUtterance.text)'")
                            self.delegate?.ttsManager(self, willSpeakUtterance: nextUtterance)
                            // You can perform additional actions with nextUtterance here
                        } else {
                            print("No more utterances in the queue.")
                        }
                        
                        self.playNextPreprocessedBuffer()
                    }
                }
            } else {
                // No silence buffer, proceed immediately
                Task {
                    self.delegate?.ttsManager(self, didFinishUtterance: utterance)
                    print("Finished playing '\(utterance.text)'")
                    
                    // Access the next utterance
                    if let nextUtterance = self.preprocessedBuffers.first?.0 {
                        print("Next utterance: '\(nextUtterance.text)'")
                        self.delegate?.ttsManager(self, willSpeakUtterance: nextUtterance)
                        // You can perform additional actions with nextUtterance here
                    } else {
                        print("No more utterances in the queue.")
                    }
                    
                    self.playNextPreprocessedBuffer()
                }
            }
        }
    }
    
    private func createSilenceBuffer(duration: Double) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 22050,
            channels: audioEngine.outputNode.outputFormat(forBus: 0).channelCount,
            interleaved: false)!
        
        let frameCount = UInt32(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        
        buffer.frameLength = frameCount
        
        // Fill with silence (zeros)
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(frameCount) {
                    channelData[channel][frame] = 0.0
                }
            }
        }
        
        return buffer
    }
    
    func stopSpeaking() {
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
            interleaved: false)!
        
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
        // Don't process next utterance if we've stopped speaking
        guard isSpeaking,
              !utteranceQueue.isEmpty,
              let utterance = utteranceQueue.first else {
            isSpeaking = false
            return
        }
        
        currentUtterance = utterance
        isSpeaking = true
        
        // Generate audio for the entire utterance
        let audio = tts.generate(text: utterance.text, sid: speakerId, speed: rate)
        
        // Create buffer with main mixer format
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
        
        // Copy samples to all channels
        let samples = audio.samples.withUnsafeBufferPointer { $0 }
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                for i in 0..<Int(frameCount) {
                    channelData[channel][i] = samples[i]
                }
            }
        }
        
        playerNode.volume = volume
        
        // Schedule buffer with completion handler for utterance tracking
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
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
}


// MARK: - Delegate Protocol
protocol TTSManagerDelegate: AnyObject {
    func ttsManager(_ manager: TTSManager, didFinishUtterance utterance: TTSUtterance)
    func ttsManager(_ manager: TTSManager, willSpeakUtterance utterance: TTSUtterance)
}
