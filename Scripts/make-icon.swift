// Draws the SimpleVector app icon and writes Resources/AppIcon.icns. Usage: swift Scripts/make-icon.swift
import AppKit

func color(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func drawIcon(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824 pt rounded square centred in 1024
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: color(0x000000, 0.48))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x14171C))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [color(0x222731), color(0x0E1014)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

    // Subtle background vector grid
    ctx.setStrokeColor(color(0xFFFFFF, 0.04))
    ctx.setLineWidth(4)
    for g in stride(from: 220.0, through: 820.0, by: 120.0) {
        ctx.move(to: CGPoint(x: g, y: 120))
        ctx.addLine(to: CGPoint(x: g, y: 904))
        ctx.move(to: CGPoint(x: 120, y: g))
        ctx.addLine(to: CGPoint(x: 904, y: g))
    }
    ctx.strokePath()

    // Back page (multipage stack)
    let backPageRect = CGRect(x: 330, y: 240, width: 430, height: 550)
    let backPagePath = CGPath(roundedRect: backPageRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.saveGState()
    ctx.addPath(backPagePath)
    ctx.setFillColor(color(0x1B2029))
    ctx.fillPath()
    ctx.addPath(backPagePath)
    ctx.setStrokeColor(color(0x5CE1E6, 0.48))
    ctx.setLineWidth(8)
    ctx.strokePath()
    ctx.restoreGState()

    // Front page (PDF/SVG sheet)
    let frontPageRect = CGRect(x: 240, y: 190, width: 450, height: 570)
    let frontPagePath = CGPath(roundedRect: frontPageRect, cornerWidth: 38, cornerHeight: 38, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: color(0x000000, 0.55))
    ctx.addPath(frontPagePath)
    ctx.setFillColor(color(0x181C24))
    ctx.fillPath()
    ctx.addPath(frontPagePath)
    ctx.setStrokeColor(color(0xFFB454, 0.85))
    ctx.setLineWidth(10)
    ctx.strokePath()
    ctx.restoreGState()

    // Editable PDF text lines at the top of the front page
    for (idx, w) in [240.0, 310.0, 200.0].enumerated() {
        let y = 660.0 - Double(idx) * 44.0
        let bar = CGRect(x: 296, y: y, width: w, height: 18)
        let barPath = CGPath(roundedRect: bar, cornerWidth: 9, cornerHeight: 9, transform: nil)
        ctx.addPath(barPath)
        ctx.setFillColor(idx == 0 ? color(0x5CE1E6, 0.90) : color(0x8A919E, 0.55))
        ctx.fillPath()
    }

    // Luminous Bezier curve & signature flourish across the page
    let p0 = CGPoint(x: 286, y: 280)
    let p1 = CGPoint(x: 644, y: 470)
    let c1 = CGPoint(x: 340, y: 540)
    let c2 = CGPoint(x: 570, y: 220)

    // Cyan tangent control lines
    ctx.saveGState()
    ctx.setStrokeColor(color(0x5CE1E6, 0.85))
    ctx.setLineWidth(7)
    ctx.setLineDash(phase: 0, lengths: [14, 10])
    ctx.move(to: p0)
    ctx.addLine(to: c1)
    ctx.move(to: p1)
    ctx.addLine(to: c2)
    ctx.strokePath()
    ctx.restoreGState()

    // Amber Bezier curve
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 22 * s, color: color(0xFFB454, 0.85))
    ctx.setStrokeColor(color(0xFFB454))
    ctx.setLineWidth(18)
    ctx.setLineCap(.round)
    ctx.move(to: p0)
    ctx.addCurve(to: p1, control1: c1, control2: c2)
    ctx.strokePath()
    ctx.restoreGState()

    // Control handle nodes
    for pt in [c1, c2] {
        ctx.setFillColor(color(0x5CE1E6))
        ctx.fillEllipse(in: CGRect(x: pt.x - 14, y: pt.y - 14, width: 28, height: 28))
    }
    for pt in [p0, p1] {
        ctx.setFillColor(color(0x9ECE6A))
        ctx.fill(CGRect(x: pt.x - 15, y: pt.y - 15, width: 30, height: 30))
    }

    ctx.restoreGState()
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = fm.temporaryDirectory.appendingPathComponent("SimpleVector-\(UUID().uuidString).iconset")
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try! fm.createDirectory(at: resources, withIntermediateDirectories: true)
for (name, size) in [
    ("16x16", 16), ("16x16@2x", 32),
    ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256),
    ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
] {
    try! drawIcon(size: size).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try! drawIcon(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote \(resources.path)/AppIcon.icns" : "iconutil failed")
exit(task.terminationStatus)
