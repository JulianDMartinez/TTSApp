import SwiftUI
import PDFKit

struct PDFViewer: UIViewRepresentable {
    let document: PDFDocument
    let currentPage: Int
    let currentLinesOriginal: [String]
    let currentWord: String

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = true
        pdfView.document = document
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        print("\n🔄 PDFViewer update")
        print("Current lines count: \(currentLinesOriginal.count)")
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

        let didHighlight = highlighter.highlightLinesInDocument(
            lineTexts: currentLinesOriginal,
            word: currentWord
        )

        print("✅ Highlight result: \(didHighlight)")
    }
}
