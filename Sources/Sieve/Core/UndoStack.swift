import Foundation
import SwiftUI

/// One reversible step of work.
///
/// Sieve edits go straight to SQLite, so "undo" cannot mean rolling back an in-memory
/// object graph. Every mutating call on `Store` instead registers the pair of database
/// operations that move the library backwards and forwards again. Undo is therefore just
/// another write — which is why redo can never desynchronise from what is on disk.
@MainActor
final class UndoStack: ObservableObject {

    struct Step {
        let name: String
        /// Groups keystroke-sized edits so typing a sentence is one undo, not forty.
        let coalesceKey: String?
        let at: Date
        let backwards: () -> Void
        let forwards: () -> Void
    }

    @Published private(set) var past: [Step] = []
    @Published private(set) var future: [Step] = []

    /// While an undo or redo is being applied the store still calls `record`; ignoring it
    /// here is what stops undo from pushing itself onto its own stack.
    private var applying = false
    private let limit = 250
    private let coalesceWindow: TimeInterval = 2.5

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var undoName: String { past.last.map { "Undo \($0.name)" } ?? "Undo" }
    var redoName: String { future.last.map { "Redo \($0.name)" } ?? "Redo" }

    func record(_ name: String,
                coalesceKey: String? = nil,
                backwards: @escaping () -> Void,
                forwards: @escaping () -> Void) {
        guard !applying else { return }

        // A run of edits to the same field collapses into the first step, so its
        // "backwards" still restores the text as it was before you started typing.
        if let key = coalesceKey, let last = past.last, last.coalesceKey == key,
           Date().timeIntervalSince(last.at) < coalesceWindow {
            past[past.count - 1] = Step(name: name, coalesceKey: key, at: Date(),
                                        backwards: last.backwards, forwards: forwards)
            future.removeAll()
            return
        }

        past.append(Step(name: name, coalesceKey: coalesceKey, at: Date(),
                         backwards: backwards, forwards: forwards))
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    @discardableResult
    func undo() -> String? {
        guard let step = past.popLast() else { return nil }
        applying = true
        step.backwards()
        applying = false
        future.append(step)
        return step.name
    }

    @discardableResult
    func redo() -> String? {
        guard let step = future.popLast() else { return nil }
        applying = true
        step.forwards()
        applying = false
        past.append(step)
        return step.name
    }

    /// Switching reviews makes every recorded step refer to rows in a library you are no
    /// longer looking at, so the history starts again rather than lying about what it can undo.
    func clear() {
        past.removeAll()
        future.removeAll()
    }
}

/// The undo and redo pair, wherever a toolbar has room for it.
struct UndoRedoButtons: View {
    @ObservedObject var history: UndoStack
    var store: Store

    var body: some View {
        HStack(spacing: 2) {
            Button {
                if let name = history.undo() { store.flash("Undid \(name.lowercased())") }
            } label: {
                Image(systemName: "arrow.uturn.backward").accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .disabled(!history.canUndo)
            .foregroundStyle(history.canUndo ? Color.primary : Color.secondary.opacity(0.35))
            .help(history.canUndo ? "\(history.undoName) (⌘Z)" : "Nothing to undo")
            .accessibilityLabel(history.undoName)

            Button {
                if let name = history.redo() { store.flash("Redid \(name.lowercased())") }
            } label: {
                Image(systemName: "arrow.uturn.forward").accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .disabled(!history.canRedo)
            .foregroundStyle(history.canRedo ? Color.primary : Color.secondary.opacity(0.35))
            .help(history.canRedo ? "\(history.redoName) (⇧⌘Z)" : "Nothing to redo")
            .accessibilityLabel(history.redoName)
        }
    }
}
