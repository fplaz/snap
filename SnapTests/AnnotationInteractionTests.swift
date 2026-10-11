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
    func testDefaultToolCreatesRectangleAndToolbarShowsRectangle() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        let popup = try XCTUnwrap(view.toolbar.subviews.compactMap { $0 as? NSPopUpButton }
            .first { $0.accessibilityLabel() == "Drawing tool" })
        XCTAssertEqual(popup.indexOfSelectedItem, AnnotationTool.allCases.firstIndex(of: .rectangle))
        view.mouseDown(with: mouse(.leftMouseDown, x: 70, y: 100))
        view.mouseUp(with: mouse(.leftMouseUp, x: 120, y: 130))
        XCTAssertEqual(document.annotations.first?.tool, .rectangle)
    }

    @MainActor
    func testWholeCanvasDragStartsNearEitherSideOfBorderWithoutDrawing() async throws {
        for startX: CGFloat in [14, 26] {
            let (window, view, document) = try fixture()
            defer { window.close() }
            let original = try XCTUnwrap(view.selection)
            view.mouseDown(with: mouse(.leftMouseDown, x: startX, y: 160))
            view.mouseUp(with: mouse(.leftMouseUp, x: startX + 15, y: 170))
            XCTAssertEqual(view.selection, original.offsetBy(dx: 15, dy: 10))
            XCTAssertTrue(document.annotations.isEmpty)
        }
    }

    @MainActor
    func testCornerResizeKeepsAnnotationsAtScreenPositionAndUpdatesExportCoordinates() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        view.mouseDown(with: mouse(.leftMouseDown, x: 70, y: 100))
        view.mouseUp(with: mouse(.leftMouseUp, x: 120, y: 130))
        let annotations = document.annotations
        let original = try XCTUnwrap(view.selection)
        var resized: CGRect?
        view.onResizeSelection = { resized = $0 }
        view.mouseDown(with: mouse(.leftMouseDown, x: original.maxX - 2, y: original.minY + 2))
        XCTAssertFalse(view.prepareForExport())
        view.mouseDragged(with: mouse(.leftMouseDragged, x: original.maxX - 102, y: original.minY + 62))
        view.mouseUp(with: mouse(.leftMouseUp, x: original.maxX - 102, y: original.minY + 62))
        XCTAssertEqual(view.selection, CGRect(x: 20, y: 80, width: 230, height: 180))
        XCTAssertEqual(resized, view.selection)
        XCTAssertEqual(document.annotations, annotations)
        XCTAssertEqual(view.exportAnnotations, annotations.map { $0.moved(by: CGPoint(x: 0, y: -60)) })
        XCTAssertTrue(view.prepareForExport())
        // Growing back restores the export coordinates without modifying the document or undo history.
        view.mouseDown(with: mouse(.leftMouseDown, x: 248, y: 82))
        view.mouseUp(with: mouse(.leftMouseUp, x: 348, y: 22))
        XCTAssertEqual(view.selection, original)
        XCTAssertEqual(view.exportAnnotations, annotations)
    }

    @MainActor
    func testCornerResizeEscapeRestoresCanvasToolbarAndAnnotationOffset() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        let original = try XCTUnwrap(view.selection)
        let toolbar = view.toolbar.frame
        view.mouseDown(with: mouse(.leftMouseDown, x: 348, y: 22))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: -100, y: 1000))
        XCTAssertEqual(view.selection?.size, CGSize(width: 16, height: 16))
        view.keyDown(with: escape())
        view.mouseUp(with: mouse(.leftMouseUp, x: -100, y: 1000))
        XCTAssertEqual(view.selection, original)
        XCTAssertEqual(view.toolbar.frame, toolbar)
    }

    @MainActor
    func testBorderDragMovesSelectionAndToolbarWithoutChangingAnnotations() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        view.mouseDown(with: mouse(.leftMouseDown, x: 70, y: 80))
        view.mouseUp(with: mouse(.leftMouseUp, x: 120, y: 110))
        let annotations = document.annotations
        let original = try XCTUnwrap(view.selection)
        let toolbar = view.toolbar.frame
        var moved: CGRect?
        view.onMoveSelection = { moved = $0 }
        view.mouseDown(with: mouse(.leftMouseDown, x: original.maxX, y: 140))
        XCTAssertFalse(view.prepareForExport())
        view.mouseDragged(with: mouse(.leftMouseDragged, x: original.maxX + 15, y: 150))
        view.mouseUp(with: mouse(.leftMouseUp, x: original.maxX + 15, y: 150))
        XCTAssertEqual(view.selection, original.offsetBy(dx: 15, dy: 10))
        XCTAssertEqual(moved, view.selection)
        XCTAssertEqual(document.annotations, annotations)
        XCTAssertEqual(view.toolbar.frame, toolbar.offsetBy(dx: 15, dy: 10))
        XCTAssertTrue(view.prepareForExport())
    }

    @MainActor
    func testBorderDragClampsToDisplayAndEscapeRestoresSelection() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        let original = try XCTUnwrap(view.selection)
        let toolbar = view.toolbar.frame
        view.mouseDown(with: mouse(.leftMouseDown, x: original.maxX, y: 140))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 1000, y: 1000))
        XCTAssertEqual(view.selection?.maxX, view.bounds.maxX)
        XCTAssertEqual(view.selection?.maxY, view.bounds.maxY)
        view.keyDown(with: escape())
        view.mouseUp(with: mouse(.leftMouseUp, x: 1000, y: 1000))
        XCTAssertEqual(view.selection, original)
        XCTAssertEqual(view.toolbar.frame, toolbar)
    }

    @MainActor
    func testNonKeyOverlayAcceptsFirstClickAndCreatesSelectionWithFirstDrag() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        view.clearSelection()
        XCTAssertFalse(window.isKeyWindow)
        let down = mouse(.leftMouseDown, x: 30, y: 40)
        XCTAssertTrue(view.acceptsFirstMouse(for: down))
        view.mouseDown(with: down)
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 180, y: 160))
        view.mouseUp(with: mouse(.leftMouseUp, x: 180, y: 160))
        XCTAssertEqual(view.selection, CGRect(x: 30, y: 40, width: 150, height: 120))
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
