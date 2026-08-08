// Generates AppIcon-1024.png for MeetingNotes.
// Concept E: white note card with two text lines and a bold green check,
// floating on a violet gradient plate. Run:
//   swift App/IconGen/generate-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
func clipPlate() { NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185).addClip() }
func softShadow(_ alpha: CGFloat = 0.3, _ blur: CGFloat = 34, _ dy: CGFloat = -14) {
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(alpha)
    sh.shadowBlurRadius = blur; sh.shadowOffset = NSSize(width: 0, height: dy); sh.set()
}
func noShadow() { NSShadow().set() }

// ── E. C's clarity, bolder: violet plate, white note card, green check as a
//      big confident sweep across the card's lower half.
func drawIcon(_ ctx: CGContext) {
    clipPlate()
    NSGradient(colors: [rgb(0x6E4BF0), rgb(0x3D22B8)])!.draw(in: plate, angle: -80)

    let card = NSRect(x: 258, y: 258, width: 508, height: 508)
    softShadow(0.3, 40, -16)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: card, xRadius: 78, yRadius: 78).fill()
    noShadow()

    rgb(0xC3BFD6).setFill()
    for (i, w) in [CGFloat(300), 220].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 330, y: 638 - CGFloat(i) * 76, width: w, height: 28),
                     xRadius: 14, yRadius: 14).fill()
    }

    let check = NSBezierPath()
    check.lineWidth = 68; check.lineCapStyle = .round; check.lineJoinStyle = .round
    check.move(to: NSPoint(x: 348, y: 420))
    check.line(to: NSPoint(x: 452, y: 326))
    check.line(to: NSPoint(x: 690, y: 552))
    rgb(0x22C77E).setStroke()
    check.stroke()
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
drawIcon(NSGraphicsContext.current!.cgContext)
image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode failed") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
