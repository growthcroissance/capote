import AppKit
import Foundation

let canvasWidth = 660
let canvasHeight = 530
let canvasSize = NSSize(width: canvasWidth, height: canvasHeight)
let scriptURL = URL(fileURLWithPath: #filePath)
let projectURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let logoURL = projectURL.appendingPathComponent("docs/assets/growth-croissance.png")
let defaultOutputURL = projectURL.appendingPathComponent("packaging/dmg/background.png")
let outputURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : defaultOutputURL

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasWidth,
    pixelsHigh: canvasHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Impossible de créer le fond du DMG")
}

func centeredText(_ text: String, baselineY: CGFloat, attributes: [NSAttributedString.Key: Any]) {
    let size = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: (canvasSize.width - size.width) / 2, y: baselineY),
        withAttributes: attributes
    )
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let canvasRect = NSRect(origin: .zero, size: canvasSize)
let paper = NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.97, alpha: 1.0)
let warmPaper = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.93, alpha: 1.0)
NSGradient(starting: paper, ending: warmPaper)?.draw(in: canvasRect, angle: -45)

let coral = NSColor(calibratedRed: 0.96, green: 0.30, blue: 0.22, alpha: 1.0)
coral.withAlphaComponent(0.045).setFill()
NSBezierPath(ovalIn: NSRect(x: 445, y: 375, width: 350, height: 350)).fill()
coral.withAlphaComponent(0.035).setFill()
NSBezierPath(ovalIn: NSRect(x: -118, y: -52, width: 300, height: 300)).fill()

if let logo = NSImage(contentsOf: logoURL) {
    logo.draw(
        in: NSRect(x: 230, y: 432, width: 200, height: 80),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
} else {
    fatalError("Logo GROWTH Croissance introuvable")
}

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedRed: 0.49, green: 0.15, blue: 0.10, alpha: 0.13)
shadow.shadowBlurRadius = 12
shadow.shadowOffset = NSSize(width: 0, height: -8)

for centerX in [165.0, 495.0] {
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: centerX - 70, y: 266, width: 140, height: 140)).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(calibratedRed: 0.92, green: 0.87, blue: 0.85, alpha: 1.0).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: centerX - 70, y: 266, width: 140, height: 140))
    ring.lineWidth = 1
    ring.stroke()
}

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 257, y: 336))
arrow.line(to: NSPoint(x: 405, y: 336))
arrow.lineWidth = 8
arrow.lineCapStyle = .round
coral.setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 387, y: 356))
arrowHead.line(to: NSPoint(x: 413, y: 336))
arrowHead.line(to: NSPoint(x: 387, y: 316))
arrowHead.lineWidth = 8
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.stroke()

let ink = NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.09, alpha: 1.0)
let muted = NSColor(calibratedRed: 0.40, green: 0.37, blue: 0.36, alpha: 1.0)
centeredText(
    "Glissez Capote dans Applications",
    baselineY: 214,
    attributes: [
        .font: NSFont.systemFont(ofSize: 21, weight: .bold),
        .foregroundColor: ink
    ]
)
centeredText(
    "macOS 14 ou ultérieur · Apple Silicon et Intel",
    baselineY: 188,
    attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: muted
    ]
)
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Impossible d’encoder le fond du DMG")
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL, options: .atomic)
print("Fond du DMG créé : \(outputURL.path)")
