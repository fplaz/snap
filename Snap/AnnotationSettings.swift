import AppKit
import Combine

struct AnnotationDefaults: Codable, Equatable {
    var tool: AnnotationTool = .rectangle
    var style = AnnotationStyle()
}

@MainActor
final class AnnotationSettings: ObservableObject {
    private enum Key {
        static let defaults = "annotationDefaults"
        static let lastUsed = "lastUsedAnnotationSettings"
        static let remember = "useLastUsedAnnotationSettings"
    }

    private let storage: UserDefaults
    @Published var defaults: AnnotationDefaults {
        didSet { save(defaults, key: Key.defaults) }
    }
    @Published var useLastUsed: Bool {
        didSet { storage.set(useLastUsed, forKey: Key.remember) }
    }
    private var lastUsed: AnnotationDefaults {
        didSet { save(lastUsed, key: Key.lastUsed) }
    }

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        let saved = storage.data(forKey: Key.defaults)
            .flatMap { try? JSONDecoder().decode(AnnotationDefaults.self, from: $0) } ?? AnnotationDefaults()
        defaults = saved
        lastUsed = storage.data(forKey: Key.lastUsed)
            .flatMap { try? JSONDecoder().decode(AnnotationDefaults.self, from: $0) } ?? saved
        useLastUsed = storage.bool(forKey: Key.remember)
    }

    var initial: AnnotationDefaults { useLastUsed ? lastUsed : defaults }

    func beginCapture() -> AnnotationDefaults {
        let value = initial
        lastUsed = value
        return value
    }

    func record(tool: AnnotationTool) { lastUsed.tool = tool }
    func record(style: AnnotationStyle) { lastUsed.style = style }

    private func save(_ value: AnnotationDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        storage.set(data, forKey: key)
    }
}
