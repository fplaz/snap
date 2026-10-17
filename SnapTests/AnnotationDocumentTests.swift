import XCTest

final class AnnotationDocumentTests: XCTestCase {
    func testStampSequenceFollowsUndoRedoDeletionAndResetWithoutRenumbering() {
        let document = AnnotationDocument()
        XCTAssertEqual(document.nextStampNumber, 1)
        let stamps = (1...3).map { Annotation(tool: .numberStamp, points: [CGPoint(x: $0 * 40, y: 40)], number: $0) }
        stamps.forEach { document.commit($0) }
        XCTAssertEqual(document.nextStampNumber, 4)
        document.undo(); XCTAssertEqual(document.nextStampNumber, 3)
        document.redo(); XCTAssertEqual(document.nextStampNumber, 4)
        document.delete(stamps[0].id)
        XCTAssertEqual(document.annotations.map(\.number), [2, 3])
        XCTAssertEqual(document.nextStampNumber, 4)
        document.delete(stamps[2].id)
        XCTAssertEqual(document.nextStampNumber, 3)
        document.undo(); XCTAssertEqual(document.nextStampNumber, 4)
        let stamp = stamps[1]
        XCTAssertEqual(stamp.bounds.size, CGSize(width: 32, height: 32))
        XCTAssertTrue(stamp.hitTest(CGPoint(x: 80, y: 40)))
        XCTAssertFalse(stamp.hitTest(CGPoint(x: 95, y: 55)))
        let moved = stamp.moved(by: CGPoint(x: 20, y: 10))
        XCTAssertEqual(moved.number, 2)
        XCTAssertTrue(moved.hitTest(CGPoint(x: 100, y: 50)))
        document.reset(); XCTAssertEqual(document.nextStampNumber, 1)
    }

    private func line(_ y: CGFloat = 10) -> Annotation {
        Annotation(tool: .line, points: [CGPoint(x: 10, y: y), CGPoint(x: 100, y: y)])
    }

    func testCreationMovementDeletionAndUndoRestoreWholeOperations() {
        let document = AnnotationDocument()
        let original = line()
        document.commit(original)
        let moved = original.moved(by: CGPoint(x: 20, y: 5))
        document.commit(moved)
        document.delete(original.id)
        document.undo(); XCTAssertEqual(document.annotations, [moved])
        document.undo(); XCTAssertEqual(document.annotations, [original])
        document.undo(); XCTAssertTrue(document.annotations.isEmpty)
        document.redo(); XCTAssertEqual(document.annotations, [original])
        document.redo(); XCTAssertEqual(document.annotations, [moved])
        document.redo(); XCTAssertTrue(document.annotations.isEmpty)
    }

    func testNewEditAfterUndoClearsRedo() {
        let document = AnnotationDocument()
        document.commit(line()); document.undo(); document.commit(line(30))
        XCTAssertFalse(document.canRedo)
    }

    func testEmptyGesturesDoNotCreateHistory() {
        let document = AnnotationDocument()
        document.commit(Annotation(tool: .pen, points: [.zero, .zero]))
        document.commit(Annotation(tool: .rectangle, points: [.zero, CGPoint(x: 0, y: 30)]))
        document.commit(Annotation(tool: .text, points: [], text: "  \n"))
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertFalse(document.canUndo)
    }

    func testUnchangedMovementDoesNotCreateHistory() {
        let document = AnnotationDocument()
        let annotation = line()
        document.commit(annotation); document.commit(annotation)
        document.undo(); XCTAssertTrue(document.annotations.isEmpty)
    }

    func testHitTestingChoosesTopmostStrokeAndIgnoresEmptyInterior() {
        let document = AnnotationDocument()
        let first = line(), last = line()
        document.commit(first); document.commit(last)
        XCTAssertEqual(document.hit(at: CGPoint(x: 50, y: 10))?.id, last.id)
        let rectangle = Annotation(tool: .rectangle, points: [.zero, CGPoint(x: 100, y: 100)])
        XCTAssertFalse(rectangle.hitTest(CGPoint(x: 50, y: 50)))
        XCTAssertTrue(rectangle.hitTest(CGPoint(x: 0, y: 50)))
    }

    func testTextEditAndStyleUndoPreserveIdentityAndOrder() {
        let document = AnnotationDocument()
        var text = Annotation(tool: .text, points: [], text: "Hello", textRect: CGRect(x: 0, y: 0, width: 100, height: 40))
        document.commit(text)
        text.text = "Hola\n世界"; document.commit(text)
        text.style.color = .blue; document.commit(text)
        document.undo(); XCTAssertEqual(document.annotations.first?.text, "Hola\n世界")
        XCTAssertEqual(document.annotations.first?.style.color, .red)
        document.undo(); XCTAssertEqual(document.annotations.first?.text, "Hello")
        XCTAssertEqual(document.annotations.first?.id, text.id)
    }

    func testResetDropsAnnotationsAndHistory() {
        let document = AnnotationDocument()
        document.commit(line()); document.reset()
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertFalse(document.canUndo); XCTAssertFalse(document.canRedo)
    }

    func testBlurRequiresAreaAndCanBeSelectedMovedDeletedAndUndone() {
        let document = AnnotationDocument()
        document.commit(Annotation(tool: .blur, points: [.zero, CGPoint(x: 0, y: 30)]))
        XCTAssertFalse(document.canUndo)
        let blur = Annotation(tool: .blur, points: [CGPoint(x: 80, y: 60), CGPoint(x: 10, y: 20)])
        document.commit(blur)
        XCTAssertEqual(document.hit(at: CGPoint(x: 40, y: 40)), blur)
        XCTAssertNil(document.hit(at: CGPoint(x: 90, y: 40)))
        let moved = blur.moved(by: CGPoint(x: 20, y: 10))
        document.commit(moved)
        document.delete(blur.id)
        document.undo(); XCTAssertEqual(document.annotations, [moved])
        document.undo(); XCTAssertEqual(document.annotations, [blur])
        document.undo(); XCTAssertTrue(document.annotations.isEmpty)
        document.redo(); XCTAssertEqual(document.annotations, [blur])
    }
}
