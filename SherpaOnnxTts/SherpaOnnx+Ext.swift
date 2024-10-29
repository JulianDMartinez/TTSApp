// MARK: - SherpaOnnx+Ext.swift

import Foundation

extension SherpaOnnxOfflineTtsWrapper {
    func generateSpeech(text: String, speakerId: Int) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            let workItem = DispatchWorkItem {
                do {
                    let generatedAudio = self.generate(text: text, sid: speakerId)
                    continuation.resume(returning: generatedAudio.samples)
                } catch {
                    continuation.resume(throwing: TTSError.generationFailed(error))
                }
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
