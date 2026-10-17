import AppKit
import XCTest

final class AnnotationSettingsTests: XCTestCase {
    @MainActor
    func testFreshInstallUsesThinOutlineAndFixedDefaults() throws {
        try withStorage { storage in
            let settings = AnnotationSettings(storage: storage)
            XCTAssertFalse(settings.useLastUsed)
            XCTAssertEqual(settings.initial.tool, .rectangle)
            XCTAssertEqual(settings.initial.style.width, 2)
            XCTAssertFalse(settings.initial.style.isFilled)
            let toolbar = CaptureToolbar()
            let shape = try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSPopUpButton }
                .first { $0.accessibilityLabel() == "Shape style" })
            XCTAssertEqual(shape.indexOfSelectedItem, 0)
        }
    }

    @MainActor
    func testFixedDefaultsAndLastUsedPersistIndependentlyAcrossRelaunch() throws {
        try withStorage { storage in
            let settings = AnnotationSettings(storage: storage)
            let fixed = AnnotationDefaults(tool: .ellipse,
                style: AnnotationStyle(color: .blue, width: 8, fontSize: 32, blurRadius: 7, isFilled: true))
            settings.defaults = fixed
            XCTAssertEqual(settings.beginCapture(), fixed)
            settings.record(tool: .arrow)
            let lastStyle = AnnotationStyle(color: .green, width: 4, fontSize: 16, blurRadius: 9)
            settings.record(style: lastStyle)
            XCTAssertEqual(settings.initial, fixed)
            settings.useLastUsed = true
            let relaunched = AnnotationSettings(storage: storage)
            XCTAssertTrue(relaunched.useLastUsed)
            XCTAssertEqual(relaunched.initial, AnnotationDefaults(tool: .arrow, style: lastStyle))
            relaunched.useLastUsed = false
            XCTAssertEqual(relaunched.initial, fixed)
            // A capture with fixed defaults also becomes the most recently used configuration.
            XCTAssertEqual(relaunched.beginCapture(), fixed)
            relaunched.useLastUsed = true
            XCTAssertEqual(relaunched.initial, fixed)
        }
    }

    @MainActor
    func testCorruptSavedDataFallsBackToThinDefaults() throws {
        try withStorage { storage in
            storage.set(Data("invalid".utf8), forKey: "annotationDefaults")
            storage.set(Data("invalid".utf8), forKey: "lastUsedAnnotationSettings")
            storage.set(true, forKey: "useLastUsedAnnotationSettings")
            XCTAssertEqual(AnnotationSettings(storage: storage).initial, AnnotationDefaults())
        }
    }

    @MainActor
    func testSettingsWindowCanCloseAndReopenWithSamePreferences() throws {
        try withStorage { storage in
            let settings = AnnotationSettings(storage: storage)
            let controller = SettingsWindow(settings: settings)
            defer { controller.window?.close(); controller.window?.contentView = nil }
            controller.show()
            let window = try XCTUnwrap(controller.window)
            XCTAssertEqual(window.title, "Annotation tool settings")
            XCTAssertTrue(window.isVisible)
            settings.useLastUsed = true
            window.close()
            controller.show()
            XCTAssertTrue(controller.window === window)
            XCTAssertTrue(window.isVisible)
            XCTAssertTrue(settings.useLastUsed)
            controller.hide()
            XCTAssertFalse(window.isVisible)
        }
    }

    @MainActor
    private func withStorage(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "SnapAnnotationSettingsTests.\(UUID().uuidString)"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        try body(storage)
    }
}
