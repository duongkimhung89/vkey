import CoreGraphics
import CoreText
import Foundation
let path = CommandLine.arguments[1]
var box = CGRect(x: 0, y: 0, width: 22, height: 16)
let context = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil)!
context.beginPDFPage(nil)

// macOS draws its own badge from TISIconLabels only for Apple's sources, so
// this reproduces that badge at its native 22x16 pt (a larger page is scaled
// but laid out at its original size, which pushes it off centre).  Template
// image: opaque black badge, glyphs knocked out (even-odd fill; PDF has no
// "clear" blend mode).
let badge = box
let shape = CGMutablePath()
shape.addPath(CGPath(roundedRect: badge, cornerWidth: 4, cornerHeight: 4, transform: nil))

let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 10.5, nil)!
let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "VK", attributes: attributes))
let textBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
let origin = CGPoint(x: (box.width - textBounds.width) / 2 - textBounds.origin.x,
                     y: (box.height - textBounds.height) / 2 - textBounds.origin.y)
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
    for i in 0..<count {
        guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
        shape.addPath(glyph, transform: CGAffineTransform(translationX: origin.x + positions[i].x, y: origin.y + positions[i].y))
    }
}
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.addPath(shape)
context.fillPath(using: .evenOdd)
context.endPDFPage()
context.closePDF()
