//
//  ContentView.swift
//  SherpaOnnxTts
//
//  Created by fangjun on 2023/11/23.
//

import Combine
import PDFKit
import SwiftUI

struct ContentView: View {
    @State private var viewModel = ContentViewModel()
    @State private var text: String = ""
    @State private var showAlert: Bool = false
    @State private var showDocumentPicker = false
    @State private var showPDFPicker = false

    var body: some View {
        VStack(spacing: 20) {
            controlsSection

            // Input selection buttons
            HStack {
                Button("Text Input") {
                    viewModel.inputMode = .text
                }
                .buttonStyle(.bordered)

                Button("PDF Input") {
                    showPDFPicker = true
                }
                .buttonStyle(.bordered)
            }

            if viewModel.inputMode == .text {
                textInputSection
            } else if viewModel.inputMode == .pdf,
                      let document = viewModel.pdfDocument {
                PDFViewer(
                    document: document,
                    currentPage: viewModel.currentPage,
                    currentLinesOriginal: viewModel.currentSentenceOriginals,
                    currentWord: viewModel.currentWord,
                    pdfHighlighter: PDFHighlighter(
                        document: document,
                        currentPageNumber: viewModel.currentPage
                    )
                )
                .edgesIgnoringSafeArea(.all)
            } else {
                if viewModel.pdfPages.isEmpty {
                    Text("Select a PDF file to begin")
                } else {
                    Text("Page \(viewModel.currentPage + 1) of \(viewModel.pdfPages.count)")
                    TextEditor(text: .constant(viewModel.pdfPages[viewModel.currentPage]))
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
                viewModel.loadPDF(from: url)
            }
        }
        .sheet(isPresented: $showPDFPicker) {
            DocumentPicker { url in
                viewModel.loadPDFDocument(from: url)
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Empty Text"),
                message: Text("Please enter some text to speak."),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: viewModel.ttsManager.isSpeaking) { _, _ in
            // Update local state if needed
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
            Slider(value: $viewModel.ttsManager.rate, in: 0.5 ... 2.0) {
                Text("Rate")
            }
            .padding([.horizontal])
        }
    }

    private var volumeControl: some View {
        VStack {
            Text("Volume")
            Slider(value: $viewModel.ttsManager.volume, in: 0 ... 1) {
                Text("Volume")
            }
            .padding([.horizontal])
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
                viewModel.speakText(trimmedText)
                hideKeyboard()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("speakButton")

            if viewModel.ttsManager.isSpeaking {
                Button(viewModel.ttsManager.isPaused ? "Continue" : "Pause") {
                    if viewModel.ttsManager.isPaused {
                        viewModel.continueSpeaking()
                    } else {
                        viewModel.pauseSpeaking()
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pauseContinueButton")

                Button("Stop") {
                    viewModel.stopSpeaking()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("stopButton")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
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
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
#endif
