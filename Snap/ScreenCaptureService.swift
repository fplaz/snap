import AppKit
import ScreenCaptureKit

enum ScreenCaptureService {
    struct Display {
        let id: CGDirectDisplayID
        let frame: CGRect
    }

    static func configuration(logicalSize: CGSize, pixelScale: CGFloat) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        // CoreGraphics display dimensions can be logical points on Retina displays.
        // Use ScreenCaptureKit's source scale so the frozen image matches the backing pixels.
        configuration.width = Int((logicalSize.width * pixelScale).rounded(.up))
        configuration.height = Int((logicalSize.height * pixelScale).rounded(.up))
        configuration.captureResolution = .best
        configuration.ignoreShadowsDisplay = false
        configuration.ignoreShadowsSingleWindow = false
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        return configuration
    }

    static func capture(displays: [Display]) async throws -> [DisplaySnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: DisplaySnapshot.self) { group in
            for screen in displays {
                guard let display = content.displays.first(where: { $0.displayID == screen.id }) else {
                    throw CaptureError.displayUnavailable
                }
                group.addTask {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let configuration = configuration(logicalSize: filter.contentRect.size,
                                                      pixelScale: CGFloat(filter.pointPixelScale))
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    try Task.checkCancellation()
                    return DisplaySnapshot(displayID: screen.id, frame: screen.frame, image: image)
                }
            }
            var snapshots: [DisplaySnapshot] = []
            for try await snapshot in group { snapshots.append(snapshot) }
            return snapshots
        }
    }
}
