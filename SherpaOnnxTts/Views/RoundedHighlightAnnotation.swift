import PDFKit

class RoundedHighlightAnnotation: PDFAnnotation {
    private let cornerRadius: CGFloat = 0.2
    
    override init(bounds: CGRect, forType annotationType: PDFAnnotationSubtype, withProperties properties: [AnyHashable : Any]?) {
        super.init(bounds: bounds, forType: .highlight, withProperties: properties)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let page = self.page else { return }
        
        context.saveGState()
        
        // Set blend mode for highlighting
        context.setBlendMode(.multiply)
        
        // Get the transformation matrix for the annotation's bounds
        let transform = page.transform(for: box)
        context.concatenate(transform)
        
        // Create path for rounded rectangle
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
        
        // Clip to the path to ensure we only draw within the rounded rectangle
        context.addPath(path.cgPath)
        context.clip()
        
        // Draw the highlight
        context.setFillColor(color.cgColor)
        context.fill(bounds)
        
        context.restoreGState()
    }
}
