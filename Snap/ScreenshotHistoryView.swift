import SwiftUI
import AppKit
import Combine
import GoogleSignInSwift

struct ScreenshotHistoryView: View {
    @ObservedObject var account: AccountController
    @ObservedObject var uploads: UploadCoordinator
    @ObservedObject var history: ScreenshotHistoryController
    let signIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if account.id != nil {
                HStack {
                    Text("My Screenshots").font(.title2.weight(.semibold))
                    Button { history.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh screenshots").disabled(history.isLoading)
                    Spacer()
                    if let email = account.email {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                        Button("Sign Out") { account.signOut() }.disabled(account.isSigningIn)
                    }
                }
            }
            if account.id == nil {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "icloud.and.arrow.up").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("Your screenshots, in your Google Drive").font(.headline)
                    Text("Uploads are viewable by anyone with the link. Your Snap folder stays private.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    GoogleSignInButton(action: signIn).frame(width: 220)
                        .disabled(!account.configured || account.isSigningIn)
                    if account.isSigningIn {
                        ProgressView().controlSize(.small)
                        Button("Cancel Sign In") { account.cancelSignIn() }
                    }
                    if let message = account.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                if let message = account.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if uploads.pending != nil || (!uploads.status.isEmpty && uploads.status != "Link copied") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            if uploads.isWorking { ProgressView().controlSize(.small) }
                            Text(uploads.status).font(.callout)
                            Spacer()
                            if uploads.latestLink != nil { Button("Copy Link") { uploads.copyLatestLink() } }
                        }
                        if uploads.pending != nil {
                            HStack {
                                if uploads.needsReplacementFolder {
                                    Button("Create Replacement Folder & Retry") { uploads.replaceFolderAndRetry() }
                                        .disabled(uploads.isWorking)
                                } else { Button("Retry") { uploads.retry() }.disabled(uploads.isWorking) }
                                Button("Discard Local Copy") { uploads.discardLocal() }
                                Text("Discard leaves any uploaded file in Drive.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                if let message = history.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if history.files.isEmpty && !history.isLoading && history.message == nil {
                    Spacer()
                    Text("No uploads yet. Capture an area and use Upload & Copy Link.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(history.files) { file in card(file) }
                        }
                        if history.nextPage != nil { Button("Load More") { history.loadMore() }.disabled(history.isLoading).padding() }
                    }
                }
                if history.isLoading { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460)
        .background(Color(nsColor: NSColor(white: 0.045, alpha: 1)))
        .preferredColorScheme(.dark)
    }

    private func card(_ file: DriveFile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Rectangle().fill(.white.opacity(0.035))
                if let image = history.thumbnails[file.id] {
                    Image(nsImage: image).resizable().scaledToFit()
                } else { Image(systemName: "photo").font(.title).foregroundStyle(.secondary) }
            }.frame(height: 130).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                .onAppear { history.requestThumbnail(file.id) }
            Text(file.name ?? "Screenshot").font(.callout).lineLimit(1)
            if let date = file.createdDate {
                Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(file.isPublic ? "Copy Link" : "Retry Sharing") { history.copyLink(file, retrySharing: !file.isPublic) }
                    .disabled(history.actionID != nil)
                Spacer()
                Button { if let url = file.viewingURL { NSWorkspace.shared.open(url) } } label: { Image(systemName: "arrow.up.right.square") }
                    .help("Open in Drive").disabled(file.viewingURL == nil)
            }.font(.caption)
        }.padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

@MainActor
final class ScreenshotHistoryWindow {
    private var window: NSWindow?
    private let account: AccountController
    private let uploads: UploadCoordinator
    private let history: ScreenshotHistoryController
    private var accountObservation: AnyCancellable?
    init(account: AccountController, uploads: UploadCoordinator, history: ScreenshotHistoryController) {
        self.account = account; self.uploads = uploads; self.history = history
        accountObservation = account.$id.sink { [weak self] id in
            self?.window?.title = id == nil ? "Snap" : "Snap — My Screenshots"
        }
    }
    func hide() { window?.orderOut(nil) }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 780, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = account.id == nil ? "Snap" : "Snap — My Screenshots"
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: ScreenshotHistoryView(account: account, uploads: uploads, history: history,
                                                 signIn: { [weak account] in account?.signIn() }))
            window.center(); self.window = window
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
        if account.id != nil, history.files.isEmpty { history.refresh() }
    }
}
