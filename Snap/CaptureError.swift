import Foundation

enum CaptureError: LocalizedError {
    case displayUnavailable, invalidSelection, encodingFailed, clipboardFailed

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: return "The display changed or is unavailable. Try taking a new screenshot."
        case .invalidSelection: return "Select a nonempty area of the screen."
        case .encodingFailed: return "The screenshot could not be encoded as a PNG."
        case .clipboardFailed: return "The screenshot could not be copied. Try again or save it instead."
        }
    }
}
