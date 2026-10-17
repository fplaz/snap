import AppKit

enum AnnotationTool: String, CaseIterable, Codable {
    case select = "Select", pen = "Pen", arrow = "Arrow", line = "Line"
    case rectangle = "Rectangle", ellipse = "Ellipse", text = "Text"
    case blur = "Blur", numberStamp = "Number stamps"
}

enum AnnotationColor: String, CaseIterable, Codable {
    case red, yellow, green, blue, white, black

    var nsColor: NSColor {
        switch self {
        case .red: return NSColor(srgbRed: 0.95, green: 0.16, blue: 0.2, alpha: 1)
        case .yellow: return NSColor(srgbRed: 1, green: 0.82, blue: 0.1, alpha: 1)
        case .green: return NSColor(srgbRed: 0.1, green: 0.8, blue: 0.35, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.1, green: 0.5, blue: 1, alpha: 1)
        case .white: return .white
        case .black: return .black
        }
    }
}

struct AnnotationStyle: Equatable, Codable {
    var color: AnnotationColor = .red
    var width: CGFloat = 2
    var fontSize: CGFloat = 24
    var blurRadius: CGFloat = 3.5
    var isFilled = false
    var stampDiameter: CGFloat = 32
}

extension AnnotationStyle {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        color = try values.decode(AnnotationColor.self, forKey: .color)
        width = try values.decode(CGFloat.self, forKey: .width)
        fontSize = try values.decode(CGFloat.self, forKey: .fontSize)
        blurRadius = try values.decode(CGFloat.self, forKey: .blurRadius)
        isFilled = try values.decode(Bool.self, forKey: .isFilled)
        stampDiameter = try values.decodeIfPresent(CGFloat.self, forKey: .stampDiameter) ?? 32
    }
}

struct Annotation: Equatable, Identifiable {
    var id = UUID()
    var tool: AnnotationTool
    var points: [CGPoint]
    var style = AnnotationStyle()
    var text = ""
    var textRect = CGRect.zero
    var number = 1

    var bounds: CGRect {
        if tool == .text { return textRect }
        if tool == .numberStamp, let center = points.first {
            return CGRect(x: center.x - style.stampDiameter / 2, y: center.y - style.stampDiameter / 2,
                          width: style.stampDiameter, height: style.stampDiameter)
        }
        guard let first = points.first else { return .zero }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min() ?? first.x, y: ys.min() ?? first.y,
                      width: (xs.max() ?? first.x) - (xs.min() ?? first.x),
                      height: (ys.max() ?? first.y) - (ys.min() ?? first.y))
    }

    var isEmpty: Bool {
        if tool == .text { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if tool == .numberStamp { return points.isEmpty }
        guard let first = points.first, let last = points.last else { return true }
        if tool == .pen { return !points.contains(where: { $0 != first }) }
        if tool == .rectangle || tool == .ellipse || tool == .blur { return bounds.width == 0 || bounds.height == 0 }
        return first == last
    }

    func moved(by delta: CGPoint) -> Annotation {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        copy.textRect = textRect.offsetBy(dx: delta.x, dy: delta.y)
        return copy
    }

    func hitTest(_ point: CGPoint) -> Bool {
        let tolerance = max(5, style.width / 2 + 3)
        switch tool {
        case .numberStamp:
            return !isEmpty && hypot(point.x - bounds.midX, point.y - bounds.midY) <= style.stampDiameter / 2
        case .blur: return bounds.contains(point)
        case .text: return textRect.contains(point)
        case .rectangle:
            let r = bounds
            if style.isFilled { return r.contains(point) }
            let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                           CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
                           CGPoint(x: r.minX, y: r.minY)]
            return Self.hitsSegments(corners, point: point, tolerance: tolerance)
        case .ellipse:
            let r = bounds
            guard r.width > 0, r.height > 0 else { return false }
            let x = (point.x - r.midX) / (r.width / 2), y = (point.y - r.midY) / (r.height / 2)
            if style.isFilled { return x * x + y * y <= 1 }
            return abs(sqrt(x * x + y * y) - 1) * min(r.width, r.height) / 2 <= tolerance
        case .arrow:
            return Self.hitsSegments(points, point: point, tolerance: tolerance) ||
                Self.hitsSegments(AnnotationRenderer.arrowhead(for: self), point: point, tolerance: tolerance)
        default: return Self.hitsSegments(points, point: point, tolerance: tolerance)
        }
    }

    private static func hitsSegments(_ points: [CGPoint], point: CGPoint, tolerance: CGFloat) -> Bool {
        guard points.count > 1 else { return false }
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length == 0 ? 0 : min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length))
            if hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= tolerance { return true }
        }
        return false
    }
}
