// Renders App/AppIcon.icns. Run: swift Tools/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return img }

    // macOS icon grid: the squircle occupies ~82% of the canvas.
    let inset = size * 0.09
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.15, alpha: 1).setFill()
    path.fill()
    ctx.restoreGState()

    // Gradient fill
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.25, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.12, alpha: 1),
        NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.10, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -70)

    // Subtle top highlight
    let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
    highlight.draw(in: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: 90)

    // Bell symbol
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.50, weight: .bold)
    if let bell = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: bell.size, flipped: false) { r in
            bell.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let s = tinted.size
        let origin = CGPoint(x: (size - s.width) / 2, y: (size - s.height) / 2 + size * 0.01)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.02,
                      color: NSColor.black.withAlphaComponent(0.25).cgColor)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        ctx.restoreGState()
    }

    // Check badge (bottom-right)
    let badgeD = size * 0.30
    let badgeRect = CGRect(x: rect.maxX - badgeD * 0.95, y: rect.minY - badgeD * 0.05, width: badgeD, height: badgeD)
    ctx.saveGState()
    ctx.resetClip()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.02,
                  color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1).setFill()
    NSBezierPath(ovalIn: badgeRect).fill()
    ctx.restoreGState()
    NSColor.white.withAlphaComponent(0.9).setStroke()
    let ring = NSBezierPath(ovalIn: badgeRect.insetBy(dx: size * 0.006, dy: size * 0.006))
    ring.lineWidth = size * 0.012
    ring.stroke()
    let checkCfg = NSImage.SymbolConfiguration(pointSize: badgeD * 0.55, weight: .heavy)
    if let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(checkCfg) {
        let tinted = NSImage(size: check.size, flipped: false) { r in
            check.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
        }
        let s = tinted.size
        tinted.draw(at: CGPoint(x: badgeRect.midX - s.width / 2, y: badgeRect.midY - s.height / 2),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }

    img.unlockFocus()
    return img
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    render(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let cwd = FileManager.default.currentDirectoryPath
let iconset = "\(cwd)/App/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(render(size: 1024), pixels: base).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base).png"))
    try! png(render(size: 1024), pixels: base * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
}
print("wrote \(iconset)")
