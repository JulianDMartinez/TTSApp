//
//  PDFManager.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/30/24.
//

import PDFKit
import Foundation

class PDFManager {
    private var document: PDFDocument?
    private var currentPageNumber: Int = 0
    
    func loadPDF(from url: URL) -> [String] {
        document = PDFDocument(url: url)
        return extractPages()
    }
    
    private func extractPages() -> [String] {
        guard let document = document else { return [] }
        var texts = [String]()
        
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let text = page.string {
                texts.append(text)
            }
        }
        
        return texts
    }
    
    func setCurrentPage(_ page: Int) {
        currentPageNumber = page
    }
}
