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
        guard let document = uiView.document else {
            return
        }

        var highlighter = PDFHighlighter(
            document: document,
            currentPageNumber: currentPage,
            highlightWord: currentWord
        )

        _ = highlighter.highlightLinesInDocument(
            lineTexts: currentLinesOriginal,
            word: currentWord
        )
    }
}
