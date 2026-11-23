// Renders each world theme from Shaders.metal to PNGs so shader changes can be checked on the Mac.
// usage: swift scripts/theme_preview.swift <outDir> [yawDegrees] [pitchDegrees]
import Metal
import simd
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/themes"
let yawDeg = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 0 : 0
let pitchDeg = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3]) ?? 0 : 0
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
guard let dev = MTLCreateSystemDefaultDevice() else { fatalError("no metal") }
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let src = try String(contentsOf: root.appendingPathComponent("PhoneClient/Sources/Render/Shaders.metal"))
let lib = try dev.makeLibrary(source: src, options: nil)
let d = MTLRenderPipelineDescriptor()
d.vertexFunction = lib.makeFunction(name: "quadVertex"); d.fragmentFunction = lib.makeFunction(name: "themeFragment")
d.colorAttachments[0].pixelFormat = .bgra8Unorm
let pso = try dev.makeRenderPipelineState(descriptor: d)
let q = dev.makeCommandQueue()!
let W = 640, H = 360
var sheet = [UInt8](repeating: 0, count: W * 4 * H * 2 * 4)
struct TP { var right: SIMD4<Float>; var up: SIMD4<Float>; var back: SIMD4<Float>; var tanY: Float; var aspect: Float; var time: Float; var theme: Int32 }
let yaw = Float(yawDeg * .pi / 180), pitch = Float(pitchDeg * .pi / 180)
// camera axes for yaw (turn left positive) then pitch
let fwd = SIMD3<Float>(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
let right0 = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
let up0 = simd_cross(-fwd, right0)
func norm(_ v: SIMD3<Float>) -> SIMD3<Float> { v / (v * v).sum().squareRoot() }
let back = -fwd
for theme in 1...8 {
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
    td.usage = [.renderTarget]; td.storageMode = .shared
    let tex = dev.makeTexture(descriptor: td)!
    let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
    let cb = q.makeCommandBuffer()!; let enc = cb.makeRenderCommandEncoder(descriptor: rp)!
    var tp = TP(right: SIMD4(norm(right0), 0), up: SIMD4(norm(up0), 0), back: SIMD4(back, 0), tanY: Float(tan(90.0 * .pi / 360)), aspect: Float(W) / Float(H), time: 3.0, theme: Int32(theme))
    var sc = SIMD2<Float>(1, 1)
    enc.setRenderPipelineState(pso); enc.setVertexBytes(&sc, length: 8, index: 0); enc.setFragmentBytes(&tp, length: MemoryLayout<TP>.size, index: 0)
    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4); enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    var px = [UInt8](repeating: 0, count: W * H * 4)
    tex.getBytes(&px, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0)
    let ox = ((theme - 1) % 4) * W, oy = ((theme - 1) / 4) * H
    for row in 0..<H { for col in 0..<(W * 4) { sheet[(oy + row) * (W * 4 * 4) + ox * 4 + col] = px[row * W * 4 + col] } }
}
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: &sheet, width: W * 4, height: H * 2, bitsPerComponent: 8, bytesPerRow: W * 16, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
let url = URL(fileURLWithPath: "\(out)/sheet.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
print("ok")
