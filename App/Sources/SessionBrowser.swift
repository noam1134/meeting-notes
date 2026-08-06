import SwiftUI
import MeetingNotesCore

struct SessionBrowser: View {
    @Bindable var state: AppState
    @State private var selected: URL?

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items, id: \.folder) { row in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(row.title)
                                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: row.icon).foregroundStyle(row.color)
                            }
                            .tag(row.folder)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let folder = selected {
                detailView(for: folder)
            } else {
                Text("Select a session").foregroundStyle(.secondary)
            }
        }
        .onAppear { state.refresh() }
    }

    private struct Row {
        let folder: URL
        let title: String, subtitle: String, icon: String
        let color: Color
    }
    private struct BrowserSection { let title: String; let items: [Row] }

    private var sections: [BrowserSection] {
        var active: [Row] = [], pending: [Row] = [], processed: [Row] = [], broken: [Row] = []
        for item in state.sessions {
            switch item {
            case let .readable(session, folder):
                let row = Row(folder: folder, title: session.name,
                              subtitle: "\(session.notes.count) notes",
                              icon: session.isActive ? "record.circle" : "clock",
                              color: session.isActive ? .red
                                   : session.status == .processed ? .green : .orange)
                if session.isActive { active.append(row) }
                else if session.status == .processed {
                    processed.append(Row(folder: folder, title: session.name,
                                         subtitle: row.subtitle,
                                         icon: "checkmark.circle", color: .green))
                } else { pending.append(row) }
            case let .unreadable(folder):
                broken.append(Row(folder: folder, title: folder.lastPathComponent,
                                  subtitle: "Unreadable session.json",
                                  icon: "exclamationmark.triangle", color: .red))
            }
        }
        return [("Active", active), ("Pending", pending),
                ("Processed", processed), ("Unreadable", broken)]
            .filter { !$0.1.isEmpty }
            .map { BrowserSection(title: $0.0, items: $0.1) }
    }

    @ViewBuilder
    private func detailView(for folder: URL) -> some View {
        if let session = try? state.store.loadSession(in: folder) {
            List(session.notes) { note in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(note.category).font(.caption).padding(.horizontal, 6)
                            .background(.quaternary, in: Capsule())
                        Text(note.timestamp, style: .time)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if note.status == .processed {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    Text(note.text)
                    if let image = note.image,
                       let nsImage = NSImage(contentsOf: folder.appendingPathComponent(image)) {
                        Image(nsImage: nsImage)
                            .resizable().scaledToFit().frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            // Corrupt file: show, never touch. "Reveal in Finder" per spec.
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text("session.json is unreadable — left untouched.")
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
            }
        }
    }
}
