import AppKit
import SwiftUI

struct UploadProgressView: View {
    @ObservedObject var uploads: UploadCoordinator
    let copyLink: () -> Void
    let close: () -> Void
    let reviewUpload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: uploads.isWorking ? "icloud.and.arrow.up" : (uploads.latestLink == nil ? "exclamationmark.circle" : "checkmark.circle"))
                    .foregroundStyle(.secondary)
                Text(uploads.isWorking ? "Uploading screenshot" : (uploads.latestLink == nil ? "Upload needs attention" : "Screenshot uploaded"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !uploads.isWorking {
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Close").accessibilityLabel("Close")
                }
            }
            if uploads.isWorking {
                UploadLoadingBar().frame(height: 6)
                Text(uploads.status).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let link = uploads.latestLink {
                Text(link.absoluteString).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text(uploads.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack {
                if !uploads.isWorking, uploads.latestLink == nil {
                    Button("Review upload", action: reviewUpload)
                }
                Spacer()
                Button(action: copyLink) {
                    Label("Copy link", systemImage: "doc.on.doc")
                }.disabled(uploads.isWorking || uploads.latestLink == nil)
            }.controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360, height: 130)
        .background(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14)))
        .preferredColorScheme(.dark)
    }
}

private struct UploadLoadingBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSProgressIndicator {
        let bar = NSProgressIndicator()
        bar.style = .bar
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        return bar
    }
    func updateNSView(_ bar: NSProgressIndicator, context: Context) { }
}

@MainActor
final class UploadProgressPanel {
    private let uploads: UploadCoordinator
    private let reviewUpload: () -> Void
    private var panel: NSPanel?
    private var wantsVisible = false
    private var captureInProgress = false

    init(uploads: UploadCoordinator, reviewUpload: @escaping () -> Void) {
        self.uploads = uploads; self.reviewUpload = reviewUpload
    }

    func show() {
        if panel == nil {
            let panel = UploadNotificationPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 130),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: UploadProgressView(uploads: uploads,
                copyLink: { [weak self] in self?.copyLinkAndClose() },
                close: { [weak self] in self?.close() },
                reviewUpload: { [weak self] in self?.close(); self?.reviewUpload() }))
            self.panel = panel
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            panel?.setFrame(Self.frame(in: screen.visibleFrame), display: false)
        }
        wantsVisible = true
        if !captureInProgress { panel?.orderFrontRegardless() }
    }

    static func frame(in visibleFrame: CGRect) -> CGRect {
        CGRect(x: visibleFrame.maxX - 360 - 20, y: visibleFrame.maxY - 130 - 20, width: 360, height: 130)
    }

    func close() {
        wantsVisible = false
        panel?.orderOut(nil)
    }

    func captureStarted() {
        captureInProgress = true
        panel?.orderOut(nil)
    }

    func captureEnded() {
        captureInProgress = false
        if wantsVisible { panel?.orderFrontRegardless() }
    }

    func copyLinkAndClose() {
        guard !uploads.isWorking, uploads.latestLink != nil else { return }
        uploads.copyLatestLink()
        close()
    }
}

private final class UploadNotificationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
