import SwiftUI
import MeetingNotesCore

struct MenuContent: View {
    @Bindable var state: AppState
    @State private var meetingName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = state.activeSession {
                Label(session.name, systemImage: "record.circle")
                    .foregroundStyle(.red)
                Text("\(session.notes.count) notes").font(.caption).foregroundStyle(.secondary)
                Button("End Meeting") { state.endMeeting() }
                    .keyboardShortcut("e")
            } else {
                TextField("Meeting name (optional)", text: $meetingName)
                    .onSubmit { start() }
                Button("Start Meeting") { start() }
                    .keyboardShortcut(.defaultAction)
            }
            Divider()
            Button("Open Sessions Folder") {
                NSWorkspace.shared.open(state.store.rootURL)
            }
            if let error = state.lastError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.caption).lineLimit(3)
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { state.refresh() }
    }

    private func start() {
        state.startMeeting(named: meetingName)
        meetingName = ""
    }
}
