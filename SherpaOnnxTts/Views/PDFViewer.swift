import PDFKit
import SwiftUI
import UIKit

struct PDFViewer: UIViewRepresentable {
    let document: PDFDocument
    let currentPage: Int
    let spokenText: String
    let currentSentence: String
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
        if let document = uiView.document,
           let page = document.page(at: currentPage) {
            var highlighter = PDFHighlighter(
                document: document,
                currentPageNumber: currentPage,
                spokenText: spokenText,
                highlightWord: currentWord
            )
            
            let didHighlight = highlighter.highlightTextInDocument(
                sentence: currentSentence,
                word: currentWord
            )
            
            if isTracking {
                let destination = PDFDestination(
                    page: page,
                    at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height)
                )
                UIView.animate(withDuration: 0.3) {
                    uiView.go(to: destination)
                }
            }
        }
    }
}