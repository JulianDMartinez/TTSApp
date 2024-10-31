import SwiftUI
import PDFKit

struct PDFViewer: UIViewRepresentable {
    let document: PDFDocument
    let currentPage: Int
    let currentLinesOriginal: [String]  // This is already an array but we're not using it fully
    let currentWord: String

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = true
        pdfView.document = document
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let document = uiView.document else {
            return
        }

        var highlighter = PDFHighlighter(
            document: document,
            currentPageNumber: currentPage,
            highlightWord: currentWord
        )

        // Now we pass all lines to be highlighted
        _ = highlighter.highlightLinesInDocument(
            lineTexts: currentLinesOriginal,  // This now correctly uses all sentences
            word: currentWord
        )
    }
}
