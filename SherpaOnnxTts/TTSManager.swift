//
//  TTSManager.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/28/24.
//

import Foundation
import AVFoundation

@Observable final class TTSManager {
    private var tts = createOfflineTts()
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var converterNode: AVAudioMixerNode
    private let processingQueue = DispatchQueue(label: "com.sherpaonnxtts.processing", qos: .userInitiated)
    private var currentUtterance: TTSUtterance?
    private var utteranceQueue: [TTSUtterance] = []
    private var processingTask: Task<Void, Never>?
    
    var rate: Float = 1.0
    var speakerId: Int = 0
    var volume: Float = 1.0
    var isPaused: Bool = false
    var isSpeaking: Bool = false
    
    // Add delegate for utterance progress
    var delegate: TTSManagerDelegate?
    
    init() {
        converterNode = AVAudioMixerNode()
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        // Attach both nodes
        audioEngine.attach(playerNode)
        audioEngine.attach(converterNode)
        
        // Get the hardware output format
        let hwFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        
        // Create format for TTS output (22.05kHz)
        let ttsFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: 22050,
                                    channels: 1,
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
    
    func speak(_ text: String) {
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
                        
                        // Create buffer with TTS format
                        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                 sampleRate: 22050,
                                                 channels: 1,
                                                 interleaved: false)!
                        
                        let frameCount = UInt32(audio.samples.count)
                        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
                        buffer.frameLength = frameCount
                        
                        // Copy samples to buffer
                        let samples = audio.samples.withUnsafeBufferPointer { $0 }
                        for i in 0..<Int(frameCount) {
                            buffer.floatChannelData?[0][i] = samples[i]
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
        processingTask?.cancel()
        processingTask = nil
        playerNode.stop()
        utteranceQueue.removeAll()
        currentUtterance = nil
        isSpeaking = false
        isPaused = false
    }
    
    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer, for utterance: TTSUtterance) {
        playerNode.volume = volume
        
        // Schedule buffer with completion handler for utterance tracking
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                self?.utteranceDidComplete()
            }
        }
    }
    
    private func utteranceDidComplete() {
        delegate?.ttsManager(self, didFinishUtterance: currentUtterance!)
        utteranceQueue.removeFirst()
        processNextUtterance()
    }
    
    private func processNextUtterance() {
        guard let utterance = utteranceQueue.first else {
            isSpeaking = false
            return
        }
        
        currentUtterance = utterance
        isSpeaking = true
        
        // Generate audio for the entire utterance
        let audio = tts.generate(text: utterance.text, sid: speakerId, speed: rate)
        
        // Create buffer with TTS format
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                 sampleRate: 22050,
                                 channels: 1,
                                 interleaved: false)!
        
        let frameCount = UInt32(audio.samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        // Copy samples to buffer
        let samples = audio.samples.withUnsafeBufferPointer { $0 }
        for i in 0..<Int(frameCount) {
            buffer.floatChannelData?[0][i] = samples[i]
        }
        
        playerNode.volume = volume
        
        // Schedule buffer with completion handler for utterance tracking
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                self?.utteranceDidComplete()
            }
        }
        
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
    
    func pauseSpeaking() {
        playerNode.pause()
        isPaused = true
    }
    
    func continueSpeaking() {
        playerNode.play()
        isPaused = false
    }
}

// Add TTSUtterance class
class TTSUtterance {
    let text: String
    var range: Range<String.Index>?
    
    init(_ text: String) {
        self.text = text
    }
}

// Add delegate protocol
protocol TTSManagerDelegate: AnyObject {
    func ttsManager(_ manager: TTSManager, didFinishUtterance utterance: TTSUtterance)
    func ttsManager(_ manager: TTSManager, willSpeakUtterance utterance: TTSUtterance)
}
