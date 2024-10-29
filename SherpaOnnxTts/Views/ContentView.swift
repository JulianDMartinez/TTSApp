//
//  ContentView.swift
//  SherpaOnnxTts
//
//  Created by fangjun on 2023/11/23.
//
// Text-to-speech with Next-gen Kaldi on iOS without Internet connection

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var keyboard = KeyboardResponder()
    @State var ttsManager: TTSManager
    @State private var text: String = ""
    @State private var showAlert: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            controlsSection
            textInputSection
            Spacer()
            actionButtons
                .padding(.bottom, keyboard.currentHeight > 0 ? keyboard.currentHeight : 20)
                .animation(.easeOut(duration: 0.16), value: keyboard.currentHeight)
        }
        .padding()
        .alert("Empty Text", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter some text to speak")
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
    
    private var controlsSection: some View {
        VStack(spacing: 12) {
            rateControl
            volumeControl
        }
    }
    
    private var rateControl: some View {
        VStack {
            Text("Rate")
            Slider(value: $ttsManager.rate, in: 0.5...2.0) {
                Text("Rate")
            }
        }
    }
    
    private var volumeControl: some View {
        VStack {
            Text("Volume")
            Slider(value: $ttsManager.volume, in: 0...1) {
                Text("Volume")
            }
        }
    }
    
    private var textInputSection: some View {
        VStack(alignment: .leading) {
            Text("Please input your text below")
                .padding([.trailing, .top, .bottom])
            
            TextEditor(text: $text)
                .font(.body)
                .opacity(text.isEmpty ? 0.25 : 1)
                .disableAutocorrection(true)
                .border(Color.black)
                .frame(height: 200)
        }
    }
    
    private var actionButtons: some View {
        HStack {
            Spacer()
            
            Button("Speak") {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedText.isEmpty {
                    showAlert = true
                    return
                }
                ttsManager.speak(trimmedText)
                hideKeyboard()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("speakButton")
            
            if ttsManager.isSpeaking {
                Button(ttsManager.isPaused ? "Continue" : "Pause") {
                    if ttsManager.isPaused {
                        ttsManager.continueSpeaking()
                    } else {
                        ttsManager.pauseSpeaking()
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pauseContinueButton")
                
                Button("Stop") {
                    ttsManager.stopSpeaking()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("stopButton")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(ttsManager: TTSManager())
    }
}

// MARK: - Keyboard Responder

final class KeyboardResponder: ObservableObject {
    @Published var currentHeight: CGFloat = 0
    private var cancellableSet: Set<AnyCancellable> = []

    init() {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { notification -> CGFloat in
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    return frame.height
                }
                return 0
            }
        
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ -> CGFloat in 0 }
        
        Publishers.Merge(willShow, willHide)
            .subscribe(on: RunLoop.main)
            .assign(to: \.currentHeight, on: self)
            .store(in: &cancellableSet)
    }
}

// MARK: - Hide Keyboard Extension

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
