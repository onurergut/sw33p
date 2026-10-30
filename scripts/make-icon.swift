import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/icon.png")
let iconset = URL(fileURLWithPath: "/tmp/sw33p.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(size: Int) -> Data {
    // Render into an explicit bitmap so Retina backing scale cannot turn a
    // 16 px icon into 32 px and corrupt the iconset's size mapping.
    guard let rep = NSBitmapImageRep(
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
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create a \(size)x\(size) bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024

    let background = NSBezierPath(
        roundedRect: NSRect(x: 64 * scale, y: 64 * scale, width: 896 * scale, height: 896 * scale),
        xRadius: 210 * scale,
        yRadius: 210 * scale
    )
    NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1).setFill()
    background.fill()

    let accent = NSColor(calibratedRed: 0.45, green: 0.92, blue: 0.72, alpha: 1)
    accent.setStroke()
    for index in 0..<3 {
        let path = NSBezierPath()
        let y = (620 - CGFloat(index) * 150) * scale
        path.move(to: NSPoint(x: 250 * scale, y: y))
        path.line(to: NSPoint(x: 774 * scale, y: y))
        path.lineWidth = 22 * scale
        path.lineCapStyle = .round
        path.stroke()
    }

    let sparkle = NSBezierPath()
    let center = NSPoint(x: 660 * scale, y: 300 * scale)
    sparkle.move(to: NSPoint(x: center.x, y: center.y + 70 * scale))
    sparkle.line(to: NSPoint(x: center.x + 24 * scale, y: center.y))
    sparkle.line(to: NSPoint(x: center.x, y: center.y - 70 * scale))
    sparkle.line(to: NSPoint(x: center.x - 24 * scale, y: center.y))
    sparkle.close()
    NSColor.white.setFill()
    sparkle.fill()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode a \(size)x\(size) PNG")
    }
    return data
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in sizes {
    try draw(size: size).write(to: iconset.appendingPathComponent(name))
}
try draw(size: 1024).write(to: outputDirectory)
