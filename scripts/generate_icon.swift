import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_icon.swift OUTPUT.png\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create icon bitmap\n", stderr)
    exit(1)
}

bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor.clear.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let tileRect = NSRect(x: 62, y: 62, width: 900, height: 900)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)
tile.addClip()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.49, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.40, green: 0.25, blue: 0.90, alpha: 1)
])!
gradient.draw(in: tileRect, angle: -45)

func drawPage(rect: NSRect, alpha: CGFloat) {
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 46, yRadius: 46).fill()
}

drawPage(rect: NSRect(x: 250, y: 250, width: 530, height: 430), alpha: 0.34)
drawPage(rect: NSRect(x: 210, y: 305, width: 530, height: 430), alpha: 0.62)
drawPage(rect: NSRect(x: 170, y: 360, width: 530, height: 430), alpha: 0.96)

let lineColor = NSColor(
    calibratedRed: 0.23,
    green: 0.40,
    blue: 0.89,
    alpha: 0.72
)
lineColor.setFill()
NSBezierPath(
    roundedRect: NSRect(x: 242, y: 662, width: 300, height: 36),
    xRadius: 18,
    yRadius: 18
).fill()
NSBezierPath(
    roundedRect: NSRect(x: 242, y: 590, width: 220, height: 24),
    xRadius: 12,
    yRadius: 12
).fill()
NSBezierPath(
    roundedRect: NSRect(x: 242, y: 535, width: 330, height: 24),
    xRadius: 12,
    yRadius: 12
).fill()

let playCircleRect = NSRect(x: 540, y: 170, width: 280, height: 280)
NSColor(
    calibratedRed: 0.08,
    green: 0.16,
    blue: 0.39,
    alpha: 0.92
).setFill()
NSBezierPath(ovalIn: playCircleRect).fill()

let play = NSBezierPath()
play.move(to: NSPoint(x: 646, y: 245))
play.line(to: NSPoint(x: 646, y: 375))
play.line(to: NSPoint(x: 756, y: 310))
play.close()
NSColor.white.setFill()
play.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode icon PNG\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
