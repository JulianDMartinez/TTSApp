//
//  TTSManager.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/28/24.
//

import Foundation
import AVFoundation
import Combine

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
    
    // MARK: - Initialization
    init() {
        converterNode = AVAudioMixerNode()
        setupAudioEngine()
    }
    
    // MARK: - Public Methods
        func speak(_ text: String) {
        // Reset stop flag
        isStopRequested = false
        
        // Stop any existing speech and processing
        stopSpeaking()
        processingTask?.cancel()
        
        // Split text into sentences
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !sentences.isEmpty else { return }
        
        processingTask = Task { [weak self] in
            guard let self = self else { return }
            
            for sentence in sentences {
                guard !Task.isCancelled else { break }
                
                let utterance = TTSUtterance(sentence)
                
                // Process utterance on background queue
                await withCheckedContinuation { continuation in
                    self.processingQueue.async {
                        // Generate audio for the utterance
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
                        
                        // Schedule playback on main thread
                        DispatchQueue.main.async {
                            self.utteranceQueue.append(utterance)
                            self.scheduleBuffer(buffer, for: utterance)
                            
                            if !self.isSpeaking {
                                self.isSpeaking = true
                                self.currentUtterance = utterance
                                self.playerNode.play()
                            }
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }
    
    func stopSpeaking() {
        // Set stop flag first
        isStopRequested = true
        
        // Cancel the processing task if it's running
        processingTask?.cancel()
        processingTask = nil
        
        // Reset all state before stopping player
        isSpeaking = false
        isPaused = false
        currentUtterance = nil
        utteranceQueue.removeAll()
        
        // Stop the player node and reset its scheduled buffers
        playerNode.stop()
        playerNode.reset()  // This removes any scheduled buffers
        
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
    
    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer, for utterance: TTSUtterance) {
        playerNode.volume = volume
        
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self, !self.isStopRequested else { return }
            
            Task { @MainActor in
                self.delegate?.ttsManager(self, didFinishUtterance: utterance)
                if !self.utteranceQueue.isEmpty {
                    self.utteranceQueue.removeFirst()
                }
                self.processNextUtterance()
            }
        }
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
            
            Task { @MainActor in
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
}

// MARK: - TTSUtterance Class
class TTSUtterance {
    let text: String
    var range: Range<String.Index>?
    
    init(_ text: String) {
        self.text = text
    }
}

// MARK: - Delegate Protocol
protocol TTSManagerDelegate: AnyObject {
    func ttsManager(_ manager: TTSManager, didFinishUtterance utterance: TTSUtterance)
    func ttsManager(_ manager: TTSManager, willSpeakUtterance utterance: TTSUtterance)
}
