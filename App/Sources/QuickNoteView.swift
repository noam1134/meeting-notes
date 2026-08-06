import SwiftUI
import MeetingNotesCore

struct QuickNoteView: View {
    let state: AppState
    let dismiss: () -> Void
    @State private var text = ""
    @State private var category: String

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
            NoteComposer(text: $text, category: $category, categories: state.settings.categories, onSubmit: save)
        }
        .padding(14)
        .frame(width: 480)
        .onExitCommand(perform: dismiss)   // Esc
    }

    private func save() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return dismiss() }
        if state.activeSession == nil { state.startMeeting(named: nil) }
        state.addNote(text: text, category: category, imageData: nil)
        dismiss()
    }
}
