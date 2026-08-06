import SwiftUI
import MeetingNotesCore

struct NoteComposer: View {
    @Binding var text: String
    @Binding var category: String
    let categories: [String]
    let onSubmit: () -> Void
    var focusOnAppear = true
    var chipsAboveField = false
    var onFocusLost: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chipsAboveField { categoryChips }
            TextField("Note…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(onSubmit)
                .onChange(of: focused) { _, isFocused in
                    if isFocused {
                        // macOS selects all prefilled text when the field gains focus;
                        // put the caret at the end so typing appends, not replaces.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                                editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
                            }
                        }
                    } else {
                        onFocusLost?()
                    }
                }
            if !chipsAboveField { categoryChips }
        }
        .onAppear { if focusOnAppear { focused = true } }
    }

    private var categoryChips: some View {
        HStack(spacing: 6) {
            ForEach(Array(categories.enumerated()), id: \.element) { i, cat in
                let isSelected = category == cat
                let button = Button {
                    category = cat
                } label: {
                    Text("\(i + 1) \(cat)")
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isSelected ? categoryColor(cat, categories: categories) : Color.clear,
                                    in: Capsule())
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .overlay(Capsule().stroke(isSelected ? Color.clear : Color.secondary.opacity(0.4)))
                }
                .buttonStyle(.plain)
                // CategoryHotkey.digitCharacter is nil for a 10th+ category
                // (index >= 9); ⌘-digit shortcuts only span 1-9, and the
                // unguarded Character("\(i + 1)") this replaces traps at
                // runtime once i reaches 9 ("10" is not a single character).
                if let digit = CategoryHotkey.digitCharacter(forIndex: i) {
                    button.keyboardShortcut(KeyEquivalent(digit), modifiers: [.command])
                } else {
                    button
                }
            }
        }.font(.caption)
    }
}
