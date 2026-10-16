import AppKit

@MainActor
final class CaptureOverlayView: NSView, NSTextViewDelegate {
    private let snapshot: DisplaySnapshot
    private let screenshot: NSImage
    private let blurredScreenshots = NSCache<NSNumber, NSImage>()
    private var dragOrigin: CGPoint?
    private(set) var selection: CGRect?
    private var tracking: NSTrackingArea?
    let toolbar = CaptureToolbar()
    let document: AnnotationDocument
    private var tool: AnnotationTool = .rectangle
    private var toolBeforeSpace: AnnotationTool?
    private var style = AnnotationStyle()
    private var selectedID: UUID?
    private var draft: Annotation?
    private var moveOriginal: Annotation?
    private var annotationOrigin: CGPoint?
    private var textEditor: AnnotationTextEditor?
    private var editingText: Annotation?
    private var areaDrag: (start: CGPoint, selection: CGRect, toolbar: CGRect)?
    private var areaResize: (start: CGPoint, selection: CGRect, toolbar: CGRect, offset: CGPoint)?
    private var annotationOffset: CGPoint = .zero
    private let borderHitWidth: CGFloat = 7
    private var contentOrigin: CGPoint {
        CGPoint(x: (selection?.minX ?? 0) + annotationOffset.x, y: (selection?.minY ?? 0) + annotationOffset.y)
    }
    var exportAnnotations: [Annotation] { document.annotations.map { $0.moved(by: annotationOffset) } }

    var onBeginSelection: (() -> Bool)?
    var onSelect: ((CGRect) -> Void)?
    var onMoveSelection: ((CGRect) -> Void)?
    var onResizeSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onCopy: (() -> Void)?
    var onUpload: (() -> Void)?
    var onSave: (() -> Void)?
    var onStartOver: (() -> Void)?
    var isExporting = false {
        didSet {
            if isExporting { restoreTemporaryTool() }
            toolbar.setExporting(isExporting)
        }
    }

    init(snapshot: DisplaySnapshot, document: AnnotationDocument) {
        self.snapshot = snapshot
        self.document = document
        blurredScreenshots.countLimit = 3
        screenshot = NSImage(cgImage: snapshot.image, size: snapshot.logicalSize)
        super.init(frame: CGRect(origin: .zero, size: snapshot.logicalSize))
        toolbar.isHidden = true
        addSubview(toolbar)
        toolbar.onTool = { [weak self] tool in
            self?.changeTool(tool)
        }
        toolbar.setTool(tool)
        toolbar.onStyle = { [weak self] style in self?.changeStyle(style) }
        toolbar.onUndo = { [weak self] in self?.undoAnnotation() }
        toolbar.onRedo = { [weak self] in self?.redoAnnotation() }
        toolbar.onCopy = { [weak self] in self?.onCopy?() }
        toolbar.onUpload = { [weak self] in self?.onUpload?() }
        toolbar.onSave = { [weak self] in self?.onSave?() }
        toolbar.onCancel = { [weak self] in self?.onCancel?() }
        toolbar.onStartOver = { [weak self] in self?.onStartOver?() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var acceptsFirstResponder: Bool { true }

    // Each display has its own window; the first drag must also select in a non-key overlay.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: toolCursor)
        if let selection, dragOrigin == nil, !isExporting {
            let cursor: NSCursor = areaDrag == nil ? .openHand : .closedHand
            let outer = selection.insetBy(dx: -borderHitWidth, dy: -borderHitWidth)
            let edges = [
                CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: borderHitWidth * 2),
                CGRect(x: outer.minX, y: selection.maxY - borderHitWidth, width: outer.width, height: borderHitWidth * 2),
                CGRect(x: outer.minX, y: selection.minY, width: borderHitWidth * 2, height: selection.height),
                CGRect(x: selection.maxX - borderHitWidth, y: selection.minY, width: borderHitWidth * 2, height: selection.height)
            ]
            for edge in edges { addCursorRect(edge.intersection(bounds), cursor: cursor) }
            if let handle = resizeHandle {
                addCursorRect(handle.intersection(bounds), cursor: areaResize == nil ? .openHand : .closedHand)
            }
        }
        if !toolbar.isHidden {
            addCursorRect(toolbar.frame, cursor: .arrow)
            addCursorRect(CGRect(x: toolbar.frame.minX, y: toolbar.frame.minY,
                                 width: 28, height: toolbar.frame.height), cursor: .openHand)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if areaDrag != nil { NSCursor.closedHand.set(); return }
        if areaResize != nil { NSCursor.closedHand.set(); return }
        let point = convert(event.locationInWindow, from: nil)
        if !toolbar.isHidden, toolbar.frame.contains(point) {
            if point.x < toolbar.frame.minX + 28 { NSCursor.openHand.set() }
            else { NSCursor.arrow.set() }
        }
        else {
            if resizeHandle?.contains(point) == true { NSCursor.openHand.set() }
            else if isSelectionBorder(point) { NSCursor.openHand.set() }
            else { toolCursor.set() }
        }
    }

    private var toolCursor: NSCursor { tool == .select ? .arrow : .crosshair }

    private var resizeHandle: CGRect? {
        guard let selection, dragOrigin == nil, !isExporting else { return nil }
        return CGRect(x: selection.maxX - 18, y: selection.minY - 6, width: 24, height: 24)
    }

    private func isSelectionBorder(_ point: CGPoint) -> Bool {
        guard let selection, dragOrigin == nil, !isExporting else { return false }
        if !toolbar.isHidden, toolbar.frame.contains(point) { return false }
        return (selection.insetBy(dx: -borderHitWidth, dy: -borderHitWidth).contains(point)
                && !selection.insetBy(dx: borderHitWidth, dy: borderHitWidth).contains(point))
    }

    override func mouseMoved(with event: NSEvent) { cursorUpdate(with: event) }
    override func mouseEntered(with event: NSEvent) { cursorUpdate(with: event) }

    override func draw(_ dirtyRect: NSRect) {
        screenshot.draw(in: bounds)
        let mask = NSBezierPath(rect: bounds)
        if let selection, selection.width > 0, selection.height > 0 {
            mask.appendRect(selection)
        }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill()
        mask.fill()
        if let selection, selection.width > 0, selection.height > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            let transform = AffineTransform(translationByX: contentOrigin.x, byY: contentOrigin.y)
            (transform as NSAffineTransform).concat()
            var annotations = document.annotations.filter { $0.id != editingText?.id && $0.id != draft?.id }
            if let draft { annotations.append(draft) }
            AnnotationRenderer.draw(annotations, in: CGRect(x: -annotationOffset.x, y: -annotationOffset.y,
                                                            width: selection.width, height: selection.height),
                                    blurredScreenshot: { [self] radius in
                                        let key = NSNumber(value: Double(radius))
                                        if let cached = blurredScreenshots.object(forKey: key) { return cached }
                                        guard let image = try? AnnotationRenderer.blurredScreenshot(
                                            snapshot.image, logicalSize: snapshot.logicalSize, radius: radius) else { return nil }
                                        blurredScreenshots.setObject(image, forKey: key)
                                        return image
                                    },
                                    screenshotRect: CGRect(x: -contentOrigin.x, y: -contentOrigin.y,
                                                           width: bounds.width, height: bounds.height))
            if let selected = annotations.first(where: { $0.id == selectedID }) {
                NSColor.white.setStroke()
                let outline = NSBezierPath(rect: selected.bounds.insetBy(dx: -4, dy: -4))
                outline.lineWidth = 1
                outline.setLineDash([4, 3], count: 2, phase: 0)
                outline.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1
            border.stroke()
            if dragOrigin == nil {
                NSColor.black.setStroke()
                let corner = NSBezierPath()
                corner.lineWidth = 2.5
                corner.move(to: CGPoint(x: selection.maxX - 13, y: selection.minY + 1.5))
                corner.line(to: CGPoint(x: selection.maxX - 1.5, y: selection.minY + 1.5))
                corner.line(to: CGPoint(x: selection.maxX - 1.5, y: selection.minY + 13))
                corner.stroke()
            }
        } else {
            let text = "Drag to capture · Esc to cancel" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white
            ]
            let size = text.size(withAttributes: attributes)
            let frame = CGRect(x: (bounds.width - size.width) / 2, y: bounds.height - 76,
                               width: size.width, height: size.height)
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: frame.insetBy(dx: -16, dy: -10), xRadius: 10, yRadius: 10).fill()
            text.draw(in: frame, withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isExporting else { return }
        if let selection {
            commitText()
            let position = convert(event.locationInWindow, from: nil)
            if resizeHandle?.contains(position) == true, toolbar.isHidden || !toolbar.frame.contains(position) {
                cancelGesture(); selectedID = nil
                window?.makeKey(); window?.makeFirstResponder(self)
                areaResize = (position, selection, toolbar.frame, annotationOffset)
                NSCursor.closedHand.set()
                needsDisplay = true
                return
            }
            if isSelectionBorder(position) {
                cancelGesture()
                window?.makeKey(); window?.makeFirstResponder(self)
                areaDrag = (position, selection, toolbar.frame)
                NSCursor.closedHand.set(); needsDisplay = true
                return
            }
            guard selection.contains(position) else { return }
            window?.makeKey(); window?.makeFirstResponder(self)
            let point = CGPoint(x: position.x - contentOrigin.x, y: position.y - contentOrigin.y)
            selectedID = nil
            if tool == .select {
                if let annotation = document.hit(at: point) {
                    selectedID = annotation.id; style = annotation.style; toolbar.setStyle(style)
                    if event.clickCount == 2, annotation.tool == .text { beginText(annotation); return }
                    moveOriginal = annotation; draft = annotation; annotationOrigin = point
                }
            } else if tool == .text {
                let rect = CGRect(x: point.x, y: max(-annotationOffset.y, point.y - style.fontSize * 1.4),
                                  width: min(280, selection.width - annotationOffset.x - point.x),
                                  height: min(point.y + annotationOffset.y, style.fontSize * 1.4))
                beginText(Annotation(tool: .text, points: [], style: style, textRect: rect))
            } else {
                draft = Annotation(tool: tool, points: [point, point], style: style)
                annotationOrigin = point
            }
            changed(); return
        }
        guard onBeginSelection?() == true else { return }
        window?.makeKey()
        window?.makeFirstResponder(self)
        dragOrigin = convert(event.locationInWindow, from: nil)
        selection = nil
        toolbar.isHidden = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if areaResize != nil { resizeSelection(with: event); return }
        if areaDrag != nil { moveSelection(with: event); return }
        if annotationOrigin != nil { updateAnnotation(event); return }
        guard let dragOrigin, !isExporting else { return }
        selection = SelectionGeometry.rectangle(from: dragOrigin,
                                                to: convert(event.locationInWindow, from: nil), in: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if areaResize != nil {
            resizeSelection(with: event); areaResize = nil
            if let selection { onResizeSelection?(selection) }
            cursorUpdate(with: event); needsDisplay = true
            return
        }
        if areaDrag != nil {
            moveSelection(with: event)
            areaDrag = nil
            if let selection { onMoveSelection?(selection) }
            cursorUpdate(with: event); needsDisplay = true
            return
        }
        if annotationOrigin != nil {
            updateAnnotation(event)
            if let draft { document.commit(draft) }
            cancelGesture(); changed(); return
        }
        guard let dragOrigin, !isExporting else { return }
        self.dragOrigin = nil
        let rectangle = SelectionGeometry.rectangle(from: dragOrigin,
                                                     to: convert(event.locationInWindow, from: nil), in: bounds)
        selection = rectangle.width > 0 && rectangle.height > 0 ? rectangle : nil
        needsDisplay = true
        if let selection { onSelect?(selection) }
    }

    func showToolbar() {
        guard let selection else { return }
        var usableBounds = bounds
        if let screen = window?.screen {
            usableBounds = screen.visibleFrame.offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY)
        }
        toolbar.frame = SelectionGeometry.toolbarFrame(selection: selection,
                                                        size: CaptureToolbar.preferredSize, bounds: usableBounds)
        toolbar.movementBounds = usableBounds
        toolbar.isHidden = false
        window?.invalidateCursorRects(for: self)
    }

    func clearAnnotations() {
        guard !isExporting else { return }
        cancelText(); cancelGesture(); selectedID = nil
        document.reset()
        changed()
    }

    func clearSelection() {
        restoreTemporaryTool()
        areaResize = nil; annotationOffset = .zero
        areaDrag = nil
        cancelText(); cancelGesture(); selectedID = nil
        selection = nil
        dragOrigin = nil
        toolbar.isHidden = true
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if handleToolShortcut(event) { return }
        if event.keyCode == 53 {
            if let areaResize {
                selection = areaResize.selection; toolbar.frame = areaResize.toolbar; annotationOffset = areaResize.offset
                self.areaResize = nil
                window?.invalidateCursorRects(for: self); changed(); return
            }
            if let areaDrag {
                selection = areaDrag.selection; toolbar.frame = areaDrag.toolbar
                self.areaDrag = nil
                window?.invalidateCursorRects(for: self); changed(); return
            }
            if annotationOrigin != nil { cancelGesture(); changed(); return }
            if dragOrigin != nil { dragOrigin = nil; selection = nil; changed(); return }
            if selectedID != nil { selectedID = nil; changed(); return }
            onCancel?(); return
        }
        if event.keyCode == 51 || event.keyCode == 117, let selectedID, !isExporting {
            document.delete(selectedID); self.selectedID = nil; changed(); return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if handleToolShortcut(event) { return }
        super.keyUp(with: event)
    }

    // Called by the panel too, so toolbar focus does not swallow these shortcuts.
    func handleToolShortcut(_ event: NSEvent) -> Bool {
        if event.type == .keyUp, event.keyCode == 49, toolBeforeSpace != nil {
            restoreTemporaryTool()
            return true
        }
        guard event.type == .keyDown, selection != nil, dragOrigin == nil,
              !isExporting, textEditor == nil else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 49:
            if !event.isARepeat, toolBeforeSpace == nil {
                cancelGesture()
                toolBeforeSpace = tool
                updateTool(.select)
            }
            return true
        case 48:
            if !event.isARepeat {
                let tools = AnnotationTool.allCases
                let index = tools.firstIndex(of: toolBeforeSpace ?? tool)!
                changeTool(tools[(index + 1) % tools.count])
            }
            return true
        default: return false
        }
    }

    func restoreTemporaryTool() {
        guard let previous = toolBeforeSpace else { return }
        toolBeforeSpace = nil
        updateTool(previous)
    }

    private func changeTool(_ newTool: AnnotationTool) {
        guard !isExporting else { return }
        commitText(); cancelGesture(); selectedID = nil
        if toolBeforeSpace != nil {
            toolBeforeSpace = newTool
            updateTool(.select)
        } else {
            updateTool(newTool)
        }
    }

    private func updateTool(_ newTool: AnnotationTool) {
        tool = newTool
        toolbar.setTool(newTool)
        changed()
        window?.invalidateCursorRects(for: self)
        toolCursor.set()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // The text view keeps native text copy, selection, input-method and undo semantics.
        if textEditor != nil { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command || modifiers == [.command, .shift] else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": if modifiers.contains(.shift) { redoAnnotation() } else { undoAnnotation() }; return true
        case "c": onCopy?(); return true
        case "s": onSave?(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    func prepareForExport() -> Bool {
        guard annotationOrigin == nil, dragOrigin == nil, areaDrag == nil, areaResize == nil else { return false }
        commitText(); selectedID = nil; changed()
        return true
    }

    private func resizeSelection(with event: NSEvent) {
        guard let areaResize, !isExporting else { return }
        let point = convert(event.locationInWindow, from: nil)
        let original = areaResize.selection
        let right = min(bounds.maxX, max(original.minX + min(16, original.width), original.maxX + point.x - areaResize.start.x))
        let bottom = max(bounds.minY, min(original.maxY - min(16, original.height), original.minY + point.y - areaResize.start.y))
        let rectangle = CGRect(x: original.minX, y: bottom, width: right - original.minX, height: original.maxY - bottom)
        selection = rectangle
        annotationOffset = CGPoint(x: areaResize.offset.x, y: areaResize.offset.y + original.minY - bottom)
        toolbar.frame = SelectionGeometry.resizedToolbar(original: areaResize.toolbar, from: original,
                                                         to: rectangle, bounds: toolbar.movementBounds ?? bounds)
        window?.invalidateCursorRects(for: self); needsDisplay = true
    }

    private func moveSelection(with event: NSEvent) {
        guard let areaDrag, !isExporting else { return }
        let point = convert(event.locationInWindow, from: nil)
        let original = areaDrag.selection
        let origin = CGPoint(x: min(max(original.minX + point.x - areaDrag.start.x, bounds.minX), bounds.maxX - original.width),
                             y: min(max(original.minY + point.y - areaDrag.start.y, bounds.minY), bounds.maxY - original.height))
        selection = CGRect(origin: origin, size: original.size)
        let limit = toolbar.movementBounds ?? bounds
        toolbar.frame.origin = CGPoint(
            x: min(max(areaDrag.toolbar.minX + origin.x - original.minX, limit.minX), max(limit.minX, limit.maxX - toolbar.frame.width)),
            y: min(max(areaDrag.toolbar.minY + origin.y - original.minY, limit.minY), max(limit.minY, limit.maxY - toolbar.frame.height)))
        window?.invalidateCursorRects(for: self)
        NSCursor.closedHand.set(); needsDisplay = true
    }

    private func updateAnnotation(_ event: NSEvent) {
        guard !isExporting, let selection, let origin = annotationOrigin else { return }
        let previousBounds = draft?.bounds
        let position = convert(event.locationInWindow, from: nil)
        var point = CGPoint(x: position.x - contentOrigin.x, y: position.y - contentOrigin.y)
        if let original = moveOriginal {
            draft = original.moved(by: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
        } else if var annotation = draft {
            point = SelectionGeometry.clamped(point, to: CGRect(x: -annotationOffset.x, y: -annotationOffset.y,
                                                               width: selection.width, height: selection.height))
            if annotation.tool == .pen {
                if annotation.points.last != point { annotation.points.append(point) }
            } else { annotation.points = [origin, point] }
            draft = annotation
        }
        if let draft {
            let margin = max(20, draft.style.width * 4)
            let dirty = (previousBounds ?? draft.bounds).union(draft.bounds).insetBy(dx: -margin, dy: -margin)
                .offsetBy(dx: contentOrigin.x, dy: contentOrigin.y)
            setNeedsDisplay(dirty.intersection(selection.insetBy(dx: -1, dy: -1)))
        }
    }

    private func cancelGesture() { draft = nil; moveOriginal = nil; annotationOrigin = nil }
    private func changed() {
        toolbar.updateHistory(canUndo: document.canUndo, canRedo: document.canRedo)
        toolbar.setContextualTool(document.annotations.first(where: { $0.id == selectedID })?.tool ?? tool)
        needsDisplay = true
    }
    private func changeStyle(_ newStyle: AnnotationStyle) {
        guard !isExporting else { return }
        commitText(); cancelGesture(); style = newStyle
        if var selected = document.annotations.first(where: { $0.id == selectedID }) {
            selected.style = newStyle
            if selected.tool == .text {
                let top = selected.textRect.maxY
                let height = min(top + annotationOffset.y, AnnotationRenderer.textHeight(selected.text, width: selected.textRect.width, style: newStyle))
                selected.textRect.origin.y = top - height
                selected.textRect.size.height = height
            }
            document.commit(selected)
        }
        changed()
    }
    private func undoAnnotation() {
        guard !isExporting else { return }
        commitText(); cancelGesture(); selectedID = nil; document.undo(); changed()
    }
    private func redoAnnotation() {
        guard !isExporting else { return }
        commitText(); cancelGesture(); selectedID = nil; document.redo(); changed()
    }

    private func beginText(_ annotation: Annotation) {
        guard let selection, annotation.textRect.width > 0, annotation.textRect.height > 0 else { return }
        restoreTemporaryTool()
        editingText = annotation
        let editor = AnnotationTextEditor(frame: annotation.textRect.offsetBy(dx: contentOrigin.x, dy: contentOrigin.y))
        editor.isRichText = false; editor.drawsBackground = false; editor.allowsUndo = true
        editor.textContainerInset = .zero; editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isHorizontallyResizable = false; editor.isVerticallyResizable = false
        editor.typingAttributes = AnnotationRenderer.attributes(for: annotation.style)
        editor.textStorage?.setAttributedString(NSAttributedString(string: annotation.text, attributes: editor.typingAttributes))
        editor.insertionPointColor = annotation.style.color.nsColor
        editor.delegate = self
        editor.onCommit = { [weak self] in self?.commitText() }
        editor.onCancel = { [weak self] in self?.cancelText() }
        textEditor = editor; addSubview(editor); window?.makeFirstResponder(editor)
        resizeTextEditor(); needsDisplay = true
    }

    func textDidChange(_ notification: Notification) { resizeTextEditor() }

    private func resizeTextEditor() {
        guard let editor = textEditor, let annotation = editingText, let selection,
              let layout = editor.layoutManager, let container = editor.textContainer else { return }
        container.containerSize = CGSize(width: annotation.textRect.width, height: 10000)
        layout.ensureLayout(for: container)
        let height = min(annotation.textRect.maxY + annotationOffset.y, max(annotation.style.fontSize * 1.4, layout.usedRect(for: container).height))
        editor.frame = CGRect(x: annotation.textRect.minX + contentOrigin.x,
                              y: annotation.textRect.maxY + contentOrigin.y - height,
                              width: annotation.textRect.width, height: height)
    }

    private func commitText() {
        guard let editor = textEditor, var annotation = editingText, let selection else { return }
        annotation.text = editor.string
        annotation.textRect = editor.frame.offsetBy(dx: -contentOrigin.x, dy: -contentOrigin.y)
        document.commit(annotation)
        closeTextEditor(); changed()
    }
    private func cancelText() { closeTextEditor(); changed() }
    private func closeTextEditor() {
        textEditor?.delegate = nil; textEditor?.removeFromSuperview()
        textEditor = nil; editingText = nil
        window?.makeFirstResponder(self)
    }
}
