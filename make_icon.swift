// Draws the app icon and writes it as a 1024px PNG. Usage: swift make_icon.swift out.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, alpha])!
}

// Rounded-square body with a soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(shape)
ctx.setFillColor(color(0x15161C))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let gradient = CGGradient(colorsSpace: space, colors: [color(0x34364A), color(0x0B0C10)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// Warm glow behind the line being read.
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFD60A, 0.22), color(0xFFD60A, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 626), startRadius: 0,
                       endCenter: CGPoint(x: 330, y: 626), endRadius: 420, options: [])

// Lines of script: one already read, the bright one being read, the rest fading out below.
let rows: [(y: CGFloat, width: CGFloat, alpha: CGFloat)] = [
    (708, 380, 0.26), (594, 524, 1), (480, 450, 0.58), (366, 524, 0.36), (252, 290, 0.18),
]
for row in rows {
    let bar = CGRect(x: 300, y: row.y, width: row.width, height: 64)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 32, cornerHeight: 32, transform: nil))
    ctx.setFillColor(color(0xFFFFFF, row.alpha))
    ctx.fillPath()
}

// Reading marker.
let marker = CGMutablePath()
marker.move(to: CGPoint(x: 204, y: 660))
marker.addLine(to: CGPoint(x: 204, y: 592))
marker.addLine(to: CGPoint(x: 262, y: 626))
marker.closeSubpath()
ctx.addPath(marker)
ctx.setFillColor(color(0xFFD60A))
ctx.setStrokeColor(color(0xFFD60A))
ctx.setLineWidth(14)
ctx.setLineJoin(.round)
ctx.drawPath(using: .fillStroke)
ctx.restoreGState()

// Thin rim light.
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(color(0xFFFFFF, 0.1))
ctx.setLineWidth(4)
ctx.strokePath()

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
