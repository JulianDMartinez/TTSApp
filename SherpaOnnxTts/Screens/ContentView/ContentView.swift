//
//  ContentView.swift
//  SherpaOnnxTts
//
//  Created by fangjun on 2023/11/23.
//
// Text-to-speech with Next-gen Kaldi on iOS without Internet connection

import SwiftUI
import Combine
import PDFKit

struct ContentView: View {
    @State var ttsManager: TTSManager
    @State private var text: String = ""
    @State private var showAlert: Bool = false
    @State private var showDocumentPicker = false
    @State private var pdfPages: [String] = []
    @State private var currentPage = 0
    @State private var showPDFPicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            controlsSection
            
            // Input selection buttons
            HStack {
                Button("Text Input") {
                    ttsManager.inputMode = .text
                }
                .buttonStyle(.bordered)
                
                Button("PDF Input") {
                    showPDFPicker = true
                }
                .buttonStyle(.bordered)
            }
            
            if ttsManager.inputMode == .text {
                textInputSection
            } else if ttsManager.inputMode == .pdf,
                      let document = ttsManager.pdfDocument {
                PDFViewer(document: document,
                         currentPage: currentPage,
                         spokenText: ttsManager.spokenText,
                         currentSentence: ttsManager.currentSentence,
                         currentWord: ttsManager.currentWord,
                         isTracking: ttsManager.isTracking)
                    .edgesIgnoringSafeArea(.all)
            } else {
                if pdfPages.isEmpty {
                    Text("Select a PDF file to begin")
                } else {
                    Text("Page \(currentPage + 1) of \(pdfPages.count)")
                    TextEditor(text: .constant(pdfPages[currentPage]))
                        .font(.body)
                        .border(Color.black)
                        .frame(height: 200)
                }
            }
            
            Spacer()
            actionButtons
        }
        .padding()
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in
                pdfPages = ttsManager.loadPDF(from: url)
                if !pdfPages.isEmpty {
                    ttsManager.inputMode = .pdf
                    ttsManager.speak(pdfPages[currentPage])
                }
            }
        }
        .sheet(isPresented: $showPDFPicker) {
            DocumentPicker { url in
                if let document = PDFDocument(url: url) {
                    ttsManager.pdfDocument = document
                    ttsManager.inputMode = .pdf
                    if let text = document.page(at: 0)?.string {
                        ttsManager.speak(text, pageNumber: 0)
                    }
                }
            }
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
