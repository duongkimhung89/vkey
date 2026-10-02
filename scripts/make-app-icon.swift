import CoreGraphics
import CoreText
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make-app-icon.swift OUTPUT_ICONSET\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func iconImage(size: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let unit = CGFloat(size)
    let outer = CGRect(x: unit * 0.06, y: unit * 0.06, width: unit * 0.88, height: unit * 0.88)
    let radius = unit * 0.22

    context.setFillColor(color(0.0, 0.25, 0.62))
    context.addPath(CGPath(roundedRect: outer, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()

    let inner = outer.insetBy(dx: unit * 0.025, dy: unit * 0.025)
    context.setFillColor(color(0.04, 0.42, 1.0))
    context.addPath(CGPath(roundedRect: inner, cornerWidth: radius * 0.9, cornerHeight: radius * 0.9, transform: nil))
    context.fillPath()

    context.setStrokeColor(color(0.55, 0.82, 0.94, 0.7))
    context.setLineWidth(max(1, unit * 0.012))
    context.addPath(CGPath(roundedRect: inner.insetBy(dx: unit * 0.012, dy: unit * 0.012), cornerWidth: radius * 0.84, cornerHeight: radius * 0.84, transform: nil))
    context.strokePath()

    let fontSize = unit * 0.31
    let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)!
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "VK", attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    let origin = CGPoint(
        x: (unit - bounds.width) / 2 - bounds.origin.x,
        y: (unit - bounds.height) / 2 - bounds.origin.y - unit * 0.015
    )

    let textPath = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        let runFont = attributes[kCTFontAttributeName] as! CTFont
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for index in 0..<count {
            guard let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
            textPath.addPath(glyphPath, transform: CGAffineTransform(
                translationX: origin.x + positions[index].x,
                y: origin.y + positions[index].y
            ))
        }
    }
    context.setFillColor(color(0.95, 0.98, 1))
    context.addPath(textPath)
    context.fillPath()

    return context.makeImage()!
}

for (filename, size) in iconSizes {
    let url = outputDirectory.appendingPathComponent(filename)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("cannot create PNG destination: \(url.path)")
    }
    CGImageDestinationAddImage(destination, iconImage(size: size), nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("cannot write PNG: \(url.path)")
    }
}
