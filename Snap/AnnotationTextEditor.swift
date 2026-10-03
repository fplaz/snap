import AppKit

final class AnnotationTextEditor: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        if event.keyCode == 36, event.modifierFlags.contains(.command) { onCommit?(); return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36, event.modifierFlags.contains(.command) { onCommit?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}
