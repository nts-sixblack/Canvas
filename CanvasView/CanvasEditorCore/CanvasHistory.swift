import Foundation

public struct CanvasHistory<Value> {
    private var undoStack: [Value] = []
    private var redoStack: [Value] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func record(currentValue: Value) {
        undoStack.append(currentValue)
        redoStack.removeAll()
    }

    public mutating func undo(currentValue: Value) -> Value? {
        guard let previous = undoStack.popLast() else {
            return nil
        }
        redoStack.append(currentValue)
        return previous
    }

    public mutating func redo(currentValue: Value) -> Value? {
        guard let next = redoStack.popLast() else {
            return nil
        }
        undoStack.append(currentValue)
        return next
    }

    public mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
