import XCTest
import AppKit

final class AnnotationInteractionTests: XCTestCase {
    @MainActor
    func testSelectionCanExportImmediatelyWithoutShowingAnnotationToolbar() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        view.clearSelection()
        var selected: CGRect?
        var readyForCopy = false
        view.onSelect = { rectangle in
            selected = rectangle
            readyForCopy = view.prepareForExport()
            view.isExporting = true
        }
        view.mouseDown(with: mouse(.leftMouseDown, x: 180, y: 180))
        view.mouseUp(with: mouse(.leftMouseUp, x: 80, y: 80))
        XCTAssertEqual(selected, CGRect(x: 80, y: 80, width: 100, height: 100))
        XCTAssertTrue(readyForCopy)
        XCTAssertTrue(view.toolbar.isHidden)
        XCTAssertTrue(view.exportAnnotations.isEmpty)
        view.mouseDown(with: mouse(.leftMouseDown, x: 100, y: 100))
        view.mouseUp(with: mouse(.leftMouseUp, x: 150, y: 150))
        XCTAssertTrue(view.exportAnnotations.isEmpty)
    }

    @MainActor
    func testFilledShapesCanBeCreatedMovedAndChangedToOutlinesWithUndo() async throws {
        for tool in [AnnotationTool.rectangle, .ellipse] {
            let (window, view, document) = try fixture()
            defer { window.close() }
            view.toolbar.onTool?(tool)
            let menus = view.toolbar.subviews.compactMap { $0 as? NSPopUpButton }
            let shapeStyle = try XCTUnwrap(menus.first { $0.accessibilityLabel() == "Shape style" })
            let width = try XCTUnwrap(menus.first { $0.accessibilityLabel() == "Line width" })
            XCTAssertFalse(shapeStyle.isHidden)
            XCTAssertTrue(width.isHidden)
            XCTAssertEqual(shapeStyle.indexOfSelectedItem, 1)
            shapeStyle.selectItem(at: 3)
            shapeStyle.sendAction(shapeStyle.action!, to: shapeStyle.target)
            view.mouseDown(with: mouse(.leftMouseDown, x: 80, y: 80))
            view.mouseUp(with: mouse(.leftMouseUp, x: 180, y: 180))
            let original = try XCTUnwrap(document.annotations.first)
            XCTAssertTrue(original.style.isFilled)
            XCTAssertTrue(original.hitTest(CGPoint(x: 110, y: 110)))
            XCTAssertFalse(original.hitTest(CGPoint(x: 40, y: 110)))
            if tool == .ellipse { XCTAssertFalse(original.hitTest(CGPoint(x: 61, y: 61))) }
            view.toolbar.onTool?(.select)
            view.mouseDown(with: mouse(.leftMouseDown, x: 130, y: 130))
            view.mouseUp(with: mouse(.leftMouseUp, x: 140, y: 140))
            let moved = original.moved(by: CGPoint(x: 10, y: 10))
            XCTAssertEqual(document.annotations, [moved])
            XCTAssertFalse(shapeStyle.isHidden)
            XCTAssertEqual(shapeStyle.indexOfSelectedItem, 3)
            shapeStyle.selectItem(at: 2)
            shapeStyle.sendAction(shapeStyle.action!, to: shapeStyle.target)
            let outlined = try XCTUnwrap(document.annotations.first)
            XCTAssertFalse(outlined.style.isFilled)
            XCTAssertEqual(outlined.style.width, 8)
            XCTAssertFalse(outlined.hitTest(CGPoint(x: 120, y: 120)))
            document.undo(); XCTAssertEqual(document.annotations, [moved])
            document.redo(); XCTAssertEqual(document.annotations, [outlined])
            XCTAssertTrue(view.prepareForExport())
            XCTAssertEqual(view.exportAnnotations, [outlined])
        }
    }

    @MainActor
    func testFilledShapeStyleSurvivesOtherToolsAndRestoresSelectedStyle() async throws {
        let toolbar = CaptureToolbar()
        let menus = toolbar.subviews.compactMap { $0 as? NSPopUpButton }
        let shapeStyle = try XCTUnwrap(menus.first { $0.accessibilityLabel() == "Shape style" })
        let width = try XCTUnwrap(menus.first { $0.accessibilityLabel() == "Line width" })
        toolbar.setStyle(AnnotationStyle(width: 8, isFilled: true))
        toolbar.setContextualTool(.pen)
        XCTAssertTrue(shapeStyle.isHidden)
        XCTAssertFalse(width.isHidden)
        var style: AnnotationStyle?
        toolbar.onStyle = { style = $0 }
        width.selectItem(at: 0)
        width.sendAction(width.action!, to: width.target)
        XCTAssertEqual(style?.width, 2)
        toolbar.setContextualTool(.ellipse)
        XCTAssertFalse(shapeStyle.isHidden)
        XCTAssertEqual(shapeStyle.indexOfSelectedItem, 3)
        toolbar.setStyle(AnnotationStyle(width: 4))
        XCTAssertEqual(shapeStyle.indexOfSelectedItem, 1)
        toolbar.setExporting(true)
        XCTAssertFalse(shapeStyle.isEnabled)
    }

    @MainActor
    func testBlurStrengthIsStoredPerAreaAndSelectedEditsCanBeUndone() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        let slider = try XCTUnwrap(view.toolbar.subviews.compactMap { $0 as? NSSlider }.first)
        XCTAssertTrue(slider.isHidden)
        view.toolbar.onTool?(.blur)
        XCTAssertFalse(slider.isHidden)
        XCTAssertEqual(slider.doubleValue, 3.5)
        slider.doubleValue = 6
        slider.sendAction(slider.action!, to: slider.target)
        view.mouseDown(with: mouse(.leftMouseDown, x: 80, y: 80))
        view.mouseUp(with: mouse(.leftMouseUp, x: 160, y: 160))
        let first = try XCTUnwrap(document.annotations.first)
        XCTAssertEqual(first.style.blurRadius, 6)
        slider.doubleValue = 2
        slider.sendAction(slider.action!, to: slider.target)
        view.mouseDown(with: mouse(.leftMouseDown, x: 200, y: 80))
        view.mouseUp(with: mouse(.leftMouseUp, x: 280, y: 160))
        XCTAssertEqual(document.annotations.map(\.style.blurRadius), [6, 2])
        view.toolbar.onTool?(.select)
        view.mouseDown(with: mouse(.leftMouseDown, x: 120, y: 120))
        view.mouseUp(with: mouse(.leftMouseUp, x: 120, y: 120))
        XCTAssertFalse(slider.isHidden)
        XCTAssertEqual(slider.doubleValue, 6)
        slider.doubleValue = 9.2
        slider.sendAction(slider.action!, to: slider.target)
        XCTAssertEqual(document.annotations.map(\.style.blurRadius), [9, 2])
        document.undo(); XCTAssertEqual(document.annotations.first, first)
        document.redo(); XCTAssertEqual(document.annotations.first?.style.blurRadius, 9)
        view.toolbar.setExporting(true)
        XCTAssertFalse(slider.isEnabled)
        view.toolbar.setExporting(false)
        view.toolbar.onTool?(.pen)
        XCTAssertTrue(slider.isHidden)
    }

    @MainActor
    func testBlurDragMoveUndoAndContextualControls() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        view.toolbar.onTool?(.blur)
        let menus = view.toolbar.subviews.compactMap { $0 as? NSPopUpButton }
        for label in ["Annotation color", "Line width", "Text size"] {
            XCTAssertTrue(try XCTUnwrap(menus.first { $0.accessibilityLabel() == label }).isHidden)
        }
        view.mouseDown(with: mouse(.leftMouseDown, x: 160, y: 160))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 80, y: 80))
        XCTAssertFalse(view.prepareForExport())
        view.mouseUp(with: mouse(.leftMouseUp, x: 80, y: 80))
        let blur = try XCTUnwrap(document.annotations.first)
        XCTAssertEqual(blur.tool, .blur)
        XCTAssertEqual(blur.bounds, CGRect(x: 60, y: 60, width: 80, height: 80))
        view.keyDown(with: key(49))
        view.mouseDown(with: mouse(.leftMouseDown, x: 120, y: 120))
        view.mouseUp(with: mouse(.leftMouseUp, x: 140, y: 130))
        view.keyUp(with: key(49, type: .keyUp))
        XCTAssertEqual(document.annotations, [blur.moved(by: CGPoint(x: 20, y: 10))])
        document.undo(); XCTAssertEqual(document.annotations, [blur])
        XCTAssertTrue(view.prepareForExport())
        XCTAssertEqual(view.exportAnnotations, [blur])
        view.toolbar.onTool?(.rectangle)
        XCTAssertFalse(try XCTUnwrap(menus.first { $0.accessibilityLabel() == "Annotation color" }).isHidden)
    }

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
    func testAllResizeHandlesKeepOppositeEdgesAndAnnotationsFixed() async throws {
        let cases: [(CGPoint, CGRect)] = [
            (CGPoint(x: 22, y: 22), CGRect(x: 30, y: 35, width: 320, height: 225)),
            (CGPoint(x: 348, y: 22), CGRect(x: 20, y: 35, width: 340, height: 225)),
            (CGPoint(x: 22, y: 258), CGRect(x: 30, y: 20, width: 320, height: 255)),
            (CGPoint(x: 348, y: 258), CGRect(x: 20, y: 20, width: 340, height: 255)),
            (CGPoint(x: 22, y: 140), CGRect(x: 30, y: 20, width: 320, height: 240)),
            (CGPoint(x: 348, y: 140), CGRect(x: 20, y: 20, width: 340, height: 240)),
            (CGPoint(x: 185, y: 22), CGRect(x: 20, y: 35, width: 330, height: 225)),
            (CGPoint(x: 185, y: 258), CGRect(x: 20, y: 20, width: 330, height: 255))
        ]
        for (point, expected) in cases {
            let (window, view, document) = try fixture()
            defer { window.close() }
            view.mouseDown(with: mouse(.leftMouseDown, x: 70, y: 100))
            view.mouseUp(with: mouse(.leftMouseUp, x: 120, y: 130))
            let annotations = document.annotations
            let toolbar = view.toolbar.frame
            var resized: CGRect?
            view.onResizeSelection = { resized = $0 }
            view.mouseDown(with: mouse(.leftMouseDown, x: point.x, y: point.y))
            XCTAssertFalse(view.prepareForExport())
            view.mouseDragged(with: mouse(.leftMouseDragged, x: point.x + 10, y: point.y + 15))
            XCTAssertEqual(view.selection, expected, "Handle at \(point)")
            XCTAssertEqual(document.annotations, annotations)
            XCTAssertEqual(view.exportAnnotations, annotations.map {
                $0.moved(by: CGPoint(x: 20 - expected.minX, y: 20 - expected.minY))
            })
            view.keyDown(with: escape())
            XCTAssertEqual(view.selection, CGRect(x: 20, y: 20, width: 330, height: 240))
            XCTAssertEqual(view.toolbar.frame, toolbar)
            XCTAssertEqual(view.exportAnnotations, annotations)
            XCTAssertNil(resized)
            view.mouseDown(with: mouse(.leftMouseDown, x: point.x, y: point.y))
            view.mouseUp(with: mouse(.leftMouseUp, x: point.x + 10, y: point.y + 15))
            XCTAssertEqual(resized, expected)
            XCTAssertTrue(view.prepareForExport())
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
        view.mouseDown(with: mouse(.leftMouseDown, x: original.maxX, y: 100))
        XCTAssertFalse(view.prepareForExport())
        view.mouseDragged(with: mouse(.leftMouseDragged, x: original.maxX + 15, y: 110))
        view.mouseUp(with: mouse(.leftMouseUp, x: original.maxX + 15, y: 110))
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
        view.mouseDown(with: mouse(.leftMouseDown, x: original.maxX, y: 100))
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

    @MainActor
    func testSpaceTemporarilySelectsAndRestoresEveryToolDespiteKeyRepeat() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        let popup = try toolPopup(view)
        for tool in AnnotationTool.allCases {
            view.toolbar.onTool?(tool)
            view.keyDown(with: key(49))
            XCTAssertEqual(popup.indexOfSelectedItem, 0)
            view.keyDown(with: key(49, repeatKey: true))
            view.keyUp(with: key(49, type: .keyUp, modifiers: .shift))
            XCTAssertEqual(popup.indexOfSelectedItem, AnnotationTool.allCases.firstIndex(of: tool))
        }
    }

    @MainActor
    func testSpaceSelectsAndMovesAnnotationThenRestoresDrawingTool() async throws {
        let (window, view, document) = try fixture()
        defer { window.close() }
        let annotation = Annotation(tool: .line, points: [CGPoint(x: 30, y: 30), CGPoint(x: 80, y: 80)])
        document.commit(annotation)
        view.keyDown(with: key(49))
        view.mouseDown(with: mouse(.leftMouseDown, x: 70, y: 70))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 90, y: 80))
        view.keyUp(with: key(49, type: .keyUp))
        view.mouseUp(with: mouse(.leftMouseUp, x: 90, y: 80))
        XCTAssertEqual(document.annotations, [annotation.moved(by: CGPoint(x: 20, y: 10))])
        view.mouseDown(with: mouse(.leftMouseDown, x: 150, y: 150))
        view.mouseUp(with: mouse(.leftMouseUp, x: 200, y: 200))
        XCTAssertEqual(document.annotations.last?.tool, .rectangle)
    }

    @MainActor
    func testTabCyclesToolbarOrderAndWrapsWithoutRepeating() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        let popup = try toolPopup(view)
        view.toolbar.onTool?(.select)
        for index in 1...AnnotationTool.allCases.count {
            view.keyDown(with: key(48))
            view.keyDown(with: key(48, repeatKey: true))
            XCTAssertEqual(popup.indexOfSelectedItem, index % AnnotationTool.allCases.count)
        }
        view.toolbar.onTool?(.ellipse)
        view.keyDown(with: key(48))
        let menus = view.toolbar.subviews.compactMap { $0 as? NSPopUpButton }
        XCTAssertFalse(try XCTUnwrap(menus.first { $0.accessibilityLabel() == "Text size" }).isHidden)
        XCTAssertTrue(try XCTUnwrap(menus.first { $0.accessibilityLabel() == "Line width" }).isHidden)
    }

    @MainActor
    func testShiftTabCyclesBackwardAndWrapsWithoutRepeating() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        let popup = try toolPopup(view)
        view.toolbar.onTool?(.select)
        for index in 1...AnnotationTool.allCases.count {
            XCTAssertTrue(view.handleToolShortcut(key(48, modifiers: .shift)))
            XCTAssertTrue(view.handleToolShortcut(key(48, repeatKey: true, modifiers: .shift)))
            XCTAssertEqual(popup.indexOfSelectedItem,
                           (AnnotationTool.allCases.count - index) % AnnotationTool.allCases.count)
        }
        for modifiers: NSEvent.ModifierFlags in [.command, .control, .option, [.shift, .command]] {
            XCTAssertFalse(view.handleToolShortcut(key(48, modifiers: modifiers)))
        }
        XCTAssertFalse(view.handleToolShortcut(key(49, modifiers: .shift)))
    }

    @MainActor
    func testShiftTabWhileSpaceHeldChangesToolRestoredOnRelease() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        view.keyDown(with: key(49))
        view.keyDown(with: key(48, modifiers: .shift))
        XCTAssertEqual(try toolPopup(view).indexOfSelectedItem, 0)
        view.keyUp(with: key(49, type: .keyUp))
        XCTAssertEqual(try toolPopup(view).indexOfSelectedItem, AnnotationTool.allCases.firstIndex(of: .line))
    }

    @MainActor
    func testTabWhileSpaceHeldChangesToolRestoredOnRelease() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        view.keyDown(with: key(49))
        view.keyDown(with: key(48))
        XCTAssertEqual(try toolPopup(view).indexOfSelectedItem, 0)
        view.keyUp(with: key(49, type: .keyUp))
        XCTAssertEqual(try toolPopup(view).indexOfSelectedItem, AnnotationTool.allCases.firstIndex(of: .ellipse))
    }

    @MainActor
    func testShortcutsIgnoreTextEditingExportAndUnfinishedSelection() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        view.toolbar.onTool?(.text)
        view.mouseDown(with: mouse(.leftMouseDown, x: 50, y: 200))
        XCTAssertFalse(view.handleToolShortcut(key(49)))
        XCTAssertFalse(view.handleToolShortcut(key(48)))
        XCTAssertFalse(view.handleToolShortcut(key(48, modifiers: .shift)))
        let editor = try XCTUnwrap(view.subviews.compactMap { $0 as? AnnotationTextEditor }.first)
        editor.insertText("Two words", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(editor.string, "Two words")
        view.clearSelection()
        XCTAssertFalse(view.handleToolShortcut(key(49)))
        XCTAssertFalse(view.handleToolShortcut(key(48)))
        view.mouseDown(with: mouse(.leftMouseDown, x: 20, y: 20))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 350, y: 260))
        XCTAssertFalse(view.handleToolShortcut(key(49)))
        view.mouseUp(with: mouse(.leftMouseUp, x: 350, y: 260))
        view.isExporting = true
        XCTAssertFalse(view.handleToolShortcut(key(49)))
        XCTAssertFalse(view.handleToolShortcut(key(48)))
    }

    @MainActor
    func testPanelRoutesShortcutsWithToolbarFocusAndRestoresOnFocusLoss() async throws {
        let (window, view, _) = try fixture()
        defer { window.close() }
        let panel = CaptureOverlayPanel(frame: view.frame)
        defer { panel.close() }
        panel.contentView = view
        let popup = try toolPopup(view)
        panel.makeFirstResponder(popup)
        panel.sendEvent(key(48))
        XCTAssertEqual(popup.indexOfSelectedItem, AnnotationTool.allCases.firstIndex(of: .ellipse))
        panel.sendEvent(key(48, modifiers: .shift))
        XCTAssertEqual(popup.indexOfSelectedItem, AnnotationTool.allCases.firstIndex(of: .rectangle))
        panel.sendEvent(key(48))
        panel.sendEvent(key(49))
        XCTAssertEqual(popup.indexOfSelectedItem, 0)
        panel.resignKey()
        XCTAssertEqual(popup.indexOfSelectedItem, AnnotationTool.allCases.firstIndex(of: .ellipse))
        panel.sendEvent(key(49, type: .keyUp))
        XCTAssertEqual(popup.indexOfSelectedItem, AnnotationTool.allCases.firstIndex(of: .ellipse))
    }

    @MainActor
    private func toolPopup(_ view: CaptureOverlayView) throws -> NSPopUpButton {
        try XCTUnwrap(view.toolbar.subviews.compactMap { $0 as? NSPopUpButton }
            .first { $0.accessibilityLabel() == "Drawing tool" })
    }

    private func key(_ code: UInt16, type: NSEvent.EventType = .keyDown,
                     repeatKey: Bool = false, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        let characters = code == 49 ? " " : "\t"
        return NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                               windowNumber: 0, context: nil, characters: characters,
                               charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: code)!
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
