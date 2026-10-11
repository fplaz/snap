import CoreGraphics

enum SelectionGeometry {
    static func rectangle(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        let a = clamped(start, to: bounds)
        let b = clamped(end, to: bounds)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func clamped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    // AppKit uses bottom-left logical coordinates; CGImage crops use top-left pixels.
    static func pixelRectangle(for selection: CGRect, logicalSize: CGSize, pixelSize: CGSize) -> CGRect? {
        guard logicalSize.width > 0, logicalSize.height > 0,
              pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let clipped = selection.standardized.intersection(CGRect(origin: .zero, size: logicalSize))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        let scaleX = pixelSize.width / logicalSize.width
        let scaleY = pixelSize.height / logicalSize.height
        let left = floor(clipped.minX * scaleX)
        let right = ceil(clipped.maxX * scaleX)
        let top = floor((logicalSize.height - clipped.maxY) * scaleY)
        let bottom = ceil((logicalSize.height - clipped.minY) * scaleY)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
            .intersection(CGRect(origin: .zero, size: pixelSize))
    }

    static func toolbarFrame(selection: CGRect, size: CGSize, bounds: CGRect) -> CGRect {
        let margin: CGFloat = 12
        let gap: CGFloat = 10
        let x = min(max(selection.maxX - size.width, bounds.minX + margin),
                    max(bounds.minX + margin, bounds.maxX - margin - size.width))
        var y = selection.minY - gap - size.height
        if y < bounds.minY + margin { y = selection.maxY + gap }
        if y + size.height > bounds.maxY - margin {
            y = min(max(selection.minY + gap, bounds.minY + margin), bounds.maxY - margin - size.height)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    static func resizedToolbar(original: CGRect, from start: CGRect, to selection: CGRect, bounds: CGRect) -> CGRect {
        let x = original.maxX >= start.maxX
            ? original.minX + selection.maxX - start.maxX
            : min(original.minX, selection.maxX - original.width)
        let y = original.maxY <= start.minY
            ? original.minY + selection.minY - start.minY
            : max(original.minY, selection.minY - 10 - original.height)
        return CGRect(x: min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - original.width)),
                      y: min(max(y, bounds.minY), max(bounds.minY, bounds.maxY - original.height)),
                      width: original.width, height: original.height)
    }
}
