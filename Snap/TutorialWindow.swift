import AppKit
import SwiftUI

@MainActor
final class TutorialWindow: ObservableObject {
    static let shownKey = "hasShownTutorial"
    @Published private(set) var step = 0
    private let defaults: UserDefaults
    private(set) var window: NSWindow?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func showOnFirstLaunch() {
        guard !defaults.bool(forKey: Self.shownKey) else { return }
        show()
    }

    func show() {
        step = 0
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Snap Tutorial"
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: TutorialView(tutorial: self))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // Showing it once is enough: skipping or closing must also prevent a repeat.
        defaults.set(true, forKey: Self.shownKey)
    }

    func next() {
        if step == TutorialStep.all.count - 1 { hide() }
        else { step += 1 }
    }

    func back() { step = max(0, step - 1) }
    func hide() { window?.orderOut(nil) }
}

struct TutorialStep {
    let title: String
    let detail: String
    let tip: String

    static let all: [TutorialStep] = [
        TutorialStep(title: "Take your first screenshot",
                     detail: "Press ⌘⇧7 to select an area and annotate it. Use ⌘⇧6 to select an area and copy it immediately. Both options are also in the Snap menu.",
                     tip: "Allow Screen Recording when macOS asks. Copy with ⌘C or save a PNG with ⌘S."),
        TutorialStep(title: "Adjust your screenshot area",
                     detail: "Drag the border to move the selected area. Drag any corner or the black handle at the middle of an edge to resize it.",
                     tip: "Drag the six-dot handle to move the toolbar."),
        TutorialStep(title: "Share through Google Drive",
                     detail: "Open the Snap menu and choose “Sign in with Google…”. Click the Google sign-in button, then finish signing in in your browser.",
                     tip: "After a capture, click the cloud-arrow icon for “Upload & Copy Link”. Screenshots go to Snap Screenshots in your Drive; anyone with a screenshot’s link can view it."),
        TutorialStep(title: "Make your point with annotations",
                     detail: "Choose a tool from the tool menu. Rectangle and Ellipse offer outline or filled styles. With “Blur”, drag over an area and adjust its strength. With “Number stamps”, click to place colored circles with white numbers: 1, 2, 3… Other marks use color, line width, or text size.",
                     tip: "“Select” moves or deletes marks; double-click text to edit it. Use ⌘Z to undo and ⌘⇧Z to redo."),
        TutorialStep(title: "Switch tools without slowing down",
                     detail: "Hold Space to use the pointer (“Select”) tool. Release it to return to your previous tool. Press Tab to cycle through all tools, or Shift+Tab to cycle backward.",
                     tip: "While editing text, Space and Tab keep their normal typing behavior. Reopen this guide anytime from Snap → “Tutorial…”."),
    ]
}

private struct TutorialView: View {
    @ObservedObject var tutorial: TutorialWindow

    var body: some View {
        let page = TutorialStep.all[tutorial.step]
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("GET TO KNOW SNAP").font(.caption.weight(.semibold)).tracking(2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(tutorial.step + 1) / \(TutorialStep.all.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            TutorialIllustration(step: tutorial.step).frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(page.title).font(.system(size: 25, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(page.detail).font(.system(size: 14)).lineSpacing(4)
                Text(page.tip).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Skip tutorial") { tutorial.hide() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                ForEach(0..<TutorialStep.all.count, id: \.self) { index in
                    Circle().fill(index == tutorial.step ? Color.white : Color.white.opacity(0.2))
                        .frame(width: 5, height: 5)
                }
                Spacer()
                Button("Back") { tutorial.back() }.disabled(tutorial.step == 0)
                Button { tutorial.next() } label: {
                    Text(tutorial.step == TutorialStep.all.count - 1 ? "Done" : "Next")
                        .foregroundStyle(.black).padding(.horizontal, 16).padding(.vertical, 7)
                        .background(.white, in: RoundedRectangle(cornerRadius: 7))
                }.keyboardShortcut(.defaultAction).buttonStyle(.plain)
            }
        }
        .padding(30)
        .frame(width: 620, height: 540)
        .background(LinearGradient(colors: [Color(white: 0.10), Color(white: 0.045)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
    }
}

private struct TutorialIllustration: View {
    let step: Int

    var body: some View {
        switch step {
        case 0:
            HStack(spacing: 28) {
                keycap("⌘⇧7")
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                crop(resizing: false)
            }
        case 1:
            crop(resizing: true)
        case 2:
            HStack(spacing: 22) {
                icon("person.crop.circle", label: "Sign in")
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                icon("icloud.and.arrow.up", label: "Upload")
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                icon("link", label: "Copy link")
            }
        case 3:
            HStack(spacing: 14) {
                icon("cursorarrow", label: "Select")
                icon("pencil.tip", label: "Pen")
                icon("arrow.up.right", label: "Arrow")
                icon("line.diagonal", label: "Line")
                icon("rectangle", label: "Rectangle")
                icon("oval", label: "Ellipse")
                icon("textformat", label: "Text")
                icon("drop.halffull", label: "Blur")
            }
        default:
            HStack(spacing: 48) {
                VStack(spacing: 12) { keycap("Space"); Text("Hold for Select").font(.caption).foregroundStyle(.secondary) }
                VStack(spacing: 12) { keycap("Tab ⇥"); Text("Cycle tools").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 23, weight: .medium, design: .monospaced))
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.2)))
            .shadow(color: .black.opacity(0.3), radius: 0, y: 4)
    }

    private func icon(_ symbol: String, label: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 24)).frame(height: 30)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func crop(resizing: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.05))
            RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            Image(systemName: resizing ? "arrow.up.left.and.arrow.down.right" : "viewfinder")
                .font(.system(size: 28)).foregroundStyle(.white.opacity(0.7))
            if resizing {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 20)).offset(x: -100)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 17)).padding(6).background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 5))
                    .offset(x: 100, y: 45)
            }
        }.frame(width: resizing ? 200 : 140, height: 90)
    }
}
