import SwiftUI
import PDFKit
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
//        print("DEBUG: PDFViewer updating with:")
//        print("- Current page: \(currentPage)")
//        print("- Spoken text: '\(spokenText)'")
//        print("- Current sentence: '\(currentSentence)'")
//        print("- Current word: '\(currentWord)'")
        
        if let document = uiView.document,
           let page = document.page(at: currentPage) {
            
            let highlighter = PDFHighlighter(
                document: document,
                currentPageNumber: currentPage,
                spokenText: spokenText,
                highlightWord: currentWord
            )
            
            highlighter.clearHighlights()
            
            let didHighlight = highlighter.highlightTextInDocument(
                sentence: currentSentence,
                word: currentWord
            )
            print("Highlighting result: \(didHighlight)")
            
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
