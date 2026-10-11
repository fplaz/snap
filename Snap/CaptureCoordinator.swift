import AppKit
import Carbon
import UniformTypeIdentifiers
import os
import Combine

@MainActor
final class CaptureCoordinator {
    var onCaptureStarted: (() -> Void)?
    var onCaptureEnded: (() -> Void)?
    private let uploads: UploadCoordinator?
    private var uploadObservation: AnyCancellable?
    private var session = CaptureSession()
    private let document = AnnotationDocument()
    private var snapshots: [CGDirectDisplayID: DisplaySnapshot] = [:]
    private var panels: [CGDirectDisplayID: CaptureOverlayPanel] = [:]
    private var preparation: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var escapeShortcut: GlobalShortcut?
    private var previousApplication: NSRunningApplication?
    private var savePanel: NSSavePanel?
    private var displayObserver: NSObjectProtocol?
    private let log = OSLog(subsystem: "cl.fplaz.snap", category: "Capture")
    private var captureSignpost: OSSignpostID?

    init(uploads: UploadCoordinator? = nil) {
        self.uploads = uploads
        uploadObservation = uploads?.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refreshUploadAvailability() }
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }
    }

    deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
    }

    func start() {
        guard session.phase == .idle else { return }
        let previous = NSWorkspace.shared.frontmostApplication
        guard ScreenPermission.ensureAccess() else { return }
        guard let id = session.begin() else { return }
        onCaptureStarted?()
        previousApplication = previous?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : previous
        let displays = NSScreen.screens.compactMap { screen -> ScreenCaptureService.Display? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return ScreenCaptureService.Display(id: number.uint32Value, frame: screen.frame)
        }
        escapeShortcut = GlobalShortcut(keyCode: UInt32(kVK_Escape), modifiers: 0, identifier: 2) { [weak self] in
            self?.cancel()
        }
        let signpost = OSSignpostID(log: log)
        captureSignpost = signpost
        os_signpost(.begin, log: log, name: "Invocation to overlay", signpostID: signpost)
        preparation = Task { [weak self] in
            do {
                let images = try await ScreenCaptureService.capture(displays: displays)
                guard let self, !Task.isCancelled, self.session.prepared(id) else { return }
                self.preparation = nil
                guard !images.isEmpty else { throw CaptureError.displayUnavailable }
                self.present(images)
                self.endCaptureSignpost()
            } catch {
                guard let self, self.session.id == id else { return }
                if !(error is CancellationError) {
                    let failure = error as NSError
                    os_log("Capture failed: domain=%{public}@ code=%ld preflight=%{public}@", log: self.log,
                           type: .error, failure.domain, failure.code, ScreenPermission.hasAccess ? "granted" : "denied")
                }
                self.finish(restoreFocus: true)
                if ScreenCaptureService.isPermissionDenied(error) {
                    _ = ScreenPermission.ensureAccess(afterCaptureDenied: true)
                } else if !(error is CancellationError) {
                    self.showError(error)
                }
            }
        }
    }

    private func present(_ images: [DisplaySnapshot]) {
        // Once panels own keyboard focus, Escape belongs to their responder chain.
        // In particular, Escape in the save panel must cancel just that panel.
        escapeShortcut = nil
        // Every image is obtained before any capture window is made visible.
        for snapshot in images {
            snapshots[snapshot.displayID] = snapshot
            let view = CaptureOverlayView(snapshot: snapshot, document: document)
            let panel = CaptureOverlayPanel(frame: snapshot.frame)
            panel.contentView = view
            panel.makeFirstResponder(view)
            view.onBeginSelection = { [weak self] in self?.beginSelection() ?? false }
            view.onSelect = { [weak self] rectangle in self?.selected(rectangle, on: snapshot.displayID) }
            view.onMoveSelection = { [weak self] rectangle in _ = self?.session.moveSelection(to: rectangle) }
            view.onResizeSelection = { [weak self] rectangle in _ = self?.session.resizeSelection(to: rectangle) }
            view.onCancel = { [weak self] in self?.cancel() }
            view.onCopy = { [weak self] in self?.copy() }
            view.onSave = { [weak self] in self?.save() }
            view.onUpload = { [weak self] in self?.upload() }
            view.onStartOver = { [weak self] in self?.startOver() }
            panels[snapshot.displayID] = panel
        }
        refreshUploadAvailability()
        NSApp.activate(ignoringOtherApps: true)
        for panel in panels.values { panel.orderFrontRegardless() }
        let pointer = NSEvent.mouseLocation
        let active = panels.values.first(where: { $0.frame.contains(pointer) }) ?? panels.values.first
        active?.makeKey()
        NSCursor.crosshair.set()
    }

    private func beginSelection() -> Bool {
        guard session.phase == .selecting else { return false }
        guard session.beginSelection() else { return false }
        for panel in panels.values { (panel.contentView as? CaptureOverlayView)?.clearSelection() }
        return true
    }

    private func selected(_ rectangle: CGRect, on displayID: CGDirectDisplayID) {
        let signpost = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "Release to toolbar", signpostID: signpost)
        guard session.select(displayID: displayID, rectangle: rectangle) else {
            os_signpost(.end, log: log, name: "Release to toolbar", signpostID: signpost)
            return
        }
        (panels[displayID]?.contentView as? CaptureOverlayView)?.showToolbar()
        os_signpost(.end, log: log, name: "Release to toolbar", signpostID: signpost)
    }

    private func crop() throws -> CGImage {
        guard let selection = session.selection, let snapshot = snapshots[selection.displayID] else {
            throw CaptureError.invalidSelection
        }
        return try ScreenshotExporter.compose(image: snapshot.image, selection: selection.rectangle,
                                              logicalSize: snapshot.logicalSize,
                                              annotations: (panels[selection.displayID]?.contentView as? CaptureOverlayView)?.exportAnnotations ?? document.annotations)
    }

    private func prepareOutput() -> Bool {
        guard let selection = session.selection,
              let view = panels[selection.displayID]?.contentView as? CaptureOverlayView else { return false }
        return view.prepareForExport()
    }

    private func startOver() {
        guard session.phase == .ready, let selection = session.selection,
              let view = panels[selection.displayID]?.contentView as? CaptureOverlayView else { return }
        view.clearAnnotations()
    }

    private func setExporting(_ exporting: Bool) {
        for panel in panels.values { (panel.contentView as? CaptureOverlayView)?.isExporting = exporting }
    }

    private func refreshUploadAvailability() {
        for panel in panels.values {
            (panel.contentView as? CaptureOverlayView)?.toolbar.setUploadAvailability(uploads?.canUpload == true,
                hint: uploads?.uploadHint ?? "Sign in from the Snap menu to upload")
        }
    }

    private func upload() {
        guard let uploads, uploads.canUpload, session.phase == .ready, prepareOutput(),
              let id = session.beginExport() else { return }
        setExporting(true)
        do {
            let image = try crop()
            exportTask = Task { [weak self] in
                do {
                    let png = try await Task.detached(priority: .userInitiated) { try ScreenshotExporter.png(image: image) }.value
                    guard let self, !Task.isCancelled, self.session.isExporting(id) else { return }
                    let job = try await uploads.stage(png)
                    guard !Task.isCancelled, self.session.isExporting(id) else {
                        uploads.discardLocal(); return
                    }
                    self.finish(restoreFocus: true)
                    uploads.begin(job)
                } catch { self?.exportFailed(error, id: id) }
            }
        } catch { exportFailed(error, id: id) }
    }

    private func copy() {
        guard session.phase == .ready, prepareOutput() else { return }
        guard let id = session.beginExport() else { return }
        setExporting(true)
        do {
            let image = try crop()
            exportTask = Task { [weak self] in
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        try ScreenshotExporter.png(image: image)
                    }.value
                    guard let self, !Task.isCancelled, self.session.isExporting(id) else { return }
                    let item = NSPasteboardItem()
                    guard item.setData(data, forType: .png) else { throw CaptureError.clipboardFailed }
                    // No await between the cancellation check and the clipboard side effect.
                    NSPasteboard.general.clearContents()
                    guard NSPasteboard.general.writeObjects([item]) else { throw CaptureError.clipboardFailed }
                    self.finish(restoreFocus: true)
                } catch { self?.exportFailed(error, id: id) }
            }
        } catch { exportFailed(error, id: id) }
    }

    private func save() {
        guard session.phase == .ready, prepareOutput() else { return }
        guard let id = session.beginExport() else { return }
        setExporting(true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Snap-\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted)).replacingOccurrences(of: ":", with: "-" )).png"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        savePanel = panel
        panel.begin { [weak self] result in
            guard let self, self.session.isExporting(id) else { return }
            self.savePanel = nil
            guard result == .OK, let url = panel.url else {
                self.resumeExport(id)
                return
            }
            do {
                let image = try self.crop()
                self.exportTask = Task { [weak self] in
                    do {
                        let data = try await Task.detached(priority: .userInitiated) {
                            try ScreenshotExporter.png(image: image)
                        }.value
                        guard let self, !Task.isCancelled, self.session.isExporting(id) else { return }
                        // Commit the atomic file write after the final cancellation check.
                        try data.write(to: url, options: .atomic)
                        self.finish(restoreFocus: true)
                    } catch { self?.exportFailed(error, id: id) }
                }
            } catch { self.exportFailed(error, id: id) }
        }
    }

    private func resumeExport(_ id: UUID) {
        guard session.resumeAfterExport(id) else { return }
        exportTask = nil
        setExporting(false)
        if let selection = session.selection {
            panels[selection.displayID]?.makeKey()
        }
    }

    private func exportFailed(_ error: Error, id: UUID) {
        guard session.isExporting(id) else { return }
        resumeExport(id)
        if !(error is CancellationError) { showError(error) }
    }

    func cancel() { finish(restoreFocus: true) }

    private func finish(restoreFocus: Bool) {
        guard session.phase != .idle else { return }
        session.cancel()
        preparation?.cancel()
        preparation = nil
        exportTask?.cancel()
        exportTask = nil
        savePanel?.cancel(nil)
        savePanel = nil
        escapeShortcut = nil
        for panel in panels.values { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        snapshots.removeAll()
        document.reset()
        NSCursor.arrow.set()
        endCaptureSignpost()
        if restoreFocus, let previousApplication, !previousApplication.isTerminated,
           previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
        onCaptureEnded?()
    }

    private func endCaptureSignpost() {
        if let captureSignpost {
            os_signpost(.end, log: log, name: "Invocation to overlay", signpostID: captureSignpost)
        }
        captureSignpost = nil
    }

    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Snap couldn’t finish the screenshot"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        alert.runModal()
    }
}
