import XCTest
import CoreGraphics

final class SelectionGeometryTests: XCTestCase {
    func testResizeToolbarFollowsOutsideEdgesAndWaitsForInsideEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let start = CGRect(x: 100, y: 300, width: 400, height: 400)
        let outside = CGRect(x: 520, y: 230, width: 100, height: 50)
        let expanded = CGRect(x: 100, y: 200, width: 500, height: 500)
        XCTAssertEqual(SelectionGeometry.resizedToolbar(original: outside, from: start, to: expanded, bounds: bounds),
                       outside.offsetBy(dx: 100, dy: -100))
        let inside = CGRect(x: 350, y: 350, width: 100, height: 50)
        let partial = CGRect(x: 100, y: 370, width: 380, height: 330)
        XCTAssertEqual(SelectionGeometry.resizedToolbar(original: inside, from: start, to: partial, bounds: bounds), inside)
        let crossed = CGRect(x: 100, y: 450, width: 200, height: 250)
        XCTAssertEqual(SelectionGeometry.resizedToolbar(original: inside, from: start, to: crossed, bounds: bounds),
                       CGRect(x: 200, y: 390, width: 100, height: 50))
        XCTAssertEqual(SelectionGeometry.resizedToolbar(original: inside, from: start, to: start, bounds: bounds), inside)
    }
    func testResizeKeepsToolbarRightEdgeAttachedInBothDirections() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let start = CGRect(x: 100, y: 300, width: 400, height: 400)
        let toolbar = CGRect(x: 350, y: 230, width: 150, height: 50)
        for width: CGFloat in [250, 550] {
            let resized = CGRect(x: 100, y: 300, width: width, height: 400)
            let frame = SelectionGeometry.resizedToolbar(original: toolbar, from: start, to: resized, bounds: bounds)
            XCTAssertEqual(frame.maxX, resized.maxX)
            XCTAssertEqual(frame.minY, toolbar.minY)
        }
    }
    func testReversedDragNormalizesAndClampsToDisplay() {
        let rectangle = SelectionGeometry.rectangle(from: CGPoint(x: 250, y: 180),
                                                     to: CGPoint(x: -30, y: 40),
                                                     in: CGRect(x: 0, y: 0, width: 200, height: 150))
        XCTAssertEqual(rectangle, CGRect(x: 0, y: 40, width: 200, height: 110))
    }

    func testRetinaCropConvertsToTopLeftPixelCoordinates() {
        let rectangle = SelectionGeometry.pixelRectangle(
            for: CGRect(x: 50, y: 100, width: 200, height: 100),
            logicalSize: CGSize(width: 500, height: 400), pixelSize: CGSize(width: 1000, height: 800))
        XCTAssertEqual(rectangle, CGRect(x: 100, y: 400, width: 400, height: 200))
    }

    func testIndependentFractionalScalesRoundOutward() {
        let rectangle = SelectionGeometry.pixelRectangle(
            for: CGRect(x: 1.2, y: 2.2, width: 2.1, height: 3.1),
            logicalSize: CGSize(width: 10, height: 10), pixelSize: CGSize(width: 15, height: 20))
        XCTAssertEqual(rectangle, CGRect(x: 1, y: 9, width: 4, height: 7))
    }

    func testCropClipsAtDisplayEdge() {
        let rectangle = SelectionGeometry.pixelRectangle(
            for: CGRect(x: -5, y: -5, width: 10, height: 10),
            logicalSize: CGSize(width: 10, height: 10), pixelSize: CGSize(width: 10, height: 10))
        XCTAssertEqual(rectangle, CGRect(x: 0, y: 5, width: 5, height: 5))
    }

    func testEmptyAndOffscreenCropsAreRejected() {
        for rectangle in [CGRect.zero, CGRect(x: 20, y: 20, width: 2, height: 2)] {
            XCTAssertNil(SelectionGeometry.pixelRectangle(for: rectangle,
                                                          logicalSize: CGSize(width: 10, height: 10),
                                                          pixelSize: CGSize(width: 20, height: 20)))
        }
    }

    func testGlobalDisplayOriginDoesNotChangeLocalCrop() {
        let display = CGRect(x: -1920, y: 1080, width: 1920, height: 1080)
        let globalPoint = CGPoint(x: -1900, y: 1100)
        let localPoint = CGPoint(x: globalPoint.x - display.minX, y: globalPoint.y - display.minY)
        let rectangle = SelectionGeometry.rectangle(from: localPoint, to: CGPoint(x: 220, y: 120),
                                                     in: CGRect(origin: .zero, size: display.size))
        XCTAssertEqual(rectangle, CGRect(x: 20, y: 20, width: 200, height: 100))
    }

    func testToolbarStaysWithinUsableBoundsAtEveryCorner() {
        let bounds = CGRect(x: 0, y: 30, width: 800, height: 550)
        for origin in [CGPoint(x: 0, y: 30), CGPoint(x: 798, y: 30),
                       CGPoint(x: 0, y: 578), CGPoint(x: 798, y: 578)] {
            let frame = SelectionGeometry.toolbarFrame(selection: CGRect(origin: origin, size: CGSize(width: 2, height: 2)),
                                                        size: CGSize(width: 244, height: 48), bounds: bounds)
            XCTAssertTrue(bounds.contains(frame), "Toolbar outside screen at \(origin)")
        }
    }
}
