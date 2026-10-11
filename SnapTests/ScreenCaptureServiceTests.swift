import XCTest
import ScreenCaptureKit

final class ScreenCaptureServiceTests: XCTestCase {
    func testCapturePermissionDenialIsRecognizedByDomainAndCode() {
        let code = SCStreamError.Code.userDeclined.rawValue
        XCTAssertTrue(ScreenCaptureService.isPermissionDenied(NSError(domain: SCStreamError.errorDomain, code: code)))
        XCTAssertFalse(ScreenCaptureService.isPermissionDenied(NSError(domain: NSCocoaErrorDomain, code: code)))
        XCTAssertFalse(ScreenCaptureService.isPermissionDenied(NSError(domain: SCStreamError.errorDomain, code: -1)))
        XCTAssertFalse(ScreenCaptureService.isPermissionDenied(CancellationError()))
    }

    func testRetinaCaptureMatchesDisplayRenderingPixels() {
        // This display reports 1710×1112 logical points but renders at 3420×2224.
        let configuration = ScreenCaptureService.configuration(
            logicalSize: CGSize(width: 1710, height: 1112), pixelScale: 2)
        XCTAssertEqual(configuration.width, 3420)
        XCTAssertEqual(configuration.height, 2224)
        XCTAssertEqual(configuration.captureResolution, .best)
        XCTAssertFalse(configuration.ignoreShadowsDisplay)
        XCTAssertFalse(configuration.ignoreShadowsSingleWindow)
    }

    func testStandardDisplayDoesNotUpscaleSourcePixels() {
        let configuration = ScreenCaptureService.configuration(
            logicalSize: CGSize(width: 1920, height: 1080), pixelScale: 1)
        XCTAssertEqual(configuration.width, 1920)
        XCTAssertEqual(configuration.height, 1080)
    }
}
