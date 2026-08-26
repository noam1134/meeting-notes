import AppKit
import SwiftUI

/// Sizing for the note editor's viewport.
///
/// The editor grows with its content up to `maxLines` and then scrolls
/// instead of growing further. A nil `maxLines` grows without limit — what
/// the session browser wants, so an opened note keeps the height it had as
/// static text and the surrounding list scrolls as usual.
enum NoteEditorMetrics {
    static func viewportHeight(contentHeight: CGFloat, lineHeight: CGFloat, insets: CGFloat,
                               minLines: Int, maxLines: Int?) -> CGFloat {
        let smallest = CGFloat(minLines) * lineHeight + insets
        let grown = max(contentHeight + insets, smallest)
        guard let maxLines else { return grown }
        return min(grown, CGFloat(max(maxLines, minLines)) * lineHeight + insets)
    }

    static func isScrollable(contentHeight: CGFloat, viewportHeight: CGFloat, insets: CGFloat) -> Bool {
        contentHeight + insets > viewportHeight + 0.5
    }
}

/// Auto-growing, scrollable note editor.
///
/// Replaces `TextField(axis: .vertical).lineLimit(1...6)`: that caps its
/// AppKit field at 6 lines while the field editor keeps the full text, and
/// the field editor's clip view is an `_NSKeyboardFocusClipView` rather than
/// an `NSScrollView` — so overflowing text drew no scroller and ignored the
/// wheel, leaving arrow keys as the only way to reach it. A real
/// `NSScrollView` restores both.
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let font: NSFont
    var minLines = 1
    var maxLines: Int? = 6
    var focusOnAppear = true
    let onSubmit: () -> Void
    var onCancel: (() -> Void)?
    var onFocusLost: (() -> Void)?

    static let verticalInset: CGFloat = 2
    /// Matches the `lineSpacing(3)` the browser renders saved notes with, so
    /// entering edit mode doesn't reflow the text.
    static let lineSpacing: CGFloat = 3

    /// Viewport for an empty editor, so the first layout pass doesn't jump.
    static func collapsedHeight(font: NSFont) -> CGFloat {
        NoteEditorMetrics.viewportHeight(contentHeight: 0,
                                         lineHeight: NSLayoutManager().defaultLineHeight(for: font),
                                         insets: verticalInset * 2, minLines: 1, maxLines: 6)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SubmittingTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = font
        textView.textColor = .labelColor
        textView.isRichText = false
        textView.isEditable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: Self.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Self.lineSpacing
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? SubmittingTextView else { return }
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if textView.font != font { textView.font = font }
        context.coordinator.focusIfNeeded()
        context.coordinator.syncHeight()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        weak var textView: SubmittingTextView?
        weak var scrollView: NSScrollView?
        private var didFocus = false
        private var didFlashScrollers = false

        init(_ parent: NoteTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            syncHeight()
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusLost?()
        }

        /// The view has no window during the first update pass, so retry
        /// asynchronously until it's in one.
        func focusIfNeeded() {
            guard parent.focusOnAppear, !didFocus, let textView else { return }
            guard let window = textView.window else {
                DispatchQueue.main.async { [weak self] in self?.focusIfNeeded() }
                return
            }
            didFocus = true
            window.makeFirstResponder(textView)
            // Caret at the end so typing appends to a prefilled note.
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }

        func syncHeight() {
            guard let textView, let scrollView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let content = layoutManager.usedRect(for: container).height
            let font = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let insets = textView.textContainerInset.height * 2
            let viewport = NoteEditorMetrics.viewportHeight(
                contentHeight: content,
                lineHeight: layoutManager.defaultLineHeight(for: font),
                insets: insets, minLines: parent.minLines, maxLines: parent.maxLines)

            if abs(parent.height - viewport) > 0.5 {
                let binding = parent.$height
                DispatchQueue.main.async { binding.wrappedValue = viewport }
            }

            // Overlay scrollers are invisible at rest; flash them the first
            // time the text outgrows the viewport so the overflow is visible.
            if NoteEditorMetrics.isScrollable(contentHeight: content, viewportHeight: viewport, insets: insets) {
                if !didFlashScrollers {
                    didFlashScrollers = true
                    scrollView.flashScrollers()
                }
            } else {
                didFlashScrollers = false
            }
        }
    }
}

/// ⏎ saves (⇧⏎ / ⌥⏎ insert a line break) and esc cancels, matching the
/// composer's "⏎ save · esc cancel" hint. An `NSTextView` would otherwise
/// swallow both.
final class SubmittingTextView: NSTextView {
    var onSubmit: () -> Void = {}
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76   // return, keypad enter
        if isReturn {
            if event.modifierFlags.intersection([.shift, .option]).isEmpty {
                onSubmit()
            } else {
                insertNewlineIgnoringFieldEditor(self)
            }
            return
        }
        if event.keyCode == 53, let onCancel {   // esc
            onCancel()
            return
        }
        super.keyDown(with: event)
    }
}
