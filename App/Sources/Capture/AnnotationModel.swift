import AppKit
import CoreGraphics

enum AnnotationTool { case box, arrow, text }

struct AnnotationShape: Identifiable {
    let id: UUID
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var label: String
}

enum AnnotationRenderer {
    static func flatten(image: CGImage, shapes: [AnnotationShape],
                        viewSize: CGSize) -> Data? {
        let width = image.width, height = image.height
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let sx = CGFloat(width) / viewSize.width
        let sy = CGFloat(height) / viewSize.height
        // View coords are top-left origin; CGContext is bottom-left. Flip y.
        func pt(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * sx, y: CGFloat(height) - p.y * sy)
        }

        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(3 * sx)
        for shape in shapes {
            let a = pt(shape.start), b = pt(shape.end)
            switch shape.tool {
            case .box:
                ctx.stroke(CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                  width: abs(a.x - b.x), height: abs(a.y - b.y)))
            case .arrow:
                ctx.move(to: a); ctx.addLine(to: b)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let headLen = 14 * sx
                for offset in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                    ctx.move(to: b)
                    ctx.addLine(to: CGPoint(x: b.x + headLen * cos(angle + offset),
                                            y: b.y + headLen * sin(angle + offset)))
                }
                ctx.strokePath()
            case .text:
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 16 * sx),
                    .foregroundColor: NSColor.systemRed,
                ]
                let str = NSAttributedString(string: shape.label, attributes: attrs)
                let line = CTLineCreateWithAttributedString(str)
                ctx.textPosition = a
                CTLineDraw(line, ctx)
            }
        }
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}
