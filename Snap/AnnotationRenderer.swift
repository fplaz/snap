import AppKit
import CoreImage

enum AnnotationRenderer {
    private static let blurContext = CIContext()

    // Use the full frozen display so crop boundaries do not create blur seams.
    static func blurredScreenshot(_ image: CGImage, logicalSize: CGSize, radius: CGFloat) throws -> NSImage {
        let source = CIImage(cgImage: image)
        let pixelRadius = radius * CGFloat(image.width) / logicalSize.width
        let filtered = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: pixelRadius])
        guard let result = blurContext.createCGImage(filtered, from: source.extent) else {
            throw CaptureError.encodingFailed
        }
        return NSImage(cgImage: result, size: logicalSize)
    }

    static func arrowhead(for annotation: Annotation) -> [CGPoint] {
        guard let start = annotation.points.first, let end = annotation.points.last else { return [] }
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = min(max(12, annotation.style.width * 3), hypot(end.x - start.x, end.y - start.y) * 0.6)
        return [CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)),
                end, CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6))]
    }

    static func draw(_ annotations: [Annotation], in bounds: CGRect,
                     blurredScreenshot: (CGFloat) throws -> NSImage? = { _ in nil }, screenshotRect: CGRect = .zero) rethrows {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        // Blur the screenshot first; marks stay legible and overlapping areas do not compound.
        for annotation in annotations where annotation.tool == .blur && !annotation.isEmpty {
            let blurred = try blurredScreenshot(annotation.style.blurRadius)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: annotation.bounds).addClip()
            if let blurred {
                blurred.draw(in: screenshotRect, from: .zero, operation: .copy, fraction: 1)
            } else {
                // Never expose the original area if preview filtering is unavailable.
                NSColor.black.setFill()
                NSBezierPath(rect: annotation.bounds).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        for annotation in annotations where annotation.tool != .blur {
            if annotation.tool == .text { drawText(annotation); continue }
            let path = NSBezierPath()
            path.lineWidth = annotation.style.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            annotation.style.color.nsColor.setStroke()
            switch annotation.tool {
            case .rectangle: path.appendRect(annotation.bounds)
            case .ellipse: path.appendOval(in: annotation.bounds)
            default:
                if let first = annotation.points.first {
                    path.move(to: first)
                    annotation.points.dropFirst().forEach { path.line(to: $0) }
                }
                if annotation.tool == .arrow {
                    let head = arrowhead(for: annotation)
                    if let first = head.first {
                        path.move(to: first); head.dropFirst().forEach { path.line(to: $0) }
                    }
                }
            }
            path.stroke()
        }
    }

    static func attributes(for style: AnnotationStyle) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: NSFont.systemFont(ofSize: style.fontSize),
                .foregroundColor: style.color.nsColor, .paragraphStyle: paragraph]
    }

    static func textHeight(_ text: String, width: CGFloat, style: AnnotationStyle) -> CGFloat {
        let storage = NSTextStorage(string: text, attributes: attributes(for: style))
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: 10000))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return max(style.fontSize * 1.4, layout.usedRect(for: container).height)
    }

    private static func drawText(_ annotation: Annotation) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: annotation.textRect)
        context.translateBy(x: annotation.textRect.minX, y: annotation.textRect.maxY)
        context.scaleBy(x: 1, y: -1)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let storage = NSTextStorage(string: annotation.text, attributes: attributes(for: annotation.style))
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: annotation.textRect.size)
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.drawGlyphs(forGlyphRange: layout.glyphRange(for: container), at: .zero)
        NSGraphicsContext.current = previous
        context.restoreGState()
    }
}
