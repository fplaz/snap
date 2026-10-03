import XCTest
import AppKit

final class AnnotationInteractionTests: XCTestCase {
    @MainActor
    private func fixture() throws -> (NSWindow, CaptureOverlayView, AnnotationDocument) {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let document = AnnotationDocument()
        let view = CaptureOverlayView(snapshot: DisplaySnapshot(displayID: 1,
                                      frame: CGRect(x: 0, y: 0, width: 400, height: 300), image: image), document: document)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.onBeginSelection = { true }
        view.onSelect = { _ in view.showToolbar() }
        view.mouseDown(with: mouse(.leftMouseDown, x: 20, y: 20))
        view.mouseUp(with: mouse(.leftMouseUp, x: 350, y: 260))
        return (window, view, document)
    }

    @MainActor
    func testDrawingDoesNotReplaceCaptureAndIsOneUndoOperation() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        let selection = view.selection
        view.mouseDown(with: mouse(.leftMouseDown, x: 50, y: 50))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 100, y: 70))
        view.mouseUp(with: mouse(.leftMouseUp, x: 150, y: 80))
        XCTAssertEqual(view.selection, selection)
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertEqual(document.annotations.first?.points.last, CGPoint(x: 130, y: 60))
        document.undo(); XCTAssertTrue(document.annotations.isEmpty)
    }

    @MainActor
    func testEscapeCancelsGestureBeforeCancelingCapture() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        var canceled = false
        view.onCancel = { canceled = true }
        view.mouseDown(with: mouse(.leftMouseDown, x: 50, y: 50))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 100, y: 80))
        XCTAssertFalse(view.prepareForExport())
        view.keyDown(with: escape())
        view.mouseUp(with: mouse(.leftMouseUp, x: 120, y: 90))
        XCTAssertFalse(canceled); XCTAssertTrue(document.annotations.isEmpty)
        view.keyDown(with: escape()); XCTAssertTrue(canceled)
    }

    @MainActor
    func testOutputCommitsPendingMultilineTextAndCancelRestoresPriorValue() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        view.toolbar.onTool?(.text)
        view.mouseDown(with: mouse(.leftMouseDown, x: 50, y: 200))
        let editor = try XCTUnwrap(view.subviews.compactMap { $0 as? AnnotationTextEditor }.first)
        editor.insertText("Hello\n世界", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(view.prepareForExport())
        XCTAssertEqual(document.annotations.first?.text, "Hello\n世界")
        let annotation = try XCTUnwrap(document.annotations.first)
        view.toolbar.onTool?(.select)
        view.mouseDown(with: mouse(.leftMouseDown, x: annotation.textRect.minX + 25,
                             y: annotation.textRect.maxY + 15, clicks: 2))
        let edit = try XCTUnwrap(view.subviews.compactMap { $0 as? AnnotationTextEditor }.first)
        edit.insertText("Changed", replacementRange: NSRange(location: 0, length: edit.string.utf16.count))
        edit.keyDown(with: escape())
        XCTAssertEqual(document.annotations.first?.text, "Hello\n世界")
        XCTAssertNotNil(view.selection)
    }

    @MainActor
    func testExportingBlocksEditingAndResetRemovesTextEditor() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        view.isExporting = true
        view.mouseDown(with: mouse(.leftMouseDown, x: 50, y: 50))
        view.mouseUp(with: mouse(.leftMouseUp, x: 100, y: 100))
        XCTAssertTrue(document.annotations.isEmpty)
        view.isExporting = false
        view.toolbar.onTool?(.text)
        view.mouseDown(with: mouse(.leftMouseDown, x: 50, y: 200))
        XCTAssertTrue(view.subviews.contains { $0 is AnnotationTextEditor })
        view.clearSelection()
        XCTAssertFalse(view.subviews.contains { $0 is AnnotationTextEditor })
        XCTAssertNil(view.selection)
    }

    @MainActor
    func testIncreasingSelectedTextSizeExpandsItsLayoutAndUndoRestoresIt() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        let original = Annotation(tool: .text, points: [], style: AnnotationStyle(fontSize: 16),
                                  text: "First line\nSecond line", textRect: CGRect(x: 30, y: 150, width: 200, height: 40))
        document.commit(original)
        view.toolbar.onTool?(.select)
        view.mouseDown(with: mouse(.leftMouseDown, x: 60, y: 200))
        view.mouseUp(with: mouse(.leftMouseUp, x: 60, y: 200))
        view.toolbar.onStyle?(AnnotationStyle(fontSize: 32))
        let resized = try XCTUnwrap(document.annotations.first)
        XCTAssertGreaterThan(resized.textRect.height, original.textRect.height)
        XCTAssertEqual(resized.textRect.maxY, original.textRect.maxY)
        document.undo(); XCTAssertEqual(document.annotations, [original])
    }

    @MainActor
    func testToolbarDragClampsWithoutChangingCaptureOrHistory() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        let crop = view.selection
        let toolbar = view.toolbar
        toolbar.movementBounds = CGRect(x: 0, y: 0, width: 600, height: 300)
        toolbar.frame.origin = CGPoint(x: 50, y: 50)
        toolbar.mouseDown(with: mouse(.leftMouseDown, x: 65, y: 76))
        toolbar.mouseDragged(with: mouse(.leftMouseDragged, x: 1000, y: 1000))
        toolbar.mouseUp(with: mouse(.leftMouseUp, x: 1000, y: 1000))
        XCTAssertEqual(toolbar.frame.maxX, 600)
        XCTAssertEqual(toolbar.frame.maxY, 300)
        XCTAssertEqual(view.selection, crop)
        XCTAssertFalse(document.canUndo)
        toolbar.setExporting(true)
        let frame = toolbar.frame
        toolbar.mouseDown(with: mouse(.leftMouseDown, x: 200, y: 200))
        toolbar.mouseDragged(with: mouse(.leftMouseDragged, x: 50, y: 50))
        XCTAssertEqual(toolbar.frame, frame)
    }

    @MainActor
    func testContextualSizeMenusRetainIndependentValues() async throws {
        let toolbar = CaptureToolbar()
        let menus = toolbar.subviews.compactMap { $0 as? NSPopUpButton }
        let tool = try XCTUnwrap(menus.first { $0.accessibilityLabel() == "Drawing tool" })
        let width = try XCTUnwrap(menus.first { $0.accessibilityLabel() == "Line width" })
        let size = try XCTUnwrap(menus.first { $0.accessibilityLabel() == "Text size" })
        toolbar.setStyle(AnnotationStyle(width: 8, fontSize: 16))
        tool.selectItem(at: AnnotationTool.allCases.firstIndex(of: .text)!)
        tool.sendAction(tool.action!, to: tool.target)
        XCTAssertTrue(width.isHidden); XCTAssertFalse(size.isHidden)
        var style: AnnotationStyle?
        toolbar.onStyle = { style = $0 }
        size.selectItem(at: 2); size.sendAction(size.action!, to: size.target)
        XCTAssertEqual(style?.fontSize, 32)
        XCTAssertEqual(style?.width, 8)
        tool.selectItem(at: AnnotationTool.allCases.firstIndex(of: .pen)!)
        tool.sendAction(tool.action!, to: tool.target)
        XCTAssertFalse(width.isHidden); XCTAssertTrue(size.isHidden)
        XCTAssertEqual(width.indexOfSelectedItem, 2)
    }

    @MainActor
    func testClearingAnnotationsPreservesSelectionAndToolbar() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        let selection = view.selection
        let toolbarFrame = view.toolbar.frame
        document.commit(Annotation(tool: .line, points: [CGPoint(x: 30, y: 30), CGPoint(x: 80, y: 80)]))
        view.toolbar.onTool?(.text)
        view.mouseDown(with: mouse(.leftMouseDown, x: 50, y: 200))
        let editor = try XCTUnwrap(view.subviews.compactMap { $0 as? AnnotationTextEditor }.first)
        editor.insertText("Pending text", replacementRange: NSRange(location: 0, length: 0))
        view.clearAnnotations()
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertFalse(document.canUndo); XCTAssertFalse(document.canRedo)
        XCTAssertEqual(view.selection, selection)
        XCTAssertEqual(view.toolbar.frame, toolbarFrame)
        XCTAssertFalse(view.toolbar.isHidden)
        XCTAssertFalse(view.subviews.contains { $0 is AnnotationTextEditor })
        XCTAssertTrue(view.prepareForExport())
        XCTAssertTrue(document.annotations.isEmpty)
    }

    private func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }
    private func escape() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                        isARepeat: false, keyCode: 53)!
    }
}
