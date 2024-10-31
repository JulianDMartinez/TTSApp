import PDFKit
import SwiftUI
import UIKit

struct PDFViewer: UIViewRepresentable {
    let document: PDFDocument
    let currentPage: Int
    let spokenText: String
    let currentSentence: String
    let currentSentenceOriginal: String
    let currentWord: String
    let isTracking: Bool

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .white
        pdfView.pageShadowsEnabled = true
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let document = uiView.document,
              let page = document.page(at: currentPage) else { return }

        var highlighter = PDFHighlighter(
            document: document,
            currentPageNumber: currentPage,
            spokenText: spokenText,
            highlightWord: currentWord
        )
        
        let didHighlight = highlighter.highlightTextInDocument(
            sentence: currentSentenceOriginal,
            word: currentWord
        )
        
        // Scroll to the word annotation if needed
//        if isTracking, let wordAnnotation = PDFHighlighter.currentWordAnnotation {
//            uiView.go(to: wordAnnotation)
//        }
    }
}
