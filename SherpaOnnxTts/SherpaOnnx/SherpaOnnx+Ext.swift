// MARK: - SherpaOnnx+Ext.swift

import Foundation

extension SherpaOnnxOfflineTtsWrapper {
    func generateSpeech(text: String, speakerId: Int) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            let workItem = DispatchWorkItem {
                let generatedAudio = self.generate(text: text, sid: speakerId)
                continuation.resume(returning: generatedAudio.samples)
            }
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        }
    }
}

enum TTSError: Error {
    case generationFailed(Error)
    case invalidFormat
    case audioEngineError(Error)
}
