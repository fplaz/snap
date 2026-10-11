import AppKit

// Native Finder supplies the app and Applications icons; this image is only the backdrop.
let output = CommandLine.arguments[1]
let version = CommandLine.arguments[2]
let size = NSSize(width: 1920, height: 1200)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3840, pixelsHigh: 2400,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let bounds = CGRect(origin: .zero, size: size)
NSGradient(colors: [NSColor(white: 0.045, alpha: 1), NSColor(white: 0.105, alpha: 1),
                    NSColor(white: 0.055, alpha: 1)])!.draw(in: bounds, angle: 75)
let grain = NSBezierPath()
grain.lineWidth = 0.5
for y in stride(from: CGFloat(0), through: size.height, by: 2) {
    grain.move(to: CGPoint(x: 0, y: y)); grain.line(to: CGPoint(x: size.width, y: y))
}
NSColor.white.withAlphaComponent(0.025).setStroke(); grain.stroke()
// Keep the installation layout anchored at the top left even in a larger Finder window.
NSGraphicsContext.current!.cgContext.translateBy(x: 0, y: size.height - 400)

func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
    ])
}
text("Snap", x: 44, y: 313, size: 32, weight: .semibold, color: .white)
text("VERSION \(version)", x: 508, y: 324, size: 11, weight: .medium, color: NSColor(white: 0.65, alpha: 1))
let rule = NSBezierPath()
rule.move(to: CGPoint(x: 44, y: 290)); rule.line(to: CGPoint(x: 596, y: 290))
rule.lineWidth = 0.5; NSColor.white.withAlphaComponent(0.12).setStroke(); rule.stroke()

let arrow = NSBezierPath()
arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: CGPoint(x: 274, y: 210)); arrow.line(to: CGPoint(x: 366, y: 210))
arrow.move(to: CGPoint(x: 354, y: 222)); arrow.line(to: CGPoint(x: 366, y: 210))
arrow.line(to: CGPoint(x: 354, y: 198))
NSColor(white: 0.75, alpha: 1).setStroke(); arrow.stroke()
// Finder controls label text color; pale metal plates keep labels legible in either appearance.
for x: CGFloat in [86, 406] {
    let plate = NSBezierPath(roundedRect: CGRect(x: x, y: 132, width: 148, height: 24), xRadius: 7, yRadius: 7)
    NSGradient(colors: [NSColor(white: 0.78, alpha: 1), NSColor(white: 0.65, alpha: 1)])!.draw(in: plate, angle: 90)
}
let instruction = "Drag Snap to Applications"
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.white]
let width = (instruction as NSString).size(withAttributes: attributes).width
(instruction as NSString).draw(at: CGPoint(x: (640 - width) / 2, y: 69), withAttributes: attributes)
let hint = "Then open Snap from Applications."
let hintAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(white: 0.6, alpha: 1)]
let hintWidth = (hint as NSString).size(withAttributes: hintAttributes).width
(hint as NSString).draw(at: CGPoint(x: (640 - hintWidth) / 2, y: 45), withAttributes: hintAttributes)
try bitmap.tiffRepresentation!.write(to: URL(fileURLWithPath: output))
