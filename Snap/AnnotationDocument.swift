import Foundation

final class AnnotationDocument {
    private(set) var annotations: [Annotation] = []
    private var undoStates: [[Annotation]] = []
    private var redoStates: [[Annotation]] = []
    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }

    func set(_ values: [Annotation]) {
        guard values != annotations else { return }
        undoStates.append(annotations)
        redoStates.removeAll()
        annotations = values
    }

    func commit(_ annotation: Annotation) {
        var values = annotations
        if let index = values.firstIndex(where: { $0.id == annotation.id }) {
            if annotation.isEmpty { values.remove(at: index) } else { values[index] = annotation }
        } else if !annotation.isEmpty { values.append(annotation) }
        set(values)
    }

    func delete(_ id: UUID) { set(annotations.filter { $0.id != id }) }
    func hit(at point: CGPoint) -> Annotation? { annotations.reversed().first { $0.hitTest(point) } }
    func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(annotations)
        annotations = previous
    }
    func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(annotations)
        annotations = next
    }
    func reset() { annotations = []; undoStates = []; redoStates = [] }
}
