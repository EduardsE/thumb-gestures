// Draws the Thumb Gestures app icon and writes an .iconset folder.
// Usage: swift tools/make-icon.swift <output.iconset>

import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// A horizontal arrow from x0 (tail) to x1 (tip) on the line y, in a 1024 canvas.
func arrowPath(from x0: CGFloat, to x1: CGFloat, y: CGFloat) -> CGPath {
    let shaftH: CGFloat = 64, headH: CGFloat = 200, headW: CGFloat = 150
    let neck = x1 - (x1 > x0 ? headW : -headW)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x1, y: y))
    p.addLine(to: CGPoint(x: neck, y: y + headH / 2))
    p.addLine(to: CGPoint(x: neck, y: y + shaftH / 2))
    p.addLine(to: CGPoint(x: x0, y: y + shaftH / 2))
    p.addLine(to: CGPoint(x: x0, y: y - shaftH / 2))
    p.addLine(to: CGPoint(x: neck, y: y - shaftH / 2))
    p.addLine(to: CGPoint(x: neck, y: y - headH / 2))
    p.closeSubpath()
    return p
}

func fill(_ ctx: CGContext, _ path: CGPath, light: UInt32, dark: UInt32) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: nil, colors: [color(light), color(dark)] as CFArray, locations: [0, 1])!
    let box = path.boundingBox
    ctx.drawLinearGradient(g, start: CGPoint(x: box.midX, y: box.maxY),
                           end: CGPoint(x: box.midX, y: box.minY), options: [])
    ctx.restoreGState()
}

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // macOS icon grid: 824 pt body inside a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(color(0x1E1B2E)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [color(0x3A2F5C), color(0x16132A)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

    // Left and right arrows: the Space switch.
    fill(ctx, arrowPath(from: 410, to: 190, y: 512), light: 0x7FE3C8, dark: 0x3FB59A)
    fill(ctx, arrowPath(from: 614, to: 834, y: 512), light: 0x7FE3C8, dark: 0x3FB59A)

    // The thumb button in the center.
    let button = CGPath(ellipseIn: CGRect(x: 422, y: 422, width: 180, height: 180), transform: nil)
    fill(ctx, button, light: 0xFFB36B, dark: 0xF0784A)

    // Soft top highlight.
    let shine = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 640), options: [])
    ctx.restoreGState()

    ctx.addPath(shape); ctx.setStrokeColor(color(0xFFFFFF, 0.10)); ctx.setLineWidth(3); ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(size: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(size: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
