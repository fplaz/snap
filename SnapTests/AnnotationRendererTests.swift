import XCTest
import AppKit
import ImageIO

final class AnnotationRendererTests: XCTestCase {
    func testShapeFillUsesSelectedColorAndPreservesOutlineAtBothScales() throws {
        for scale in [1, 2] {
            for tool in [AnnotationTool.rectangle, .ellipse] {
                var annotation = Annotation(tool: tool, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 60)],
                                            style: AnnotationStyle(color: .blue, width: 8, isFilled: true))
                let source = try background(width: 100 * scale, height: 80 * scale)
                let filled = try ScreenshotExporter.compose(image: source, selection: CGRect(x: 0, y: 0, width: 100, height: 80),
                                                            logicalSize: CGSize(width: 100, height: 80), annotations: [annotation])
                let center = try pixel(filled, x: 50 * scale, yFromBottom: 40 * scale)
                XCTAssertLessThan(center[0], 40)
                XCTAssertGreaterThan(center[2], 240)
                XCTAssertEqual(center[3], 255)
                XCTAssertEqual(try pixel(filled, x: 10 * scale, yFromBottom: 40 * scale), [255, 255, 255, 255])
                if tool == .ellipse {
                    XCTAssertEqual(try pixel(filled, x: 21 * scale, yFromBottom: 21 * scale), [255, 255, 255, 255])
                }
                annotation.style.isFilled = false
                let outlined = try ScreenshotExporter.compose(image: source, selection: CGRect(x: 0, y: 0, width: 100, height: 80),
                                                              logicalSize: CGSize(width: 100, height: 80), annotations: [annotation])
                XCTAssertEqual(try pixel(outlined, x: 50 * scale, yFromBottom: 40 * scale), [255, 255, 255, 255])
                XCTAssertEqual(try pixel(outlined, x: 50 * scale, yFromBottom: 20 * scale), center)
            }
        }
    }

    func testDifferentBlurStrengthsRenderIndependently() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 100, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 100))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 100))
        let light = Annotation(tool: .blur, points: [CGPoint(x: 20, y: 5), CGPoint(x: 100, y: 45)],
                               style: AnnotationStyle(blurRadius: 1))
        let strong = Annotation(tool: .blur, points: [CGPoint(x: 20, y: 55), CGPoint(x: 100, y: 95)],
                                style: AnnotationStyle(blurRadius: 12))
        let result = try ScreenshotExporter.compose(image: XCTUnwrap(context.makeImage()),
                                                    selection: CGRect(x: 0, y: 0, width: 120, height: 100),
                                                    logicalSize: CGSize(width: 120, height: 100), annotations: [light, strong])
        let lightPixel = try pixel(result, x: 52, yFromBottom: 25)[0]
        let strongPixel = try pixel(result, x: 52, yFromBottom: 75)[0]
        XCTAssertLessThan(lightPixel, 10)
        XCTAssertGreaterThan(strongPixel, lightPixel + 40)
    }

    func testBlurChangesOnlyItsAreaAtNativeAndRetinaScale() throws {
        for scale in [1, 2] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 160 * scale, height: 100 * scale,
                                                 bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 160 * scale, height: 100 * scale))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 80 * scale, height: 100 * scale))
            let source = try XCTUnwrap(context.makeImage())
            let selection = CGRect(x: 20.25, y: 10.25, width: 100, height: 70)
            let blur = Annotation(tool: .blur, points: [CGPoint(x: 40, y: 10), CGPoint(x: 80, y: 40)],
                                  style: AnnotationStyle(blurRadius: 12))
            let result = try ScreenshotExporter.compose(image: source, selection: selection,
                                                        logicalSize: CGSize(width: 160, height: 100), annotations: [blur])
            let original = try ScreenshotExporter.crop(image: source, selection: selection,
                                                       logicalSize: CGSize(width: 160, height: 100))
            XCTAssertEqual(result.width, original.width)
            XCTAssertEqual(result.height, original.height)
            let center = try pixel(result, x: 60 * scale, yFromBottom: 25 * scale)
            XCTAssertGreaterThan(center[0], 60)
            XCTAssertLessThan(center[0], 195)
            XCTAssertEqual(center[3], 255)
            for point in [(30, 25), (90, 25), (60, 55)] {
                XCTAssertEqual(try pixel(result, x: point.0 * scale, yFromBottom: point.1 * scale),
                               try pixel(original, x: point.0 * scale, yFromBottom: point.1 * scale))
            }
            // Overlapping blurs do not compound their strength or erase annotations.
            let line = Annotation(tool: .line, points: [CGPoint(x: 45, y: 25), CGPoint(x: 75, y: 25)],
                                  style: AnnotationStyle(color: .black, width: 4))
            let overlap = try ScreenshotExporter.compose(image: source, selection: selection,
                                                         logicalSize: CGSize(width: 160, height: 100),
                                                         annotations: [line, blur, blur.moved(by: CGPoint(x: 5, y: 0))])
            XCTAssertEqual(try pixel(overlap, x: 60 * scale, yFromBottom: 25 * scale), [0, 0, 0, 255])
            XCTAssertEqual(try pixel(overlap, x: 60 * scale, yFromBottom: 15 * scale),
                           try pixel(result, x: 60 * scale, yFromBottom: 15 * scale))
        }
    }

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
