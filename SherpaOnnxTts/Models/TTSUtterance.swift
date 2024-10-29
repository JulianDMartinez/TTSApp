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
    
    init(_ text: String) {
        self.text = text
    }
}
