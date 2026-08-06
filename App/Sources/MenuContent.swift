import SwiftUI
import MeetingNotesCore

struct MenuContent: View {
    @Bindable var state: AppState
    @State private var meetingName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            primaryAction
            Divider()
            MenuRow(icon: "rectangle.stack", label: "Browse Sessions", shortcut: "⌘B") {
                BrowserWindowController.shared.show(state: state)
            }
            .keyboardShortcut("b")
            MenuRow(icon: "folder", label: "Open Sessions Folder", shortcut: nil) {
                NSWorkspace.shared.open(state.store.rootURL)
            }
            if let error = state.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.caption).lineLimit(3)
            }
            Divider()
            SettingsLink {
                MenuRowContent(icon: "gearshape", label: "Settings…", shortcut: "⌘,")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")
            MenuRow(icon: "power", label: "Quit MeetingNotes", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { state.refresh() }
    }

    @ViewBuilder
    private var header: some View {
        if let session = state.activeSession {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text(session.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Text("\(session.notes.count) notes · started \(timeString(session.startedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("MeetingNotes")
                    .font(.system(size: 14, weight: .semibold))
                Text("No active meeting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if state.activeSession != nil {
            Button("End Meeting") { state.endMeeting() }
                .keyboardShortcut("e")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Meeting name (optional)", text: $meetingName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { start() }
                Button("Start Meeting") { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func start() {
        state.startMeeting(named: meetingName)
        meetingName = ""
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

/// A single native-menu-feel row: icon, label, optional trailing shortcut
/// hint, with a hover highlight. Used both as the label for plain-action
/// rows (`MenuRow`) and as the label of `SettingsLink`, which needs its
/// own label view rather than a `Button` wrapper.
private struct MenuRowContent: View {
    let icon: String
    let label: String
    var shortcut: String?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if hovering {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct MenuRow: View {
    let icon: String
    let label: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuRowContent(icon: icon, label: label, shortcut: shortcut)
        }
        .buttonStyle(.plain)
    }
}
