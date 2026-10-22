import AppKit

/// Shared vector master for the edge tab, menu bar, editor and packaged app icon.
enum PaperIdentity {
    static let paper = NSColor(srgbRed: 0.985, green: 0.977, blue: 0.955, alpha: 1)
    static let sidebar = NSColor(srgbRed: 0.94, green: 0.925, blue: 0.89, alpha: 1)
    static let selected = NSColor(srgbRed: 0.88, green: 0.84, blue: 0.76, alpha: 1)
    static let muted = NSColor(srgbRed: 0.57, green: 0.55, blue: 0.50, alpha: 1)
    static let rule = NSColor(srgbRed: 0.88, green: 0.86, blue: 0.81, alpha: 1)
    static let ink = NSColor(srgbRed: 0.24, green: 0.24, blue: 0.23, alpha: 1)
    static let accent = NSColor(srgbRed: 0.79, green: 0.57, blue: 0.26, alpha: 1)

    static func drawMark(in rect: NSRect, monochrome: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 32, yBy: rect.height / 32)
        transform.concat()
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: 18, y: 3))
        outline.line(to: NSPoint(x: 10, y: 3))
        outline.curve(to: NSPoint(x: 3, y: 10), controlPoint1: NSPoint(x: 5, y: 3), controlPoint2: NSPoint(x: 3, y: 5))
        outline.line(to: NSPoint(x: 3, y: 22))
        outline.curve(to: NSPoint(x: 10, y: 29), controlPoint1: NSPoint(x: 3, y: 27), controlPoint2: NSPoint(x: 5, y: 29))
        outline.line(to: NSPoint(x: 22, y: 29))
        outline.curve(to: NSPoint(x: 29, y: 22), controlPoint1: NSPoint(x: 27, y: 29), controlPoint2: NSPoint(x: 29, y: 27))
        outline.line(to: NSPoint(x: 29, y: 14))
        outline.lineWidth = 2.6; outline.lineCapStyle = .round; outline.lineJoinStyle = .round
        (monochrome ? NSColor.black : ink).setStroke(); outline.stroke()
        let stroke = NSBezierPath()
        stroke.move(to: NSPoint(x: 10, y: 14))
        stroke.curve(to: NSPoint(x: 21, y: 21), controlPoint1: NSPoint(x: 14, y: 15), controlPoint2: NSPoint(x: 18, y: 17))
        stroke.lineWidth = 2.8; stroke.lineCapStyle = .round; stroke.stroke()
        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: 20, y: 2))
        fold.line(to: NSPoint(x: 20, y: 9))
        fold.curve(to: NSPoint(x: 24, y: 13), controlPoint1: NSPoint(x: 20, y: 12), controlPoint2: NSPoint(x: 21, y: 13))
        fold.line(to: NSPoint(x: 31, y: 13)); fold.close()
        (monochrome ? NSColor.black : accent).setFill(); fold.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func image(size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawMark(in: rect, monochrome: template)
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "QuickNote折角纸条"
        return image
    }
}
