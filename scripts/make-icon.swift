import CoreGraphics
import CoreText
import Foundation
let path = CommandLine.arguments[1]
var box = CGRect(x: 0, y: 0, width: 32, height: 32)
let context = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil)!
context.beginPDFPage(nil)
let pill = CGRect(x: 1.5, y: 5.5, width: 29, height: 21)
context.setFillColor(CGColor(gray: 0.78, alpha: 1))
context.addPath(CGPath(roundedRect: pill, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
context.fillPath()

let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 18.0, nil)
let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.25, alpha: 1),
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "VK", attributes: attributes))
var textBounds = CTLineGetBoundsWithOptions(line, [])
let textX = (box.width - textBounds.width) / 2 - textBounds.origin.x
let textY = (box.height - textBounds.height) / 2 - textBounds.origin.y
context.textPosition = CGPoint(x: textX, y: textY)
CTLineDraw(line, context)
context.endPDFPage()
context.closePDF()
