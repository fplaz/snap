import AppKit

struct DisplaySnapshot {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let image: CGImage

    var logicalSize: CGSize { frame.size }
}
