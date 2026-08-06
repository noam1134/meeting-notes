import SwiftUI
import MeetingNotesCore

struct QuickNoteView: View {
    let state: AppState
    let dismiss: () -> Void
    @State private var text = ""
    @State private var category: String
    @FocusState private var focused: Bool

    init(state: AppState, dismiss: @escaping () -> Void) {
        self.state = state
        self.dismiss = dismiss
        _category = State(initialValue: state.settings.categories.first ?? "FYI")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.activeSession == nil {
                Label("No active meeting — ⏎ starts one now", systemImage: "record.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            TextField("Quick note…", text: $text)
                .textFieldStyle(.plain).font(.title3)
                .focused($focused)
                .onSubmit(save)
            HStack(spacing: 6) {
                ForEach(Array(state.settings.categories.enumerated()), id: \.element) { i, cat in
                    Button("\(i + 1) \(cat)") { category = cat }
                        .buttonStyle(.bordered)
                        .tint(category == cat ? .accentColor : .secondary)
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command])
                }
            }.font(.caption)
        }
        .padding(14)
        .frame(width: 480)
        .onAppear { focused = true }
        .onExitCommand(perform: dismiss)   // Esc
    }

    private func save() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return dismiss() }
        if state.activeSession == nil { state.startMeeting(named: nil) }
        state.addNote(text: text, category: category, imageData: nil)
        dismiss()
    }
}
