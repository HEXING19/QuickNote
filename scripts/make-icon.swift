import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let bg = NSBezierPath(roundedRect: NSRect(x: p*0.08, y: p*0.08, width: p*0.84, height: p*0.84), xRadius: p*0.18, yRadius: p*0.18)
        PaperIdentity.paper.setFill(); bg.fill()
        PaperIdentity.drawMark(in: NSRect(x: p*0.25, y: p*0.25, width: p*0.50, height: p*0.50))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
