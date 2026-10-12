import AppKit
import XCTest

final class TutorialTests: XCTestCase {
    @MainActor
    func testFirstLaunchIsRecordedEvenWhenSkippedAndPersistsAcrossInstances() throws {
        let suite = "SnapTutorialTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tutorial = TutorialWindow(defaults: defaults)
        defer { tutorial.window?.close(); tutorial.window?.contentView = nil }
        XCTAssertFalse(defaults.bool(forKey: TutorialWindow.shownKey))
        tutorial.showOnFirstLaunch()
        XCTAssertTrue(defaults.bool(forKey: TutorialWindow.shownKey))
        XCTAssertTrue(try XCTUnwrap(tutorial.window).isVisible)
        tutorial.hide()
        tutorial.showOnFirstLaunch()
        XCTAssertFalse(try XCTUnwrap(tutorial.window).isVisible)
        let relaunched = TutorialWindow(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        relaunched.showOnFirstLaunch()
        XCTAssertNil(relaunched.window)
    }

    @MainActor
    func testNavigationCompletesAndManualReplayStartsAtBeginning() throws {
        let suite = "SnapTutorialTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tutorial = TutorialWindow(defaults: defaults)
        defer { tutorial.window?.close(); tutorial.window?.contentView = nil }
        tutorial.show()
        tutorial.back()
        XCTAssertEqual(tutorial.step, 0)
        tutorial.next(); tutorial.back()
        XCTAssertEqual(tutorial.step, 0)
        for expected in 1..<TutorialStep.all.count {
            tutorial.next()
            XCTAssertEqual(tutorial.step, expected)
        }
        tutorial.next()
        XCTAssertFalse(try XCTUnwrap(tutorial.window).isVisible)
        tutorial.show()
        XCTAssertEqual(tutorial.step, 0)
        XCTAssertTrue(try XCTUnwrap(tutorial.window).isVisible)
        tutorial.window?.close()
        tutorial.showOnFirstLaunch()
        XCTAssertFalse(try XCTUnwrap(tutorial.window).isVisible)
    }
}
