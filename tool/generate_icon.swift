import AppKit

let size = 1024
let destination = CommandLine.arguments[1]
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create icon canvas")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let background = NSBezierPath(
    roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976),
    xRadius: 222,
    yRadius: 222
)
NSColor(srgbRed: 0.05, green: 0.36, blue: 0.42, alpha: 1).setFill()
background.fill()

let inner = NSBezierPath(
    roundedRect: NSRect(x: 97, y: 97, width: 830, height: 830),
    xRadius: 169,
    yRadius: 169
)
inner.lineWidth = 18
NSColor(srgbRed: 0.75, green: 0.94, blue: 0.91, alpha: 0.31).setStroke()
inner.stroke()

let title = "MR" as NSString
let style = NSMutableParagraphStyle()
style.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 410, weight: .heavy),
    .foregroundColor: NSColor.white,
    .paragraphStyle: style,
    .kern: -12,
]
title.draw(in: NSRect(x: 93, y: 264, width: 838, height: 480), withAttributes: attributes)

let recordDot = NSBezierPath(ovalIn: NSRect(x: 757, y: 757, width: 122, height: 122))
NSColor(srgbRed: 1.00, green: 0.42, blue: 0.34, alpha: 1).setFill()
recordDot.fill()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon")
}
try png.write(to: URL(fileURLWithPath: destination))
