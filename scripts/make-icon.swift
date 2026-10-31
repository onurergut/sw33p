import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/icon.png")
let iconset = URL(fileURLWithPath: "/tmp/sw33p.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient {
    guard let value = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: colors as CFArray,
        locations: locations
    ) else {
        fatalError("Could not create icon gradient")
    }
    return value
}

func fill(_ path: CGPath, in context: CGContext, colors: [CGColor],
          locations: [CGFloat], from start: CGPoint, to end: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        gradient(colors, locations: locations),
        start: start,
        end: end,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()
}

func draw(size: Int) -> Data {
    // Explicit pixels keep every iconset representation independent of Retina scale.
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
    ), let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create a \(size)x\(size) bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    let scale = CGFloat(size) / 256
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: 256)
    context.scaleBy(x: 1, y: -1)

    let background = CGPath(
        roundedRect: CGRect(x: 17, y: 17, width: 222, height: 222),
        cornerWidth: 51, cornerHeight: 51, transform: nil
    )
    fill(background, in: context,
         colors: [color(0x174e5c), color(0x103d4d), color(0x092d3d)],
         locations: [0, 0.55, 1],
         from: CGPoint(x: 28, y: 17), to: CGPoint(x: 217, y: 239))

    context.saveGState()
    context.addPath(background)
    context.clip()
    context.drawRadialGradient(
        gradient([color(0x6ee8c7, alpha: 0.30), color(0x6ee8c7, alpha: 0)],
                 locations: [0, 1]),
        startCenter: CGPoint(x: 66, y: 35), startRadius: 0,
        endCenter: CGPoint(x: 66, y: 35), endRadius: 200,
        options: [.drawsAfterEndLocation]
    )
    context.restoreGState()

    let rim = CGPath(
        roundedRect: CGRect(x: 17.6, y: 17.6, width: 220.8, height: 220.8),
        cornerWidth: 50.4, cornerHeight: 50.4, transform: nil
    )
    context.addPath(rim)
    context.setStrokeColor(color(0xd4fff3, alpha: 0.16))
    context.setLineWidth(1.2)
    context.strokePath()

    let sweep = CGMutablePath()
    sweep.move(to: CGPoint(x: 48, y: 197))
    sweep.addCurve(to: CGPoint(x: 163, y: 202),
                   control1: CGPoint(x: 75, y: 210),
                   control2: CGPoint(x: 122, y: 214))
    context.addPath(sweep)
    context.setStrokeColor(color(0x52d1b0, alpha: 0.18))
    context.setLineWidth(4)
    context.setLineCap(.round)
    context.strokePath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: scale, height: -8 * scale),
                      blur: 5 * scale, color: color(0x041e29, alpha: 0.42))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.translateBy(x: 128, y: 131)
    context.rotate(by: 37 * .pi / 180)

    let handle = CGPath(
        roundedRect: CGRect(x: -9, y: -87, width: 18, height: 98),
        cornerWidth: 9, cornerHeight: 9, transform: nil
    )
    fill(handle, in: context,
         colors: [color(0xb8ffe0), color(0x75edc4), color(0x2dc797)],
         locations: [0, 0.45, 1],
         from: CGPoint(x: -9, y: -87), to: CGPoint(x: 9, y: -58))
    context.move(to: CGPoint(x: -4, y: -75))
    context.addLine(to: CGPoint(x: -4, y: -17))
    context.setStrokeColor(color(0xe6fff1, alpha: 0.65))
    context.setLineWidth(2.4)
    context.strokePath()

    let bristles = CGMutablePath()
    bristles.move(to: CGPoint(x: -24, y: 8))
    bristles.addLine(to: CGPoint(x: -37, y: 62))
    bristles.addQuadCurve(to: CGPoint(x: 37, y: 62), control: CGPoint(x: 0, y: 79))
    bristles.addLine(to: CGPoint(x: 24, y: 8))
    bristles.closeSubpath()
    fill(bristles, in: context,
         colors: [color(0xffffee), color(0xe5f3da), color(0x92c9b8)],
         locations: [0, 0.5, 1],
         from: CGPoint(x: -37, y: 8), to: CGPoint(x: 37, y: 65))

    let bristleLines: [(CGPoint, CGPoint)] = [
        (CGPoint(x: -21, y: 25), CGPoint(x: -28, y: 59)),
        (CGPoint(x: -10, y: 27), CGPoint(x: -13, y: 65)),
        (CGPoint(x: 1, y: 27), CGPoint(x: 1, y: 67)),
        (CGPoint(x: 12, y: 25), CGPoint(x: 16, y: 62)),
        (CGPoint(x: 23, y: 23), CGPoint(x: 30, y: 56)),
    ]
    context.setStrokeColor(color(0x448c7c, alpha: 0.30))
    context.setLineWidth(2.8)
    for (start, end) in bristleLines {
        context.move(to: start)
        context.addLine(to: end)
    }
    context.strokePath()

    let band = CGMutablePath()
    band.move(to: CGPoint(x: -24, y: 7))
    band.addQuadCurve(to: CGPoint(x: 24, y: 7), control: CGPoint(x: 0, y: -1))
    band.addLine(to: CGPoint(x: 27, y: 24))
    band.addQuadCurve(to: CGPoint(x: -27, y: 24), control: CGPoint(x: 0, y: 34))
    band.closeSubpath()
    fill(band, in: context,
         colors: [color(0x6de2bc), color(0x40bd99), color(0x1b846e)],
         locations: [0, 0.5, 1],
         from: CGPoint(x: -27, y: 15), to: CGPoint(x: 27, y: 15))
    context.move(to: CGPoint(x: -21, y: 8))
    context.addQuadCurve(to: CGPoint(x: 19, y: 8), control: CGPoint(x: -1, y: 3))
    context.setStrokeColor(color(0xc1ffdd, alpha: 0.70))
    context.setLineWidth(1.8)
    context.strokePath()

    context.endTransparencyLayer()
    context.restoreGState()

    context.setFillColor(color(0xa4f6d4, alpha: 0.90))
    context.fillEllipse(in: CGRect(x: 67, y: 73, width: 8, height: 8))
    context.setFillColor(color(0xa4f6d4, alpha: 0.45))
    context.fillEllipse(in: CGRect(x: 60, y: 97, width: 4, height: 4))

    graphics.flushGraphics()
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
