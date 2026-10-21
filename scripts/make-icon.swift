import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let bg = NSBezierPath(roundedRect: NSRect(x: p*0.08, y: p*0.08, width: p*0.84, height: p*0.84), xRadius: p*0.18, yRadius: p*0.18)
        NSColor(srgbRed: 0.094, green: 0.094, blue: 0.106, alpha: 1).setFill(); bg.fill()
        let symbol = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)!.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: p*0.46, weight: .regular))!
        symbol.isTemplate = false
        symbol.lockFocus(); NSColor.white.set(); NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop); symbol.unlockFocus()
        let ratio = symbol.size.width / symbol.size.height
        let h = p*0.48; let w = h*ratio
        symbol.draw(in: NSRect(x: (p-w)/2, y: (p-h)/2, width: w, height: h))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
