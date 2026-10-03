import XCTest
import ImageIO

final class ScreenshotExporterTests: XCTestCase {
    func testCropUsesTopLeftImagePixelsAndPNGPreservesThem() throws {
        // Image rows: red, green / blue, white. Select the top-right logical pixel.
        let image = try fixture()
        let cropped = try ScreenshotExporter.crop(image: image, selection: CGRect(x: 1, y: 1, width: 1, height: 1),
                                                   logicalSize: CGSize(width: 2, height: 2))
        XCTAssertEqual(cropped.width, 1)
        XCTAssertEqual(cropped.height, 1)
        let data = try ScreenshotExporter.png(image: cropped)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 1)
        XCTAssertEqual(decoded.height, 1)
        XCTAssertEqual(try pixel(decoded), [0, 255, 0, 255])
    }

    func testBottomLeftCropSelectsBlueRatherThanRed() throws {
        let cropped = try ScreenshotExporter.crop(image: fixture(), selection: CGRect(x: 0, y: 0, width: 1, height: 1),
                                                   logicalSize: CGSize(width: 2, height: 2))
        XCTAssertEqual(try pixel(cropped), [0, 0, 255, 255])
    }

    func testRetinaExportPreservesPixelDimensions() throws {
        let image = try fixture()
        let cropped = try ScreenshotExporter.crop(image: image, selection: CGRect(x: 0, y: 0, width: 1, height: 0.5),
                                                   logicalSize: CGSize(width: 1, height: 1))
        XCTAssertEqual(cropped.width, 2)
        XCTAssertEqual(cropped.height, 1)
    }

    func testInvalidCropDoesNotExport() throws {
        XCTAssertThrowsError(try ScreenshotExporter.crop(image: fixture(), selection: .zero,
                                                         logicalSize: CGSize(width: 2, height: 2)))
    }

    func testPNGCanBeWrittenAndDecodedFromDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("capture.png")
        try ScreenshotExporter.png(image: fixture()).write(to: url, options: .atomic)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 2)
    }

    private func fixture() throws -> CGImage {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                             0, 0, 255, 255, 255, 255, 255, 255]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func pixel(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                                  bitsPerComponent: 8, bytesPerRow: 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
}
