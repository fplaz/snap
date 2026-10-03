import XCTest

final class CaptureSessionTests: XCTestCase {
    func testRepeatedInvocationKeepsOneSession() throws {
        var session = CaptureSession()
        let id = try XCTUnwrap(session.begin())
        XCTAssertNil(session.begin())
        XCTAssertEqual(session.id, id)
        XCTAssertTrue(session.prepared(id))
        XCTAssertNil(session.begin())
    }

    func testLatePreparationCannotResurrectCanceledSession() throws {
        var session = CaptureSession()
        let old = try XCTUnwrap(session.begin())
        session.cancel()
        let current = try XCTUnwrap(session.begin())
        XCTAssertFalse(session.prepared(old))
        XCTAssertEqual(session.phase, .preparing)
        XCTAssertTrue(session.prepared(current))
    }

    func testZeroAreaSelectionRemainsSelectable() throws {
        var session = CaptureSession()
        XCTAssertTrue(session.prepared(try XCTUnwrap(session.begin())))
        XCTAssertFalse(session.select(displayID: 1, rectangle: .zero))
        XCTAssertEqual(session.phase, .selecting)
        XCTAssertNil(session.beginExport())
    }

    func testCanceledSaveRetainsOriginalSelectionForCopy() throws {
        var session = try readySession()
        let selection = session.selection
        let id = try XCTUnwrap(session.beginExport())
        XCTAssertNil(session.beginExport())
        XCTAssertFalse(session.beginSelection())
        XCTAssertTrue(session.resumeAfterExport(id))
        XCTAssertEqual(session.selection, selection)
        XCTAssertEqual(session.beginExport(), id)
    }

    func testCancelInvalidatesPendingOutputAndReleasesSelection() throws {
        var session = try readySession()
        let id = try XCTUnwrap(session.beginExport())
        session.cancel()
        XCTAssertFalse(session.isExporting(id))
        XCTAssertFalse(session.resumeAfterExport(id))
        XCTAssertNil(session.selection)
        XCTAssertEqual(session.phase, .idle)
    }

    func testReselectReplacesSelectionOnDifferentDisplay() throws {
        var session = try readySession()
        XCTAssertTrue(session.beginSelection())
        XCTAssertNil(session.selection)
        XCTAssertTrue(session.select(displayID: 2, rectangle: CGRect(x: 10, y: 10, width: 20, height: 20)))
        XCTAssertEqual(session.selection?.displayID, 2)
    }

    func testThirtySessionsEndWithoutStateLeaking() throws {
        var session = CaptureSession()
        for _ in 0..<30 {
            let id = try XCTUnwrap(session.begin())
            XCTAssertTrue(session.prepared(id))
            XCTAssertTrue(session.select(displayID: 1, rectangle: CGRect(x: 1, y: 1, width: 20, height: 20)))
            XCTAssertEqual(session.beginExport(), id)
            session.cancel()
            XCTAssertNil(session.id)
            XCTAssertNil(session.selection)
            XCTAssertEqual(session.phase, .idle)
        }
    }

    private func readySession() throws -> CaptureSession {
        var session = CaptureSession()
        XCTAssertTrue(session.prepared(try XCTUnwrap(session.begin())))
        XCTAssertTrue(session.select(displayID: 1, rectangle: CGRect(x: 50, y: 100, width: 200, height: 100)))
        return session
    }
}
