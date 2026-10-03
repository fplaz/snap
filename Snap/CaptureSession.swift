import CoreGraphics
import Foundation

struct CaptureSession {
    enum Phase: Equatable { case idle, preparing, selecting, ready, exporting }
    struct Selection: Equatable {
        let displayID: CGDirectDisplayID
        let rectangle: CGRect
    }

    private(set) var phase: Phase = .idle
    private(set) var id: UUID?
    private(set) var selection: Selection?

    mutating func begin() -> UUID? {
        guard phase == .idle else { return nil }
        let id = UUID()
        self.id = id
        phase = .preparing
        return id
    }

    mutating func prepared(_ id: UUID) -> Bool {
        guard self.id == id, phase == .preparing else { return false }
        phase = .selecting
        return true
    }

    mutating func beginSelection() -> Bool {
        guard phase == .selecting || phase == .ready else { return false }
        phase = .selecting
        selection = nil
        return true
    }

    mutating func select(displayID: CGDirectDisplayID, rectangle: CGRect) -> Bool {
        guard phase == .selecting, rectangle.width > 0, rectangle.height > 0 else { return false }
        selection = Selection(displayID: displayID, rectangle: rectangle)
        phase = .ready
        return true
    }

    mutating func beginExport() -> UUID? {
        guard phase == .ready, selection != nil else { return nil }
        phase = .exporting
        return id
    }

    mutating func resumeAfterExport(_ id: UUID) -> Bool {
        guard self.id == id, phase == .exporting else { return false }
        phase = .ready
        return true
    }

    func isExporting(_ id: UUID) -> Bool { self.id == id && phase == .exporting }

    mutating func cancel() {
        phase = .idle
        id = nil
        selection = nil
    }
}
