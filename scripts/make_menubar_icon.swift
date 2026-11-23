import AppKit
// Usage: swift make_menubar_icon.swift outDir — template menu bar icon: a screen with speed lines behind it.
func render(scale: Int, to path: String) {
    let w = 22 * scale, h = 18 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(scale)
    NSColor.black.setStroke(); NSColor.black.setFill()
    // speed lines (left of screen, fading length)
    let lines: [(y: CGFloat, x0: CGFloat, x1: CGFloat)] = [(13, 1.5, 8), (9, 0.5, 8), (5, 2.5, 8)]
    for l in lines {
        let p = NSBezierPath(); p.lineWidth = 1.6 * s; p.lineCapStyle = .round
        p.move(to: CGPoint(x: l.x0 * s, y: l.y * s)); p.line(to: CGPoint(x: l.x1 * s, y: l.y * s)); p.stroke()
    }
    // screen (slightly skewed forward, like it's moving right)
    let scr = NSBezierPath()
    scr.lineWidth = 1.8 * s; scr.lineJoinStyle = .round
    scr.move(to: CGPoint(x: 11 * s, y: 3 * s)); scr.line(to: CGPoint(x: 20.5 * s, y: 3 * s))
    scr.line(to: CGPoint(x: 20.5 * s, y: 15 * s)); scr.line(to: CGPoint(x: 11 * s, y: 15 * s)); scr.close()
    scr.stroke()
    // inner glint
    let g = NSBezierPath(rect: CGRect(x: 13.3 * s, y: 11 * s, width: 5 * s, height: 1.4 * s)); g.fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
let dir = CommandLine.arguments[1]
render(scale: 1, to: dir + "/menubar.png"); render(scale: 2, to: dir + "/menubar@2x.png"); render(scale: 3, to: dir + "/menubar@3x.png")
