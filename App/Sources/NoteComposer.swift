import SwiftUI
import MeetingNotesCore

struct NoteComposer: View {
    @Binding var text: String
    @Binding var category: String
    let categories: [String]
    let onSubmit: () -> Void
    var focusOnAppear = true
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Note…", text: $text, axis: .vertical)
                .lineLimit(4...10)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 96, alignment: .top)
                .focused($focused)
                .onSubmit(onSubmit)
            categoryChips
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
