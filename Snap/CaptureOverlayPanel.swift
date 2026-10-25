import AppKit

final class CaptureOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if (event.type == .keyDown || event.type == .keyUp),
           let overlay = contentView as? CaptureOverlayView,
           overlay.handleToolShortcut(event) { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        (contentView as? CaptureOverlayView)?.restoreTemporaryTool()
        super.resignKey()
    }

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovable = false
        acceptsMouseMovedEvents = true
    }
}

/// An ordinary window: deactivation leaves the screenshot available without blocking the desktop.
@MainActor
final class ScreenshotEditorWindow: NSWindow, NSWindowDelegate {
    let canvas: CaptureOverlayView
    var onClose: (() -> Void)?
    private var screenshotScroll: NSScrollView?
    private var copyToast: NSView?
    private var toastDismissal: Task<Void, Never>?

    init(canvas: CaptureOverlayView) {
        self.canvas = canvas
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let size = CGSize(width: min(max(920, canvas.frame.width + 96), available.width * 0.92),
                          height: min(max(420, canvas.frame.height + 148), available.height * 0.85))
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Screenshot Editor"
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        minSize = CGSize(width: 860, height: 320)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        appearance = NSAppearance(named: .darkAqua)
        delegate = self

        let root = NSView(frame: CGRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        contentView = root

        // Share a single header row with the native window controls.
        let toolbar = canvas.toolbar
        toolbar.frame = CGRect(x: 84, y: size.height - 52, width: size.width - 96, height: 52)
        toolbar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(toolbar)

        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: size.width, height: size.height - 52))
        scroll.autoresizingMask = [.width, .height]
        scroll.contentView = CenteredScreenshotClipView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.backgroundColor = NSColor(white: 0.13, alpha: 1)
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05
        scroll.maxMagnification = 4
        root.addSubview(scroll)
        let stage = NSView(frame: canvas.frame)
        stage.addSubview(canvas)
        scroll.documentView = stage
        screenshotScroll = scroll
        let divider = NSBox(frame: CGRect(x: 0, y: size.height - 53, width: size.width, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width, .minYMargin]
        root.addSubview(divider)
        fitScreenshot()
        center()
        layoutWindowControls()
        makeFirstResponder(canvas)
    }

    private func fitScreenshot() {
        guard let scroll = screenshotScroll, let stage = scroll.documentView else { return }
        scroll.tile()
        let imageSize = canvas.bounds.size
        let fit = max(scroll.minMagnification, min(1,
            min((scroll.contentSize.width - 96) / imageSize.width,
                (scroll.contentSize.height - 96) / imageSize.height)))
        // Workspace padding stays at least 48 screen points when fitting; exports stay unchanged.
        let padding = 48 / fit
        stage.frame.size = CGSize(width: imageSize.width + padding * 2, height: imageSize.height + padding * 2)
        canvas.frame.origin = CGPoint(x: padding, y: padding)
        scroll.magnification = fit
        let viewport = scroll.contentView.bounds.size
        scroll.contentView.scroll(to: CGPoint(x: (stage.frame.width - viewport.width) / 2,
                                              y: (stage.frame.height - viewport.height) / 2))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func layoutWindowControls() {
        guard let root = contentView else { return }
        for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = standardWindowButton(type), let parent = button.superview else { continue }
            button.setFrameOrigin(parent.convert(CGPoint(x: 14 + CGFloat(index) * 20,
                y: root.bounds.maxY - 26 - button.frame.height / 2), from: root))
        }
    }

    func windowDidResize(_ notification: Notification) {
        fitScreenshot()
        layoutWindowControls()
    }

    func windowDidBecomeKey(_ notification: Notification) { layoutWindowControls() }

    func requestClose() {
        guard attachedSheet == nil, !canvas.isExporting, canvas.prepareForExport() else { return }
        let alert = NSAlert()
        alert.messageText = "Finish without saving?"
        alert.informativeText = "The screenshot and its annotations will be discarded."
        let keepEditing = alert.addButton(withTitle: "Keep Editing")
        keepEditing.keyEquivalent = "\u{1b}"
        let discard = alert.addButton(withTitle: "Finish Without Saving")
        // AppKit's destructive style forces red text; draw the requested solid fill instead.
        discard.isBordered = false
        discard.wantsLayer = true
        discard.layer?.backgroundColor = NSColor.systemRed.cgColor
        discard.layer?.cornerRadius = 14
        discard.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        discard.contentTintColor = .white
        discard.attributedTitle = NSAttributedString(string: discard.title, attributes: [
            .foregroundColor: NSColor.white,
            .font: discard.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ])
        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn else { return }
            if let onClose = self.onClose { onClose() }
            else { self.close() }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestClose()
        return false
    }

    func showCopyToast() {
        guard let root = contentView else { return }
        toastDismissal?.cancel()
        copyToast?.removeFromSuperview()
        let toast = ScreenshotCopyToast()
        toast.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24)
        ])
        copyToast = toast
        NSAccessibility.post(element: root, notification: .announcementRequested,
            userInfo: [.announcement: "Screenshot copied", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        toastDismissal = Task { @MainActor [weak self, weak toast] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            toast?.removeFromSuperview()
            self?.copyToast = nil
            self?.toastDismissal = nil
        }
    }

    override func sendEvent(_ event: NSEvent) {
        let isPointerEvent = [.mouseMoved, .mouseEntered, .cursorUpdate, .leftMouseDown, .leftMouseUp].contains(event.type)
        let isInHeader = contentView.map {
            $0.convert(event.locationInWindow, from: nil).y >= $0.bounds.maxY - 52
        } ?? false
        defer {
            if isPointerEvent && isInHeader { NSCursor.arrow.set() }
        }
        if (event.type == .keyDown || event.type == .keyUp), canvas.handleToolShortcut(event) { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if canvas.performKeyEquivalent(with: event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func resignKey() {
        canvas.restoreTemporaryTool()
        super.resignKey()
    }

    func windowWillClose(_ notification: Notification) {
        toastDismissal?.cancel()
        toastDismissal = nil
        copyToast?.removeFromSuperview()
        copyToast = nil
        onClose?()
    }
}

private final class ScreenshotCopyToast: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        let label = NSTextField(labelWithString: "Screenshot copied")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Center smaller screenshots instead of pinning them to the bottom-left corner.
private final class CenteredScreenshotClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return result }
        if documentView.frame.width < result.width {
            result.origin.x = (documentView.frame.width - result.width) / 2
        }
        if documentView.frame.height < result.height {
            result.origin.y = (documentView.frame.height - result.height) / 2
        }
        return result
    }
}
