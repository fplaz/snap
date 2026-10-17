import AppKit

@MainActor
final class CaptureToolbar: NSView {
    static let preferredSize = CGSize(width: 442, height: 52)
    var onCopy: (() -> Void)?
    var onUpload: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    var onStartOver: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onTool: ((AnnotationTool) -> Void)?
    var onStyle: ((AnnotationStyle) -> Void)?
    var movementBounds: CGRect?
    private var dragOrigin: CGPoint?
    private var originalOrigin = CGPoint.zero
    private var editingControls: [NSControl] = []
    private var uploadButton: NSButton!
    private var uploadAvailable = false
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private let tool = NSPopUpButton()
    private let color = NSPopUpButton()
    private let width = NSPopUpButton()
    private let fontSize = NSPopUpButton()
    private let blurLevel = NSSlider(value: 3.5, minValue: 1, maxValue: 12, target: nil, action: nil)
    private let blurValue = NSTextField(labelWithString: "3.5")
    private var exporting = false
    private var canUndo = false
    private var canRedo = false

    init() {
        super.init(frame: CGRect(origin: .zero, size: Self.preferredSize))
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        let symbols = ["cursorarrow", "pencil.tip", "arrow.up.right", "line.diagonal", "rectangle", "oval", "textformat", "drop.halffull"]
        popup(tool, labels: AnnotationTool.allCases.map(\.rawValue), images: symbols.map { toolIcon($0) },
              x: 30, label: "Drawing tool", action: #selector(toolChanged))
        tool.selectItem(at: AnnotationTool.allCases.firstIndex(of: .rectangle)!)
        popup(color, labels: AnnotationColor.allCases.map { $0.rawValue.capitalized },
              images: AnnotationColor.allCases.map { swatch($0.nsColor) },
              x: 78, label: "Annotation color", action: #selector(styleChanged))
        popup(width, labels: ["Thin", "Medium", "Thick"], images: [2, 4, 8].map { lineIcon($0) },
              x: 126, label: "Line width", action: #selector(styleChanged))
        popup(fontSize, labels: ["Small text", "Medium text", "Large text"],
              images: [12, 18, 24].map { textIcon($0) }, x: 126, label: "Text size", action: #selector(styleChanged))
        width.selectItem(at: 1); fontSize.selectItem(at: 1); fontSize.isHidden = true
        blurLevel.frame = CGRect(x: 78, y: 16, width: 65, height: 20)
        blurLevel.controlSize = .small
        blurLevel.isContinuous = false
        blurLevel.target = self; blurLevel.action = #selector(blurChanged)
        blurLevel.setAccessibilityLabel("Blur strength")
        blurValue.frame = CGRect(x: 144, y: 18, width: 28, height: 17)
        blurValue.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        blurValue.textColor = NSColor(white: 0.88, alpha: 1)
        blurValue.alignment = .center
        blurValue.setAccessibilityLabel("Blur strength value")
        editingControls.append(blurLevel)
        addSubview(blurLevel); addSubview(blurValue)
        setBlurLevel(3.5)
        setContextualTool(.rectangle)
        undoButton = button("Undo", symbol: "arrow.uturn.backward", x: 184, action: #selector(undo))
        redoButton = button("Redo", symbol: "arrow.uturn.forward", x: 218, action: #selector(redo))
        undoButton.toolTip = "Undo (⌘Z)"; redoButton.toolTip = "Redo (⌘⇧Z)"
        _ = button("Copy", symbol: "doc.on.doc", x: 266, action: #selector(copyImage))
        _ = button("Save", symbol: "square.and.arrow.down", x: 300, action: #selector(saveImage))
        uploadButton = button("Upload & Copy Link", symbol: "icloud.and.arrow.up", x: 334, action: #selector(upload))
        _ = button("Clear Annotations", symbol: "arrow.counterclockwise", x: 368, action: #selector(startOver))
        let cancel = button("Cancel", symbol: "xmark", x: 402, action: #selector(cancel))
        editingControls.removeAll { $0 === cancel }
        toolTip = "Drag the six-dot handle to move the toolbar"
        setUploadAvailability(false, hint: "Sign in from the Snap menu to upload")
        updateHistory(canUndo: false, canRedo: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGradient(colors: [NSColor(white: 0.035, alpha: 1), NSColor(white: 0.105, alpha: 1),
                            NSColor(white: 0.055, alpha: 1)])?.draw(in: bounds, angle: 80)
        // Restrained brushed-metal texture, drawn once with the toolbar rather than the capture.
        NSColor.white.withAlphaComponent(0.025).setStroke()
        let grain = NSBezierPath()
        grain.lineWidth = 0.5
        for y in stride(from: CGFloat(1), through: bounds.height, by: 3) {
            grain.move(to: CGPoint(x: 0, y: y)); grain.line(to: CGPoint(x: bounds.width, y: y))
        }
        grain.stroke()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        let separators = NSBezierPath()
        for x: CGFloat in [176, 258] {
            separators.move(to: CGPoint(x: x, y: 14)); separators.line(to: CGPoint(x: x, y: 38))
        }
        separators.lineWidth = 1; separators.stroke()
        NSColor(white: 0.48, alpha: 1).setFill()
        for x: CGFloat in [13, 19] {
            for y: CGFloat in [20, 26, 32] {
                NSBezierPath(ovalIn: CGRect(x: x - 1.25, y: y - 1.25, width: 2.5, height: 2.5)).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func resetCursorRects() {
        addCursorRect(CGRect(x: 0, y: 0, width: 28, height: bounds.height), cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard !exporting else { return }
        dragOrigin = event.locationInWindow
        originalOrigin = frame.origin
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, let superview else { return }
        let start = superview.convert(dragOrigin, from: nil)
        let current = superview.convert(event.locationInWindow, from: nil)
        let limit = movementBounds ?? superview.bounds
        frame.origin = CGPoint(x: min(max(limit.minX, originalOrigin.x + current.x - start.x),
                                      max(limit.minX, limit.maxX - frame.width)),
                               y: min(max(limit.minY, originalOrigin.y + current.y - start.y),
                                      max(limit.minY, limit.maxY - frame.height)))
        window?.invalidateCursorRects(for: superview)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        NSCursor.openHand.set()
    }

    func updateHistory(canUndo: Bool, canRedo: Bool) {
        self.canUndo = canUndo; self.canRedo = canRedo
        undoButton.isEnabled = canUndo && !exporting
        redoButton.isEnabled = canRedo && !exporting
    }

    func setUploadAvailability(_ available: Bool, hint: String) {
        uploadAvailable = available
        uploadButton.isEnabled = available && !exporting
        uploadButton.toolTip = hint
    }

    func setExporting(_ exporting: Bool) {
        self.exporting = exporting
        dragOrigin = nil
        editingControls.forEach { $0.isEnabled = !exporting }
        uploadButton.isEnabled = uploadAvailable && !exporting
        updateHistory(canUndo: canUndo, canRedo: canRedo)
    }

    func setStyle(_ style: AnnotationStyle) {
        color.selectItem(at: AnnotationColor.allCases.firstIndex(of: style.color) ?? 0)
        width.selectItem(at: [CGFloat(2), 4, 8].firstIndex(of: style.width) ?? 1)
        fontSize.selectItem(at: [CGFloat(16), 24, 32].firstIndex(of: style.fontSize) ?? 1)
        setBlurLevel(style.blurRadius)
    }

    private func popup(_ control: NSPopUpButton, labels: [String], images: [NSImage?],
                       x: CGFloat, label: String, action: Selector) {
        for (index, label) in labels.enumerated() {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.image = images[index]; item.toolTip = label; item.setAccessibilityLabel(label)
            control.menu?.addItem(item)
        }
        control.frame = CGRect(x: x, y: 10, width: 44, height: 32)
        control.isBordered = false; control.imagePosition = .imageOnly
        control.contentTintColor = NSColor(white: 0.88, alpha: 1)
        control.target = self; control.action = action
        control.toolTip = label; control.setAccessibilityLabel(label)
        editingControls.append(control); addSubview(control)
    }

    private func button(_ title: String, symbol name: String, x: CGFloat, action: Selector) -> NSButton {
        let control = NSButton(title: "", target: self, action: action)
        control.image = symbol(name); control.imagePosition = .imageOnly
        control.isBordered = false
        control.contentTintColor = NSColor(white: 0.88, alpha: 1)
        control.frame = CGRect(x: x, y: 10, width: 32, height: 32)
        control.toolTip = title; control.setAccessibilityLabel(title)
        editingControls.append(control); addSubview(control)
        return control
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
    }

    private func toolIcon(_ name: String) -> NSImage? {
        guard let symbol = symbol(name) else { return nil }
        let size = CGSize(width: 24, height: 28)
        let image = NSImage(size: size)
        // Rasterize at fixed scales so AppKit's selection animation scales the whole
        // centered canvas instead of asking the symbol to lay itself out again.
        for scale in [1, 2] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            symbol.draw(in: CGRect(x: (size.width - symbol.size.width) / 2,
                                   y: (size.height - symbol.size.height) / 2,
                                   width: symbol.size.width, height: symbol.size.height))
            NSGraphicsContext.restoreGraphicsState()
            bitmap.size = size
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        return image
    }

    private func lineIcon(_ thickness: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: 24, height: 28), flipped: false) { _ in
            NSColor.white.setStroke()
            let path = NSBezierPath(); path.lineWidth = thickness; path.lineCapStyle = .round
            path.move(to: CGPoint(x: 4, y: 14)); path.line(to: CGPoint(x: 20, y: 14)); path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func textIcon(_ size: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: 24, height: 28), flipped: false) { rect in
            let text = "A" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .medium),
                                                            .foregroundColor: NSColor.white]
            let measured = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (rect.width - measured.width) / 2, y: (rect.height - measured.height) / 2),
                      withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: CGSize(width: 24, height: 28), flipped: false) { _ in
            let circle = NSBezierPath(ovalIn: CGRect(x: 5, y: 7, width: 14, height: 14))
            color.setFill(); circle.fill()
            NSColor.white.withAlphaComponent(0.4).setStroke(); circle.lineWidth = 1; circle.stroke()
            return true
        }
    }

    @objc private func toolChanged() {
        let selected = AnnotationTool.allCases[tool.indexOfSelectedItem]
        setTool(selected)
        onTool?(selected)
    }
    func setTool(_ selected: AnnotationTool) {
        tool.selectItem(at: AnnotationTool.allCases.firstIndex(of: selected)!)
        setContextualTool(selected)
        tool.toolTip = "\(selected.rawValue) · Tab: next tool · Shift+Tab: previous tool · Hold Space: Select"
    }
    func setContextualTool(_ selected: AnnotationTool) {
        width.isHidden = selected == .text || selected == .blur; fontSize.isHidden = selected != .text
        color.isHidden = selected == .blur
        blurLevel.isHidden = selected != .blur; blurValue.isHidden = selected != .blur
    }
    private func setBlurLevel(_ value: CGFloat) {
        blurLevel.doubleValue = Double(value)
        blurValue.stringValue = String(format: "%.1f", blurLevel.doubleValue)
        blurLevel.toolTip = "Blur strength: \(blurValue.stringValue) · 1 (light) to 12 (strong)"
    }
    @objc private func blurChanged() {
        setBlurLevel(CGFloat((blurLevel.doubleValue * 2).rounded() / 2))
        styleChanged()
    }
    @objc private func styleChanged() {
        onStyle?(AnnotationStyle(color: AnnotationColor.allCases[color.indexOfSelectedItem],
                                 width: [2, 4, 8][width.indexOfSelectedItem],
                                 fontSize: [16, 24, 32][fontSize.indexOfSelectedItem],
                                 blurRadius: CGFloat(blurLevel.doubleValue)))
    }
    @objc private func undo() { onUndo?() }
    @objc private func redo() { onRedo?() }
    @objc private func copyImage() { onCopy?() }
    @objc private func upload() { onUpload?() }
    @objc private func saveImage() { onSave?() }
    @objc private func startOver() { onStartOver?() }
    @objc private func cancel() { onCancel?() }
}
