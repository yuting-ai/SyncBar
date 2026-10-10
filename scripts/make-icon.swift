// Draws SyncDock's app icon: an external drive with a checkmark badge, matching the menu bar symbol.
// Usage: swift scripts/make-icon.swift <output.png> [size]
import AppKit

let args = CommandLine.arguments
let output = URL(filePath: args[1])
let size = args.count > 2 ? CGFloat(Double(args[2])!) : 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Draw in a 1024-point design space.
ctx.scaleBy(x: size / 1024, y: size / 1024)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// macOS icon grid: 824-point body inset 100 points, with a soft shadow below.
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0x000000, 0.28)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 24
shadow.set()
rgb(0x2563EB).setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()
let background = NSGradient(starting: rgb(0x4F8DF7), ending: rgb(0x1D4ED8))!
background.draw(in: body, angle: -90)

// Drive: a rounded slab with a seam and two status lights.
// The drive and badge together are centred on the canvas.
let drive = NSRect(x: 255, y: 489, width: 600, height: 300)
NSGraphicsContext.saveGraphicsState()
let driveShadow = NSShadow()
driveShadow.shadowColor = rgb(0x0B2A6B, 0.35)
driveShadow.shadowOffset = NSSize(width: 0, height: -10)
driveShadow.shadowBlurRadius = 20
driveShadow.set()
NSColor.white.setFill()
NSBezierPath(roundedRect: drive, xRadius: 78, yRadius: 78).fill()
NSGraphicsContext.restoreGraphicsState()

let seam = NSBezierPath()
seam.move(to: NSPoint(x: drive.minX + 70, y: drive.minY + 118))
seam.line(to: NSPoint(x: drive.maxX - 70, y: drive.minY + 118))
seam.lineWidth = 12
seam.lineCapStyle = .round
rgb(0xC9D7F5).setStroke()
seam.stroke()
for (i, x) in [drive.maxX - 92, drive.maxX - 152].enumerated() {
    (i == 0 ? rgb(0x22C55E) : rgb(0x93B4F0)).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 19, y: drive.minY + 50, width: 38, height: 38)).fill()
}

// Badge: green disc with a checkmark, overlapping the drive's lower left like the SF Symbol.
let center = NSPoint(x: 353, y: 419)
let radius: CGFloat = 158
// A gap around the badge, painted with the background gradient so it reads as a cut-out.
NSGraphicsContext.saveGraphicsState()
NSBezierPath(ovalIn: NSRect(x: center.x - radius - 26, y: center.y - radius - 26,
                            width: 2 * (radius + 26), height: 2 * (radius + 26))).addClip()
background.draw(in: body, angle: -90)
NSGraphicsContext.restoreGraphicsState()
let disc = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
NSGradient(starting: rgb(0x4ADE80), ending: rgb(0x16A34A))!.draw(in: disc, angle: -90)

let check = NSBezierPath()
check.move(to: NSPoint(x: center.x - 72, y: center.y + 4))
check.line(to: NSPoint(x: center.x - 20, y: center.y - 50))
check.line(to: NSPoint(x: center.x + 78, y: center.y + 62))
check.lineWidth = 46
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: output)
