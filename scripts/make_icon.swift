import AppKit
// Usage: swift make_icon.swift out.png  — renders a 1024x1024 DesktopAR icon.
let S: CGFloat = 1024
let mac = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "mac"
let rep0 = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep0)
let ctx = NSGraphicsContext.current!.cgContext
let inset: CGFloat = mac ? 100 : 0
let bg = CGPath(roundedRect: CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset), cornerWidth: mac ? 185 : 0, cornerHeight: mac ? 185 : 0, transform: nil)
ctx.addPath(bg); ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
let green = NSColor(red: 0.2, green: 1.0, blue: 0.55, alpha: 1)
let grad = CGGradient(colorsSpace: space, colors: [NSColor(red: 0.30, green: 0.33, blue: 0.35, alpha: 1).cgColor,
                                                    NSColor(red: 0.06, green: 0.08, blue: 0.09, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
// green perspective grid floor
green.withAlphaComponent(0.25).setStroke()
for i in 0...12 {
    let l = NSBezierPath(); l.lineWidth = 3
    l.move(to: CGPoint(x: S / 2 + CGFloat(i - 6) * 20, y: 520)); l.line(to: CGPoint(x: S / 2 + CGFloat(i - 6) * 150, y: 0)); l.stroke()
}
for j in 0..<7 {
    let y = 520 - pow(CGFloat(j) / 6, 1.8) * 520
    let l = NSBezierPath(); l.lineWidth = 3; l.move(to: CGPoint(x: 0, y: y)); l.line(to: CGPoint(x: S, y: y)); l.stroke()
}
func panel(_ r: CGRect, _ a: CGFloat) {
    let p = NSBezierPath(roundedRect: r, xRadius: 40, yRadius: 40)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: green.withAlphaComponent(0.6 * a).cgColor)
    NSColor(white: 1, alpha: 0.10 * a).setFill(); p.fill()
    ctx.restoreGState()
    // glass sheen
    ctx.saveGState(); p.addClip()
    let sheen = CGGradient(colorsSpace: space, colors: [NSColor(white: 1, alpha: 0.35 * a).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: r.minX, y: r.maxY), end: CGPoint(x: r.midX, y: r.midY - 40), options: [])
    // green dot pattern
    green.withAlphaComponent(0.35 * a).setFill()
    var y = r.minY + 40
    while y < r.maxY - 40 { var x = r.minX + 40; while x < r.maxX - 40 { NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 7, height: 7)).fill(); x += 36 }; y += 36 }
    ctx.restoreGState()
    green.withAlphaComponent(a).setStroke(); p.lineWidth = 10; p.stroke()
    let bar = NSBezierPath(roundedRect: CGRect(x: r.minX + 40, y: r.maxY - 64, width: r.width * 0.3, height: 14), xRadius: 7, yRadius: 7)
    green.withAlphaComponent(a).setFill(); bar.fill()
}
panel(CGRect(x: 150, y: 430, width: 330, height: 240), 0.55)
panel(CGRect(x: 544, y: 430, width: 330, height: 240), 0.55)
panel(CGRect(x: 262, y: 330, width: 500, height: 340), 1.0)
NSGraphicsContext.restoreGraphicsState()
let rep = rep0
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
