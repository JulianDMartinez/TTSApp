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
        print("\n🔄 PDFViewer update")
        print("Current line: \"\(currentSentenceOriginal)\"")
        print("Current word: \"\(currentWord)\"")

        guard let document = uiView.document else {
            print("❌ No document")
            return
        }

        var highlighter = PDFHighlighter(
            document: document,
            currentPageNumber: currentPage,
            highlightWord: currentWord
        )

        let didHighlight = highlighter.highlightLineInDocument(
            lineText: currentSentenceOriginal,
            word: currentWord
        )

        print("✅ Highlight result: \(didHighlight)")
    }
}
