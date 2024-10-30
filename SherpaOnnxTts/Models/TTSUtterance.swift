//
//  TTSUtterance.swift
//  SherpaOnnxTts
//
//  Created by Julian Martinez on 10/29/24.
//

import Foundation

class TTSUtterance {
    let text: String
    var range: Range<String.Index>?
    var isTitle: Bool = false
    var pageNumber: Int?
    var characterRange: NSRange?
    
    init(_ text: String, pageNumber: Int? = nil) {
        self.text = text
        self.pageNumber = pageNumber
    }
}
