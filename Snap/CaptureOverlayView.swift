import AppKit

@MainActor
final class CaptureOverlayView: NSView, NSTextViewDelegate {
    private let snapshot: DisplaySnapshot
    private let screenshot: NSImage
    private var dragOrigin: CGPoint?
    private(set) var selection: CGRect?
    private var tracking: NSTrackingArea?
    let toolbar = CaptureToolbar()
    let document: AnnotationDocument
    private var tool: AnnotationTool = .pen
    private var style = AnnotationStyle()
    private var selectedID: UUID?
    private var draft: Annotation?
    private var moveOriginal: Annotation?
    private var annotationOrigin: CGPoint?
    private var textEditor: AnnotationTextEditor?
    private var editingText: Annotation?

    var onBeginSelection: (() -> Bool)?
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onStartOver: (() -> Void)?
    var isExporting = false {
        didSet { toolbar.setExporting(isExporting) }
    }

    init(snapshot: DisplaySnapshot, document: AnnotationDocument) {
        self.snapshot = snapshot
        self.document = document
        screenshot = NSImage(cgImage: snapshot.image, size: snapshot.logicalSize)
        super.init(frame: CGRect(origin: .zero, size: snapshot.logicalSize))
        toolbar.isHidden = true
        addSubview(toolbar)
        toolbar.onTool = { [weak self] tool in
            guard let self else { return }
            self.commitText(); self.cancelGesture(); self.selectedID = nil; self.tool = tool; self.changed()
        }
        toolbar.onStyle = { [weak self] style in self?.changeStyle(style) }
        toolbar.onUndo = { [weak self] in self?.undoAnnotation() }
        toolbar.onRedo = { [weak self] in self?.redoAnnotation() }
        toolbar.onCopy = { [weak self] in self?.onCopy?() }
        toolbar.onSave = { [weak self] in self?.onSave?() }
        toolbar.onCancel = { [weak self] in self?.onCancel?() }
        toolbar.onStartOver = { [weak self] in self?.onStartOver?() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .cursorUpdate, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if !toolbar.isHidden {
            addCursorRect(toolbar.frame, cursor: .arrow)
            addCursorRect(CGRect(x: toolbar.frame.minX, y: toolbar.frame.minY,
                                 width: 28, height: toolbar.frame.height), cursor: .openHand)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !toolbar.isHidden, toolbar.frame.contains(point) {
            if point.x < toolbar.frame.minX + 28 { NSCursor.openHand.set() }
            else { NSCursor.arrow.set() }
        }
        else { NSCursor.crosshair.set() }
    }

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
            let transform = AffineTransform(translationByX: selection.minX, byY: selection.minY)
            (transform as NSAffineTransform).concat()
            var annotations = document.annotations.filter { $0.id != editingText?.id && $0.id != draft?.id }
            if let draft { annotations.append(draft) }
            AnnotationRenderer.draw(annotations, in: CGRect(origin: .zero, size: selection.size))
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
            guard selection.contains(position) else { return }
            window?.makeKey(); window?.makeFirstResponder(self)
            let point = CGPoint(x: position.x - selection.minX, y: position.y - selection.minY)
            selectedID = nil
            if tool == .select {
                if let annotation = document.hit(at: point) {
                    selectedID = annotation.id; style = annotation.style; toolbar.setStyle(style)
                    if event.clickCount == 2, annotation.tool == .text { beginText(annotation); return }
                    moveOriginal = annotation; draft = annotation; annotationOrigin = point
                }
            } else if tool == .text {
                let rect = CGRect(x: point.x, y: max(0, point.y - style.fontSize * 1.4),
                                  width: min(280, selection.width - point.x), height: min(point.y, style.fontSize * 1.4))
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
        if annotationOrigin != nil { updateAnnotation(event); return }
        guard let dragOrigin, !isExporting else { return }
        selection = SelectionGeometry.rectangle(from: dragOrigin,
                                                to: convert(event.locationInWindow, from: nil), in: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
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
        cancelText(); cancelGesture(); selectedID = nil
        selection = nil
        dragOrigin = nil
        toolbar.isHidden = true
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
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
        guard annotationOrigin == nil, dragOrigin == nil else { return false }
        commitText(); selectedID = nil; changed()
        return true
    }

    private func updateAnnotation(_ event: NSEvent) {
        guard !isExporting, let selection, let origin = annotationOrigin else { return }
        let previousBounds = draft?.bounds
        let position = convert(event.locationInWindow, from: nil)
        var point = CGPoint(x: position.x - selection.minX, y: position.y - selection.minY)
        if let original = moveOriginal {
            draft = original.moved(by: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
        } else if var annotation = draft {
            point = SelectionGeometry.clamped(point, to: CGRect(origin: .zero, size: selection.size))
            if annotation.tool == .pen {
                if annotation.points.last != point { annotation.points.append(point) }
            } else { annotation.points = [origin, point] }
            draft = annotation
        }
        if let draft {
            let margin = max(20, draft.style.width * 4)
            let dirty = (previousBounds ?? draft.bounds).union(draft.bounds).insetBy(dx: -margin, dy: -margin)
                .offsetBy(dx: selection.minX, dy: selection.minY)
            setNeedsDisplay(dirty.intersection(selection.insetBy(dx: -1, dy: -1)))
        }
    }

    private func cancelGesture() { draft = nil; moveOriginal = nil; annotationOrigin = nil }
    private func changed() {
        toolbar.updateHistory(canUndo: document.canUndo, canRedo: document.canRedo)
        needsDisplay = true
    }
    private func changeStyle(_ newStyle: AnnotationStyle) {
        guard !isExporting else { return }
        commitText(); cancelGesture(); style = newStyle
        if var selected = document.annotations.first(where: { $0.id == selectedID }) {
            selected.style = newStyle
            if selected.tool == .text {
                let top = selected.textRect.maxY
                let height = min(top, AnnotationRenderer.textHeight(selected.text, width: selected.textRect.width, style: newStyle))
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
        editingText = annotation
        let editor = AnnotationTextEditor(frame: annotation.textRect.offsetBy(dx: selection.minX, dy: selection.minY))
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
        let height = min(annotation.textRect.maxY, max(annotation.style.fontSize * 1.4, layout.usedRect(for: container).height))
        editor.frame = CGRect(x: annotation.textRect.minX + selection.minX,
                              y: annotation.textRect.maxY + selection.minY - height,
                              width: annotation.textRect.width, height: height)
    }

    private func commitText() {
        guard let editor = textEditor, var annotation = editingText, let selection else { return }
        annotation.text = editor.string
        annotation.textRect = editor.frame.offsetBy(dx: -selection.minX, dy: -selection.minY)
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
