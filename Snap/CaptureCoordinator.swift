import AppKit
import Carbon
import UniformTypeIdentifiers
import os
import Combine

@MainActor
final class CaptureCoordinator {
    var onCaptureStarted: (() -> Void)?
    var onCaptureEnded: (() -> Void)?
    var isActive: Bool { session.phase != .idle || !editors.isEmpty }
    private let uploads: UploadCoordinator?
    private let settings: AnnotationSettings
    private var uploadObservation: AnyCancellable?
    private var session = CaptureSession()
    private var document = AnnotationDocument()
    private var editorWindow: ScreenshotEditorWindow?
    private var editors: [UUID: CaptureCoordinator] = [:]
    private var activeView: CaptureOverlayView? {
        if let editorWindow { return editorWindow.canvas }
        guard let selection = session.selection else { return nil }
        return panels[selection.displayID]?.contentView as? CaptureOverlayView
    }
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

    init(uploads: UploadCoordinator? = nil, settings: AnnotationSettings? = nil) {
        self.uploads = uploads
        self.settings = settings ?? AnnotationSettings()
        uploadObservation = uploads?.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refreshUploadAvailability() }
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.editorWindow == nil else { return }
                self.cancel()
            }
        }
    }

    deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
    }

    func start(mode: CaptureSession.Mode = .annotate) {
        guard session.phase == .idle else { return }
        let previous = NSWorkspace.shared.frontmostApplication
        guard ScreenPermission.ensureAccess() else { return }
        guard let id = session.begin(mode: mode) else { return }
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
            let view = CaptureOverlayView(snapshot: snapshot, document: document, settings: settings)
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
            view.onPopOut = { [weak self] in self?.popOut() }
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
        if session.mode == .copy {
            copy()
        } else {
            (panels[displayID]?.contentView as? CaptureOverlayView)?.showToolbar()
        }
        os_signpost(.end, log: log, name: "Release to toolbar", signpostID: signpost)
    }

    private func crop() throws -> CGImage {
        guard let selection = session.selection, let snapshot = snapshots[selection.displayID] else {
            throw CaptureError.invalidSelection
        }
        return try ScreenshotExporter.compose(image: snapshot.image, selection: selection.rectangle,
                                              logicalSize: snapshot.logicalSize,
                                              annotations: activeView?.exportAnnotations ?? document.annotations)
    }

    private func prepareOutput() -> Bool {
        activeView?.prepareForExport() ?? false
    }

    private func startOver() {
        guard session.phase == .ready, let view = activeView else { return }
        view.clearAnnotations()
    }

    private func popOut() {
        guard session.phase == .ready, let id = session.id, let selection = session.selection,
              let snapshot = snapshots[selection.displayID], let view = activeView,
              view.prepareForEditor() else { return }
        let editor = CaptureCoordinator(uploads: uploads, settings: settings)
        editor.session = session
        editor.document = document
        editor.snapshots = [snapshot.displayID: snapshot]
        let window = ScreenshotEditorWindow(canvas: view)
        editor.editorWindow = window
        view.onCopy = { [weak editor] in editor?.copy() }
        view.onSave = { [weak editor] in editor?.save() }
        view.onUpload = { [weak editor] in editor?.upload() }
        view.onStartOver = { [weak editor] in editor?.startOver() }
        view.onCancel = { [weak window] in window?.requestClose() }
        view.onPopOut = nil
        window.onClose = { [weak editor] in editor?.cancel() }
        editor.onCaptureEnded = { [weak self] in self?.editors.removeValue(forKey: id) }
        editors[id] = editor
        editor.refreshUploadAvailability()
        // Transfer ownership before resetting the overlay session.
        document = AnnotationDocument()
        finish(restoreFocus: false)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func setExporting(_ exporting: Bool) {
        editorWindow?.canvas.isExporting = exporting
        for panel in panels.values { (panel.contentView as? CaptureOverlayView)?.isExporting = exporting }
    }

    private func refreshUploadAvailability() {
        editorWindow?.canvas.toolbar.setUploadAvailability(uploads?.canUpload == true,
            hint: uploads?.uploadHint ?? "Sign in from the Snap menu to upload")
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
                    if let editorWindow = self.editorWindow {
                        self.resumeExport(id)
                        editorWindow.showCopyToast()
                    }
                    else { self.finish(restoreFocus: true) }
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
        panel.level = editorWindow == nil ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1) : .normal
        savePanel = panel
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] result in
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
        if let editorWindow { panel.beginSheetModal(for: editorWindow, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    private func resumeExport(_ id: UUID) {
        guard session.resumeAfterExport(id) else { return }
        exportTask = nil
        setExporting(false)
        editorWindow?.makeKeyAndOrderFront(nil)
        if let selection = session.selection {
            panels[selection.displayID]?.makeKey()
        }
    }

    private func exportFailed(_ error: Error, id: UUID) {
        guard session.isExporting(id) else { return }
        resumeExport(id)
        // Keep Copy available for a retry if the immediate clipboard write failed.
        if session.mode == .copy, let selection = session.selection {
            (panels[selection.displayID]?.contentView as? CaptureOverlayView)?.showToolbar()
        }
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
        editorWindow?.onClose = nil
        editorWindow?.close()
        editorWindow = nil
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
