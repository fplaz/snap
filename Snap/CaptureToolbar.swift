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
    private let shapeStyle = NSPopUpButton()
    private let fontSize = NSPopUpButton()
    private let blurLevel = NSSlider(value: 3.5, minValue: 1, maxValue: 12, target: nil, action: nil)
    private let blurValue = NSTextField(labelWithString: "3.5")
    private var exporting = false
    private var canUndo = false
    private var canRedo = false
    private var hoverTracking: NSTrackingArea?
    private weak var hoveredControl: NSControl?
    private var tooltipTask: Task<Void, Never>?
    private let hoverHint = ToolbarHoverHint()

    override var isHidden: Bool {
        didSet { if isHidden { hideHoverHint() } }
    }

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
        let shapeLabels = ["Thin outline", "Medium outline", "Thick outline", "Filled"]
        popup(shapeStyle, labels: shapeLabels,
              images: [2, 4, 8, 0].map { shapeIcon(.rectangle, thickness: $0) },
              x: 126, label: "Shape style", action: #selector(shapeStyleChanged))
        for (item, label) in zip(shapeStyle.itemArray, shapeLabels) { item.title = label }
        shapeStyle.selectItem(at: 1)
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
        let copy = button("Copy", symbol: "doc.on.doc", x: 266, action: #selector(copyImage))
        copy.toolTip = "Copy (⌘C)"
        let save = button("Save", symbol: "square.and.arrow.down", x: 300, action: #selector(saveImage))
        save.toolTip = "Save (⌘S)"
        uploadButton = button("Upload & Copy Link", symbol: "icloud.and.arrow.up", x: 334, action: #selector(upload))
        _ = button("Clear Annotations", symbol: "arrow.counterclockwise", x: 368, action: #selector(startOver))
        let cancel = button("Cancel", symbol: "xmark", x: 402, action: #selector(cancel))
        cancel.toolTip = "Cancel (Esc)"
        editingControls.removeAll { $0 === cancel }
        toolTip = "Drag the six-dot handle to move the toolbar"
        setUploadAvailability(false, hint: "Sign in from the Snap menu to upload")
        updateHistory(canUndo: false, canRedo: false)
        setStyle(AnnotationStyle())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        hideHoverHint()
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseEntered(with event: NSEvent) { updateHoverHint(with: event) }
    override func mouseMoved(with event: NSEvent) { updateHoverHint(with: event) }
    override func mouseExited(with event: NSEvent) { hideHoverHint() }

    private func updateHoverHint(with event: NSEvent) {
        guard !isHidden, !exporting, dragOrigin == nil else { hideHoverHint(); return }
        let point = convert(event.locationInWindow, from: nil)
        let control = subviews.compactMap { $0 as? NSControl }.first {
            !$0.isHidden && $0.frame.contains(point) && $0.toolTip != nil
        }
        guard control !== hoveredControl else { return }
        hideHoverHint()
        guard let control else { return }
        hoveredControl = control
        tooltipTask = Task { @MainActor [weak self, weak control] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, let control, self.hoveredControl === control,
                  !self.isHidden, let parent = self.superview, let text = control.toolTip else { return }
            self.hoverHint.setText(text, maxWidth: parent.bounds.width - 8)
            let target = self.convert(control.bounds, from: control).offsetBy(dx: self.frame.minX, dy: self.frame.minY)
            let size = self.hoverHint.frame.size
            let x = min(max(parent.bounds.minX + 4, target.midX - size.width / 2),
                        max(parent.bounds.minX + 4, parent.bounds.maxX - size.width - 4))
            let below = self.frame.minY - size.height - 6
            let y = below >= parent.bounds.minY + 4 ? below : self.frame.maxY + 6
            self.hoverHint.frame.origin = CGPoint(x: x, y: min(y, parent.bounds.maxY - size.height - 4))
            parent.addSubview(self.hoverHint, positioned: .above, relativeTo: self)
        }
    }

    private func hideHoverHint() {
        tooltipTask?.cancel()
        tooltipTask = nil
        hoveredControl = nil
        hoverHint.removeFromSuperview()
    }

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
        hideHoverHint()
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
        hideHoverHint()
        self.exporting = exporting
        dragOrigin = nil
        editingControls.forEach { $0.isEnabled = !exporting }
        uploadButton.isEnabled = uploadAvailable && !exporting
        updateHistory(canUndo: canUndo, canRedo: canRedo)
    }

    func setStyle(_ style: AnnotationStyle) {
        color.selectItem(at: AnnotationColor.allCases.firstIndex(of: style.color) ?? 0)
        width.selectItem(at: [CGFloat(2), 4, 8].firstIndex(of: style.width) ?? 1)
        shapeStyle.selectItem(at: style.isFilled ? 3 : width.indexOfSelectedItem)
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

    private func shapeIcon(_ tool: AnnotationTool, thickness: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: 24, height: 28), flipped: false) { _ in
            let rect = CGRect(x: 5, y: 7, width: 14, height: 14)
            let path = tool == .ellipse ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            if thickness == 0 {
                NSColor.white.setFill(); path.fill()
            } else {
                NSColor.white.setStroke(); path.lineWidth = thickness / 2; path.stroke()
            }
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
        hideHoverHint()
        let selected = AnnotationTool.allCases[tool.indexOfSelectedItem]
        setTool(selected)
        onTool?(selected)
    }
    func setTool(_ selected: AnnotationTool) {
        tool.selectItem(at: AnnotationTool.allCases.firstIndex(of: selected)!)
        setContextualTool(selected)
        tool.toolTip = "Tool"
    }
    func setContextualTool(_ selected: AnnotationTool) {
        let isShape = selected == .rectangle || selected == .ellipse
        width.isHidden = isShape || selected == .text || selected == .blur
        shapeStyle.isHidden = !isShape
        if isShape {
            for (index, thickness) in [CGFloat(2), 4, 8, 0].enumerated() {
                shapeStyle.item(at: index)?.image = shapeIcon(selected, thickness: thickness)
            }
        }
        fontSize.isHidden = selected != .text
        color.isHidden = selected == .blur
        blurLevel.isHidden = selected != .blur; blurValue.isHidden = selected != .blur
    }
    private func setBlurLevel(_ value: CGFloat) {
        blurLevel.doubleValue = Double(value)
        blurValue.stringValue = String(format: "%.1f", blurLevel.doubleValue)
        blurLevel.toolTip = "Blur strength"
    }
    @objc private func blurChanged() {
        setBlurLevel(CGFloat((blurLevel.doubleValue * 2).rounded() / 2))
        styleChanged()
    }
    @objc private func styleChanged() {
        hideHoverHint()
        if shapeStyle.indexOfSelectedItem != 3 { shapeStyle.selectItem(at: width.indexOfSelectedItem) }
        onStyle?(AnnotationStyle(color: AnnotationColor.allCases[color.indexOfSelectedItem],
                                 width: [2, 4, 8][width.indexOfSelectedItem],
                                 fontSize: [16, 24, 32][fontSize.indexOfSelectedItem],
                                 blurRadius: CGFloat(blurLevel.doubleValue),
                                 isFilled: shapeStyle.indexOfSelectedItem == 3))
    }
    @objc private func shapeStyleChanged() {
        if shapeStyle.indexOfSelectedItem < 3 { width.selectItem(at: shapeStyle.indexOfSelectedItem) }
        styleChanged()
    }
    @objc private func undo() { hideHoverHint(); onUndo?() }
    @objc private func redo() { hideHoverHint(); onRedo?() }
    @objc private func copyImage() { hideHoverHint(); onCopy?() }
    @objc private func upload() { hideHoverHint(); onUpload?() }
    @objc private func saveImage() { hideHoverHint(); onSave?() }
    @objc private func startOver() { hideHoverHint(); onStartOver?() }
    @objc private func cancel() { hideHoverHint(); onCancel?() }
}

@MainActor
private final class ToolbarHoverHint: NSView {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true
        label.cell?.usesSingleLineMode = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func setText(_ text: String, maxWidth: CGFloat) {
        label.stringValue = text
        let width = max(1, maxWidth - 18)
        let size = label.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: width, height: 10_000)) ?? .zero
        label.frame.size = CGSize(width: min(width, size.width), height: size.height)
        label.frame.origin = CGPoint(x: 9, y: 5)
        frame.size = CGSize(width: label.frame.width + 18, height: label.frame.height + 10)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
