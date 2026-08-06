// Generates AppIcon-1024.png. Run: swift App/IconGen/generate-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Squircle plate (standard macOS margin)
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
platePath.addClip()
NSGradient(starting: rgb(0x34353D), ending: rgb(0x17181C))!
    .draw(in: plate, angle: -90)

// Note sheet
let sheet = NSRect(x: 252, y: 240, width: 520, height: 560)
let sheetShadow = NSShadow()
sheetShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
sheetShadow.shadowBlurRadius = 30
sheetShadow.shadowOffset = NSSize(width: 0, height: -12)
ctx.saveGState()
sheetShadow.set()
rgb(0xF7F6F3).setFill()
NSBezierPath(roundedRect: sheet, xRadius: 44, yRadius: 44).fill()
ctx.restoreGState()

// Category chip (purple capsule, top-left of sheet)
rgb(0x9C5BF5).setFill()
NSBezierPath(roundedRect: NSRect(x: 300, y: 706, width: 172, height: 56),
             xRadius: 28, yRadius: 28).fill()

// Text lines
rgb(0xC8C7CD).setFill()
for (i, w) in [CGFloat(376), 420].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: 300, y: 622 - CGFloat(i) * 76, width: w, height: 32),
                 xRadius: 16, yRadius: 16).fill()
}

// Capture brackets (red, region inside the sheet, lower-right)
let red = rgb(0xFF5148)
red.setStroke()
let bx = NSRect(x: 300, y: 292, width: 424, height: 164)
let arm: CGFloat = 58
let bw: CGFloat = 24
for (cx, cy, dx, dy) in [(bx.minX, bx.minY, 1.0, 1.0), (bx.maxX, bx.minY, -1.0, 1.0),
                         (bx.minX, bx.maxY, 1.0, -1.0), (bx.maxX, bx.maxY, -1.0, -1.0)] {
    let p = NSBezierPath()
    p.lineWidth = bw
    p.lineCapStyle = .round
    p.move(to: NSPoint(x: cx + CGFloat(dx) * arm, y: cy))
    p.line(to: NSPoint(x: cx, y: cy))
    p.line(to: NSPoint(x: cx, y: cy + CGFloat(dy) * arm))
    p.stroke()
}

// Captured content inside the brackets
rgb(0xC8C7CD).setFill()
NSBezierPath(roundedRect: NSRect(x: 356, y: 358, width: 268, height: 32),
             xRadius: 16, yRadius: 16).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode failed") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
