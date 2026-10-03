import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenshotExporter {
    static func compose(image: CGImage, selection: CGRect, logicalSize: CGSize,
                        annotations: [Annotation]) throws -> CGImage {
        let cropped = try crop(image: image, selection: selection, logicalSize: logicalSize)
        guard !annotations.isEmpty else { return cropped }
        guard let pixels = SelectionGeometry.pixelRectangle(for: selection, logicalSize: logicalSize,
                                                            pixelSize: CGSize(width: image.width, height: image.height)),
              let context = CGContext(data: nil, width: cropped.width, height: cropped.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureError.encodingFailed
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        let scaleX = CGFloat(image.width) / logicalSize.width
        let scaleY = CGFloat(image.height) / logicalSize.height
        context.translateBy(x: selection.minX * scaleX - pixels.minX,
                            y: selection.minY * scaleY - (CGFloat(image.height) - pixels.maxY))
        context.scaleBy(x: scaleX, y: scaleY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        AnnotationRenderer.draw(annotations, in: CGRect(origin: .zero, size: selection.size))
        NSGraphicsContext.restoreGraphicsState()
        guard let result = context.makeImage() else { throw CaptureError.encodingFailed }
        return result
    }

    static func crop(image: CGImage, selection: CGRect, logicalSize: CGSize) throws -> CGImage {
        guard let pixels = SelectionGeometry.pixelRectangle(
            for: selection, logicalSize: logicalSize,
            pixelSize: CGSize(width: image.width, height: image.height)),
              let cropped = image.cropping(to: pixels) else { throw CaptureError.invalidSelection }
        return cropped
    }

    static func png(image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.encodingFailed }
        return data as Data
    }
}
