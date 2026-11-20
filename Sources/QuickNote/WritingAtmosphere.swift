import AppKit

enum WritingAtmosphere: String, CaseIterable {
    case paper
    case printer
    case telegraph

    var title: String {
        switch self {
        case .paper: "原版纸笺"
        case .printer: "打印机"
        case .telegraph: "电报机"
        }
    }

    var accent: NSColor {
        switch self {
        case .paper: PaperIdentity.accent
        case .printer: NSColor(srgbRed: 0.85, green: 0.64, blue: 0.36, alpha: 1)
        case .telegraph: NSColor(srgbRed: 0.52, green: 0.67, blue: 0.58, alpha: 1)
        }
    }

    func drawMark(in rect: NSRect) {
        guard self != .paper else {
            PaperIdentity.drawMark(in: rect)
            return
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 20, yBy: rect.height / 20)
        transform.concat()

        if self == .printer {
            drawShape(NSBezierPath(roundedRect: NSRect(x: 5, y: 12, width: 10, height: 6), xRadius: 1, yRadius: 1), fill: PaperIdentity.paper)
            drawShape(NSBezierPath(roundedRect: NSRect(x: 1.5, y: 4, width: 17, height: 9), xRadius: 3, yRadius: 3), fill: accent)
            drawShape(NSBezierPath(roundedRect: NSRect(x: 6, y: 2, width: 8, height: 6), xRadius: 1, yRadius: 1), fill: PaperIdentity.paper)
        } else {
            let lever = NSBezierPath()
            lever.move(to: NSPoint(x: 5, y: 13))
            lever.line(to: NSPoint(x: 5, y: 9))
            lever.line(to: NSPoint(x: 15, y: 12))
            lever.line(to: NSPoint(x: 17, y: 5))
            drawShape(lever)
            drawShape(NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3, width: 17, height: 2.5), xRadius: 1.25, yRadius: 1.25), fill: PaperIdentity.paper)
            drawShape(NSBezierPath(roundedRect: NSRect(x: 1, y: 13, width: 8, height: 4.5), xRadius: 2, yRadius: 2), fill: accent)
            drawShape(NSBezierPath(ovalIn: NSRect(x: 13, y: 10, width: 4, height: 4)), fill: PaperIdentity.paper)
        }
    }

    private func drawShape(_ path: NSBezierPath, fill: NSColor? = nil) {
        if let fill {
            fill.setFill()
            path.fill()
        }
        PaperIdentity.ink.setStroke()
        path.lineWidth = 1.65
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

/// AppKit owns the caret's position and blink timer. The overlay can extend beyond
/// its narrow invalidation rectangle without leaving marks when it moves.
final class AtmosphereCaret: NSView {
    var atmosphere = WritingAtmosphere.paper
    var outlinesNextCharacter = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        switch atmosphere {
        case .paper: break
        case .printer:
            let tray = NSBezierPath()
            tray.move(to: NSPoint(x: 0.75, y: 3.4))
            tray.line(to: NSPoint(x: 1.8, y: 0.95))
            tray.line(to: NSPoint(x: bounds.width - 1.8, y: 0.95))
            tray.line(to: NSPoint(x: bounds.width - 0.75, y: 3.4))
            tray.lineWidth = 1.5
            tray.lineCapStyle = .round
            NSColor(srgbRed: 0.62, green: 0.27, blue: 0.17, alpha: 1).setStroke()
            tray.stroke()
        case .telegraph:
            let green = NSColor(srgbRed: 0.25, green: 0.39, blue: 0.32, alpha: 1)
            let head = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 1, yRadius: 1)
            if outlinesNextCharacter {
                green.setStroke()
                head.stroke()
            } else {
                green.setFill()
                head.fill()
            }
        }
    }

    func pulse(lineFeed: Bool) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let movement = CABasicAnimation(keyPath: "transform.translation.y")
        movement.fromValue = atmosphere == .printer ? -2 : (lineFeed ? 3 : 1)
        movement.toValue = 0
        movement.duration = 0.14
        layer?.add(movement, forKey: "strike")
    }
}
