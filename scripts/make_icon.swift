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
let grad = CGGradient(colorsSpace: space, colors: [NSColor(red: 0.07, green: 0.09, blue: 0.25, alpha: 1).cgColor,
                                                    NSColor(red: 0.45, green: 0.2, blue: 0.85, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
func panel(_ r: CGRect, _ alpha: CGFloat) {
    let p = NSBezierPath(roundedRect: r, xRadius: 36, yRadius: 36)
    NSColor(white: 1, alpha: alpha * 0.18).setFill(); p.fill()
    NSColor(white: 1, alpha: alpha).setStroke(); p.lineWidth = 16; p.stroke()
    let bar = NSBezierPath(roundedRect: CGRect(x: r.minX + 40, y: r.maxY - 70, width: r.width * 0.35, height: 16), xRadius: 8, yRadius: 8)
    NSColor(white: 1, alpha: alpha * 0.8).setFill(); bar.fill()
}
panel(CGRect(x: 90, y: 360, width: 460, height: 330), 0.65)
panel(CGRect(x: 474, y: 330, width: 460, height: 330), 0.65)
panel(CGRect(x: 232, y: 250, width: 560, height: 400), 1.0)
// small "lens" dots under the front panel
for x in [412, 612] as [CGFloat] {
    NSColor.white.setFill(); NSBezierPath(ovalIn: CGRect(x: x - 34, y: 150, width: 68, height: 68)).fill()
}
NSGraphicsContext.restoreGraphicsState()
let rep = rep0
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
