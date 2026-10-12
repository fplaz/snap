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
