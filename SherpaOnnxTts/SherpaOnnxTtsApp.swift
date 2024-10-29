//
//  SherpaOnnxTtsApp.swift
//  SherpaOnnxTts
//
//  Created by fangjun on 2023/11/23.
//

import SwiftUI

@main
struct SherpaOnnxTtsApp: App {
    @State private var ttsManager = TTSManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView(ttsManager: TTSManager())
        }
    }
}
