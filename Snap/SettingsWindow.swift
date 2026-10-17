import AppKit
import SwiftUI

@MainActor
final class SettingsWindow {
    private let settings: AnnotationSettings
    private(set) var window: NSWindow?

    init(settings: AnnotationSettings) { self.settings = settings }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Annotation tool settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() { window?.orderOut(nil) }
}

private struct SettingsView: View {
    @ObservedObject var settings: AnnotationSettings

    var body: some View {
        Form {
            Section {
                Toggle("Use last-used settings", isOn: $settings.useLastUsed)
                Text("Start each capture with the tool, color, and style you last used, even after quitting Snap.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Default annotation settings") {
                Picker("Starting tool", selection: $settings.defaults.tool) {
                    ForEach(AnnotationTool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Color", selection: $settings.defaults.style.color) {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        Label {
                            Text(color.rawValue.capitalized)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: color.nsColor))
                        }.tag(color)
                    }
                }
                Picker("Line / outline", selection: $settings.defaults.style.width) {
                    Text("Thin").tag(CGFloat(2))
                    Text("Medium").tag(CGFloat(4))
                    Text("Thick").tag(CGFloat(8))
                }
                Toggle("Filled shapes", isOn: $settings.defaults.style.isFilled)
                Picker("Text size", selection: $settings.defaults.style.fontSize) {
                    Text("Small").tag(CGFloat(16))
                    Text("Medium").tag(CGFloat(24))
                    Text("Large").tag(CGFloat(32))
                }
                HStack {
                    Text("Blur strength")
                    Slider(value: $settings.defaults.style.blurRadius, in: 1...12, step: 0.5)
                        .accessibilityLabel("Default blur strength")
                    Text(String(format: "%.1f", settings.defaults.style.blurRadius))
                        .monospacedDigit().frame(width: 30)
                }
            }
            .disabled(settings.useLastUsed)
            Text(settings.useLastUsed
                 ? "Turn off last-used settings to configure fixed defaults."
                 : "These defaults apply to each new capture. Changes save automatically.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 460)
    }
}
