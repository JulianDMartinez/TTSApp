//
//  ContentView.swift
//  SherpaOnnxTts
//
//  Created by fangjun on 2023/11/23.
//
// Text-to-speech with Next-gen Kaldi on iOS without Internet connection

import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var text = ""
    @State private var showAlert = false
    @State private var ttsManager = TTSManager()
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Spacer()
                Text("Next-gen Kaldi: TTS").font(.title)
                Spacer()
            }
            
            HStack {
                Text("Speaker ID")
                TextField("Please input a speaker ID", value: $ttsManager.speakerId, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            }
            
            HStack {
                Text("Speed \(String(format: "%.1f", ttsManager.rate))")
                    .padding(.trailing)
                Slider(value: $ttsManager.rate, in: 0.5...2.0, step: 0.1) {
                    Text("Speech speed")
                }
            }
            
            HStack {
                Text("Volume")
                Slider(value: $ttsManager.volume, in: 0...1) {
                    Text("Volume")
                }
            }
            
            Text("Please input your text below")
                .padding([.trailing, .top, .bottom])
            
            TextEditor(text: $text)
                .font(.body)
                .opacity(text.isEmpty ? 0.25 : 1)
                .disableAutocorrection(true)
                .border(Color.black)
            
            Spacer()
            
            HStack {
                Spacer()
                Button(action: {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty {
                        showAlert = true
                        return
                    }
                    ttsManager.speak(t)
                }) {
                    Text("Speak")
                }
                
                if ttsManager.isSpeaking {
                    Button(action: {
                        if ttsManager.isPaused {
                            ttsManager.continueSpeaking()
                        } else {
                            ttsManager.pauseSpeaking()
                        }
                    }) {
                        Text(ttsManager.isPaused ? "Resume" : "Pause")
                    }
                    
                    Button(action: {
                        ttsManager.stopSpeaking()
                    }) {
                        Text("Stop")
                    }
                }
                Spacer()
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Empty text"),
                    message: Text("Please input your text before clicking the Speak button")
                )
            }
            Spacer()
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
