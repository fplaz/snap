import XCTest
import AppKit
import ImageIO

final class AnnotationRendererTests: XCTestCase {
    func testRetinaCompositionPreservesDimensionsAndStrokePlacement() throws {
        let image = try background(width: 200, height: 160)
        let annotation = Annotation(tool: .line, points: [CGPoint(x: 10, y: 20), CGPoint(x: 80, y: 20)],
                                    style: AnnotationStyle(color: .black, width: 4))
        let result = try ScreenshotExporter.compose(image: image, selection: CGRect(x: 0, y: 0, width: 100, height: 80),
                                                   logicalSize: CGSize(width: 100, height: 80), annotations: [annotation])
        XCTAssertEqual(result.width, 200); XCTAssertEqual(result.height, 160)
        XCTAssertEqual(try pixel(result, x: 60, yFromBottom: 40), [0, 0, 0, 255])
        XCTAssertEqual(try pixel(result, x: 60, yFromBottom: 50), [255, 255, 255, 255])
    }

    func testMovedAnnotationIsClippedToCrop() throws {
        let annotation = Annotation(tool: .rectangle, points: [CGPoint(x: -10, y: 10), CGPoint(x: 20, y: 30)],
                                    style: AnnotationStyle(color: .black, width: 2))
        let result = try ScreenshotExporter.compose(image: background(width: 100, height: 80),
                                                   selection: CGRect(x: 10, y: 10, width: 40, height: 40),
                                                   logicalSize: CGSize(width: 100, height: 80), annotations: [annotation])
        XCTAssertEqual(result.width, 40); XCTAssertEqual(result.height, 40)
        XCTAssertEqual(try pixel(result, x: 20, yFromBottom: 20), [0, 0, 0, 255])
        XCTAssertEqual(try pixel(result, x: 35, yFromBottom: 20), [255, 255, 255, 255])
    }

    func testFractionalCropOffsetPlacesAnnotationsAtSourceCoordinates() throws {
        let annotation = Annotation(tool: .line, points: [CGPoint(x: 0, y: 2), CGPoint(x: 10, y: 2)],
                                    style: AnnotationStyle(color: .black, width: 1))
        let result = try ScreenshotExporter.compose(image: background(width: 200, height: 160),
                                                   selection: CGRect(x: 10.25, y: 10.25, width: 10, height: 10),
                                                   logicalSize: CGSize(width: 100, height: 80), annotations: [annotation])
        XCTAssertEqual(result.width, 21); XCTAssertEqual(result.height, 21)
        XCTAssertEqual(try pixel(result, x: 10, yFromBottom: 4), [0, 0, 0, 255])
        XCTAssertEqual(try pixel(result, x: 10, yFromBottom: 10), [255, 255, 255, 255])
    }

    func testArrowheadEndsAtTipAndFollowsDirection() {
        let arrow = Annotation(tool: .arrow, points: [.zero, CGPoint(x: 100, y: 0)])
        let points = AnnotationRenderer.arrowhead(for: arrow)
        XCTAssertEqual(points[1], CGPoint(x: 100, y: 0))
        XCTAssertLessThan(points[0].x, 100); XCTAssertGreaterThan(points[0].y, 0)
        XCTAssertLessThan(points[2].y, 0)
    }

    func testUnannotatedExportPreservesOriginalCropPixels() throws {
        let image = try background(width: 100, height: 80)
        let selection = CGRect(x: 10, y: 10, width: 40, height: 30)
        let composed = try ScreenshotExporter.compose(image: image, selection: selection,
                                                     logicalSize: CGSize(width: 100, height: 80), annotations: [])
        let cropped = try ScreenshotExporter.crop(image: image, selection: selection, logicalSize: CGSize(width: 100, height: 80))
        XCTAssertEqual(try ScreenshotExporter.png(image: composed), try ScreenshotExporter.png(image: cropped))
    }

    func testMultilineUnicodeTextProducesComposedPNG() throws {
        let text = Annotation(tool: .text, points: [], style: AnnotationStyle(color: .black, fontSize: 16),
                              text: "Hello\n世界", textRect: CGRect(x: 5, y: 5, width: 90, height: 65))
        let image = try ScreenshotExporter.compose(image: background(width: 200, height: 160),
                                                  selection: CGRect(x: 0, y: 0, width: 100, height: 80),
                                                  logicalSize: CGSize(width: 100, height: 80), annotations: [text])
        let data = try ScreenshotExporter.png(image: image)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width, 200)
        var hasGlyph = false
        for y in 50..<140 {
            if try pixel(image, x: 20, yFromBottom: y)[0] < 250 { hasGlyph = true; break }
        }
        XCTAssertTrue(hasGlyph)
    }

    private func background(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func pixel(_ image: CGImage, x: Int, yFromBottom: Int) throws -> [UInt8] {
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: image.height - 1 - yFromBottom, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                                 bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
}
