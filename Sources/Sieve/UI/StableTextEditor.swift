import SwiftUI
import AppKit

/// A text box that does not fight you while you type in it.
///
/// SwiftUI's `TextEditor` bound straight to a store is unusable for notes: every keystroke
/// writes to SQLite, the store republishes, the whole view tree is rebuilt, and the text view
/// underneath is handed its value again. The insertion point jumps to the end, so correcting a
/// word in the middle of a sentence rewrites the tail of it, and the field's own undo history
/// is destroyed on every character.
///
/// This owns its text instead. While the box has focus it is the only writer: the outer binding
/// is updated on a short pause and again when focus leaves, and incoming values are ignored
/// unless they came from somewhere other than this field. The insertion point stays where you
/// put it, ⌘Z inside the box undoes your typing word by word, and a correction in the middle of
/// a paragraph stays a correction.
struct StableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 13)
    var placeholder: String = ""
    /// Seconds of not typing before the value is written out. Long enough that a sentence is
    /// one save, short enough that closing the window never loses a line.
    var debounce: TimeInterval = 0.5
    var onCommit: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.font = font
        tv.allowsUndo = true                       // ⌘Z inside the field, per field
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 5)
        tv.string = text
        tv.setSelectedRange(NSRange(location: text.utf16.count, length: 0))

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        context.coordinator.textView = tv
        context.coordinator.lastPushed = text
        context.coordinator.parent = self
        context.coordinator.updatePlaceholder(placeholder)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.font != font { tv.font = font }
        context.coordinator.updatePlaceholder(placeholder)

        // The only case where the outside is allowed to win: the field is not being typed in
        // and the value genuinely changed elsewhere (a different note opened, an undo, an
        // import). Anything else would be the store echoing back what we just sent it.
        let focused = tv.window?.firstResponder === tv
        if !focused, tv.string != text, context.coordinator.lastPushed != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, text.utf16.count), length: 0))
            context.coordinator.lastPushed = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StableTextEditor
        weak var textView: NSTextView?
        var lastPushed: String = ""
        private var timer: Timer?
        private var placeholderLabel: NSTextField?

        init(_ parent: StableTextEditor) { self.parent = parent }

        func updatePlaceholder(_ text: String) {
            guard let tv = textView else { return }
            if text.isEmpty {
                placeholderLabel?.removeFromSuperview()
                placeholderLabel = nil
                return
            }
            if placeholderLabel == nil {
                let label = NSTextField(labelWithString: text)
                label.textColor = .tertiaryLabelColor
                label.font = tv.font
                label.translatesAutoresizingMaskIntoConstraints = false
                label.isSelectable = false
                tv.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 8),
                    label.topAnchor.constraint(equalTo: tv.topAnchor, constant: 5),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: tv.trailingAnchor, constant: -4)
                ])
                placeholderLabel = label
            }
            placeholderLabel?.stringValue = text
            placeholderLabel?.isHidden = !tv.string.isEmpty
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            placeholderLabel?.isHidden = !tv.string.isEmpty
            schedulePush(tv.string)
        }

        /// Leaving the field always saves, so a note is never lost by clicking away from it.
        func textDidEndEditing(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            timer?.invalidate(); timer = nil
            push(tv.string)
        }

        private func schedulePush(_ value: String) {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: parent.debounce, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.push(value) }
            }
        }

        private func push(_ value: String) {
            guard value != lastPushed else { return }
            lastPushed = value
            parent.text = value
            parent.onCommit?(value)
        }

        deinit { timer?.invalidate() }
    }
}

/// A labelled note box. Used everywhere a long-form field is edited so they all behave the same.
struct NoteField: View {
    let label: String
    @Binding var text: String
    var height: CGFloat = 90
    var font: NSFont = .systemFont(ofSize: 13)
    var placeholder: String = ""
    var onCommit: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty { SectionLabel(text: label) }
            StableTextEditor(text: $text, font: font, placeholder: placeholder, onCommit: onCommit)
                .frame(minHeight: height)
                .background(D.surface)
                .clipShape(RoundedRectangle(cornerRadius: D.radius))
                .hairlineBorder()
        }
    }
}

/// The note box that appears on the passage you just marked.
///
/// It is a small floating card rather than a row in the inspector on purpose. A highlight
/// list grows all day, and the thing you want to annotate is always the thing you just made —
/// which is precisely the row furthest from the top of a list in page order. Annotating had
/// become a scroll to the bottom of the panel, and deleting a mistake had become the same
/// trip. Here the note is written where the passage is, and closing the card is the only step.
struct HighlightNoteBox: View {
    let evidence: Evidence
    var onClose: () -> Void
    var onReveal: () -> Void

    @EnvironmentObject var store: Store
    @State private var note: String = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: D.s2) {
            HStack(spacing: 5) {
                Chip(text: evidence.stance.label, color: evidence.stance.color, icon: evidence.stance.icon)
                ForEach(evidence.tagIds.compactMap { store.tag($0) }) { t in
                    Chip(text: t.name, color: t.color)
                }
                Spacer()
                if evidence.page >= 0 {
                    Button { onReveal() } label: {
                        Text("p.\(evidence.page + 1)").font(D.mono).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain).help("Go back to this passage")
                }
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 9)).accessibilityHidden(true)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Close the note")
            }

            // The passage is passed in as a value, so it is on screen the instant the box is.
            // It used to be copied into the box's own state as the box appeared, which is why
            // the quote stayed blank until the first keystroke redrew it.
            Text(evidence.quote)
                .font(D.serif).lineLimit(4)
                .padding(.leading, D.s2)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(hex: evidence.colorHex)).frame(width: 3)
                }

            StableTextEditor(text: $note,
                             placeholder: "Why does this matter?",
                             onCommit: save)
                .frame(height: 78)
                .background(D.surface)
                .clipShape(RoundedRectangle(cornerRadius: D.radius))
                .hairlineBorder()

            HStack(spacing: D.s2) {
                Button(role: .destructive) {
                    store.deleteEvidence(evidence.id)
                    store.flash("Highlight removed — ⌘Z brings it back")
                    onClose()
                } label: {
                    Label("Delete", systemImage: "trash").font(D.small)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Remove this highlight without leaving the page")
                Spacer()
                Text("⌘Z undoes · esc closes").font(.system(size: 9)).foregroundStyle(.tertiary)
                Button("Done") { save(note); onClose() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(D.s3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: D.radiusL))
        .overlay(RoundedRectangle(cornerRadius: D.radiusL).stroke(D.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
        // `id` rather than `onAppear` alone: pointing the box at a different highlight has to
        // reload the draft, and a box that only seeds itself once shows the previous note.
        .id(evidence.id)
        .onAppear {
            note = evidence.note
            loaded = true
        }
    }

    private func save(_ value: String) {
        guard loaded, value != evidence.note else { return }
        var e = evidence
        e.note = value
        store.updateEvidence(e, undoName: "a note", coalesceKey: "note-\(evidence.id)")
    }
}

/// Catches a right-click without taking anything else.
///
/// SwiftUI has no secondary-click gesture, and `contextMenu` builds its items as part of the
/// view's body — which is exactly the cost that used to freeze the highlight board. This
/// answers `hitTest` only while a right-click is being dispatched, so ordinary clicks, drags
/// and text selection pass straight through to the view underneath, and the menu it opens is
/// built at the moment it is asked for.
struct RightClickCatcher: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = Catcher()
        v.onRightClick = onRightClick
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Catcher)?.onRightClick = onRightClick
    }

    final class Catcher: NSView {
        var onRightClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp: return self
            default: return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) { onRightClick?() }
    }
}
