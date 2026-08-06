import SwiftUI
import Combine
import MeetingNotesCore

struct SessionBrowser: View {
    @Bindable var state: AppState
    @State private var selected: URL?
    @State private var searchText = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var selectedCategory: String?
    @State private var showAddNotePopover = false
    @State private var addNoteText = ""
    @State private var addNoteCategory = ""
    @State private var renamingFolder: URL?
    @State private var renameText = ""
    @FocusState private var renameFieldFocus: URL?
    @State private var sessionDeleteTarget: SessionDeleteTarget?
    @State private var editingNoteID: UUID?
    @State private var editText = ""
    @State private var editCategory = ""
    @State private var noteDeleteTarget: NoteDeleteTarget?
    @State private var editingFolder: URL?
    @State private var editorHovered = false
    @State private var outsideClickMonitor: Any?
    @State private var claudeTabFolders: Set<URL> = []
    @State private var terminalRevision = 0

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All", pending = "Pending"
        var id: String { rawValue }
    }

    private struct SessionDeleteTarget: Identifiable {
        let id: URL
        let name: String
        var folder: URL { id }
    }

    private struct NoteDeleteTarget: Identifiable {
        let id: UUID
        let folder: URL
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let folder = selected {
                detailView(for: folder)
            } else {
                ContentUnavailableView("Select a session", systemImage: "list.bullet.rectangle")
            }
        }
        .searchable(text: $searchText, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Status", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
        .confirmationDialog(
            "Move '\(sessionDeleteTarget?.name ?? "")' to Trash? Claude-created Trello cards are unaffected.",
            isPresented: Binding(
                get: { sessionDeleteTarget != nil },
                set: { if !$0 { sessionDeleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let target = sessionDeleteTarget { performDeleteSession(target.folder) }
                sessionDeleteTarget = nil
            }
            Button("Cancel", role: .cancel) { sessionDeleteTarget = nil }
        }
        .confirmationDialog(
            "Delete this note? This cannot be undone.",
            isPresented: Binding(
                get: { noteDeleteTarget != nil },
                set: { if !$0 { noteDeleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = noteDeleteTarget { state.deleteNote(id: target.id, in: target.folder) }
                noteDeleteTarget = nil
            }
            Button("Cancel", role: .cancel) { noteDeleteTarget = nil }
        }
        .onAppear {
            // Switch to .regular first (dock icon appears) so activation
            // can properly bring the window to the front.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            state.refresh()
            installOutsideClickMonitor()
            ClaudeTerminalManager.shared.onChange = { terminalRevision &+= 1 }
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
            if let m = outsideClickMonitor {
                NSEvent.removeMonitor(m)
                outsideClickMonitor = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Claude edits session.json externally; pick that up without a relaunch.
            state.refresh()
        }
        .onChange(of: selected) {
            selectedCategory = nil
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Group {
            if state.sessions.isEmpty {
                ContentUnavailableView(
                    "No meetings yet — press ⌃⇧N or ⌃⇧S during your next meeting",
                    systemImage: "mic.slash")
            } else {
                List(selection: $selected) {
                    ForEach(groupedSections, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.rows) { row in
                                sidebarRow(row.session, folder: row.id).tag(row.id)
                            }
                        }
                    }
                    if !unreadableRows.isEmpty {
                        Section("Unreadable") {
                            ForEach(unreadableRows) { row in
                                unreadableSidebarRow(row.folder).tag(row.id)
                            }
                        }
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }

    private func sidebarRow(_ session: Session, folder: URL) -> some View {
        let pendingCount = session.notes.filter { $0.status == .pending }.count
        let presentCategories = Set(session.notes.map(\.category))
        let categoryDots = state.settings.categories.filter { presentCategories.contains($0) }.prefix(5)
        let isRenaming = renamingFolder == folder
        return HStack(spacing: 8) {
            if session.isActive {
                Circle().fill(.red).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Session name", text: $renameText)
                        .textFieldStyle(.plain)
                        .onHover { editorHovered = $0 }
                        .focused($renameFieldFocus, equals: folder)
                        .onSubmit { commitRename(folder: folder) }
                        .onExitCommand { renamingFolder = nil }
                        .onChange(of: renameFieldFocus) { _, newValue in
                            if newValue != folder && renamingFolder == folder {
                                commitRename(folder: folder)
                            }
                        }
                } else {
                    Text(session.name).lineLimit(1)
                }
                Text("\(timeString(session.startedAt)) · \(session.notes.count) note\(session.notes.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !categoryDots.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(categoryDots), id: \.self) { cat in
                            Circle().fill(color(for: cat)).frame(width: 6, height: 6)
                        }
                    }
                }
            }
            Spacer()
            if session.status == .processed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 2)
        .contextMenu { sessionContextMenu(session: session, folder: folder) }
    }

    @ViewBuilder
    private func sessionContextMenu(session: Session, folder: URL) -> some View {
        Button("Rename…") {
            startRename(session: session, folder: folder)
        }
        Button(session.status == .processed ? "Mark Pending" : "Mark Processed") {
            state.setSessionStatus(session.status == .processed ? .pending : .processed, in: folder)
        }
        if session.isActive {
            Button("End Meeting") { state.endMeeting() }
        }
        Button("Copy for Claude") { copyForClaude(folder: folder) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
        Divider()
        Button("Delete Session…", role: .destructive) {
            sessionDeleteTarget = SessionDeleteTarget(id: folder, name: session.name)
        }
    }

    private func startRename(session: Session, folder: URL) {
        editingNoteID = nil
        renameText = session.name
        renamingFolder = folder
        renameFieldFocus = folder
    }

    private func commitRename(folder: URL) {
        guard renamingFolder == folder else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renamingFolder = nil
            return
        }
        state.renameSession(in: folder, to: trimmed)
        renamingFolder = nil
    }

    private func performDeleteSession(_ folder: URL) {
        state.deleteSession(in: folder)
        if selected == folder { selected = nil }
    }

    private func unreadableSidebarRow(_ folder: URL) -> some View {
        Label {
            Text(folder.lastPathComponent).lineLimit(1)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
            Divider()
            Button("Delete Session…", role: .destructive) {
                sessionDeleteTarget = SessionDeleteTarget(id: folder, name: folder.lastPathComponent)
            }
        }
    }

    private struct SessionRow: Identifiable {
        let id: URL
        let session: Session
    }
    private struct UnreadableRow: Identifiable {
        let id: URL
        var folder: URL { id }
    }
    private struct SidebarSection { let title: String; let rows: [SessionRow] }

    private var unreadableRows: [UnreadableRow] {
        state.sessions.compactMap { item in
            if case let .unreadable(folder) = item { return UnreadableRow(id: folder) }
            return nil
        }
    }

    private var groupedSections: [SidebarSection] {
        let readable = state.sessions.compactMap { item -> SessionRow? in
            if case let .readable(session, folder) = item { return SessionRow(id: folder, session: session) }
            return nil
        }
        let groups = Dictionary(grouping: readable) { dayLabel(for: $0.session.startedAt) }
        let orderedKeys = groups.keys.sorted { key1, key2 in
            let d1 = groups[key1]!.map(\.session.startedAt).max() ?? .distantPast
            let d2 = groups[key2]!.map(\.session.startedAt).max() ?? .distantPast
            return d1 > d2
        }
        return orderedKeys.map { key in
            let rows = groups[key]!.sorted { a, b in
                if a.session.isActive != b.session.isActive { return a.session.isActive }
                return a.session.startedAt > b.session.startedAt
            }
            return SidebarSection(title: key, rows: rows)
        }
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }

    // MARK: - Detail

    @ViewBuilder
    private func detailView(for folder: URL) -> some View {
        if let session = try? state.store.loadSession(in: folder) {
            readableDetail(session: session, folder: folder)
        } else {
            // Corrupt file: show, never touch.
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text("session.json is unreadable — left untouched.")
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func readableDetail(session: Session, folder: URL) -> some View {
        let categories = categoriesWithCounts(for: session)
        let notes = filteredNotes(session: session)
        let manager = ClaudeTerminalManager.shared
        let _ = terminalRevision   // refresh when runs start/end
        let showClaude = manager.hasRun(folder) && claudeTabFolders.contains(folder)
        return VStack(alignment: .leading, spacing: 0) {
            header(session: session, folder: folder)
            if manager.hasRun(folder) {
                Picker("", selection: Binding(
                    get: { showClaude },
                    set: { wantClaude in
                        if wantClaude { claudeTabFolders.insert(folder) }
                        else { claudeTabFolders.remove(folder) }
                    })) {
                    Text("Notes").tag(false)
                    Text("Claude").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            if showClaude, let terminal = manager.terminal(for: folder) {
                Divider()
                TerminalHostView(terminal: terminal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    if manager.isRunning(folder) {
                        Label("Claude is working", systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(.green)
                        Spacer()
                        Button("Stop", role: .destructive) { confirmStopClaude(folder: folder) }
                    } else {
                        Label("Finished", systemImage: "checkmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") {
                            manager.clear(folder: folder)
                            claudeTabFolders.remove(folder)
                        }
                    }
                }
                .padding(8)
            } else {
            if !categories.isEmpty {
                categoryChipRow(categories)
                    .padding(.bottom, 8)
            }
            Divider()
            if notes.isEmpty {
                ContentUnavailableView("No notes match", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(notes) { note in
                            noteCard(note, folder: folder)
                        }
                    }
                    .padding()
                }
            }
            }
        }
    }

    private func confirmStopClaude(folder: URL) {
        let alert = NSAlert()
        alert.messageText = "Stop Claude for this session?"
        alert.informativeText = "The claude process will be terminated. Any clarifying questions it's waiting on won't be answered."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            ClaudeTerminalManager.shared.stop(folder: folder)
            claudeTabFolders.remove(folder)
        }
    }

    private func header(session: Session, folder: URL) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).font(.title2.bold())
                Text(timeRangeString(session))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(session.status)
            Button {
                addNoteText = ""
                addNoteCategory = state.settings.categories.first ?? ""
                showAddNotePopover = true
            } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .popover(isPresented: $showAddNotePopover) {
                addNotePopover(folder: folder)
            }
            Button {
                copyForClaude(folder: folder)
            } label: {
                Label("Copy for Claude", systemImage: "doc.on.clipboard")
            }
            Button {
                processWithClaude(session: session, folder: folder)
            } label: {
                Label("Process with Claude", systemImage: "terminal")
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.status == .processed)
        }
        .padding()
    }

    private func addNotePopover(folder: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Add a note…", text: $addNoteText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { saveAddNote(folder: folder) }
            HStack(spacing: 6) {
                ForEach(state.settings.categories, id: \.self) { cat in
                    let isSelected = addNoteCategory == cat
                    let categoryColorValue = color(for: cat)
                    Button {
                        addNoteCategory = cat
                    } label: {
                        Text(cat)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(isSelected ? categoryColorValue : Color.clear, in: Capsule())
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .overlay(Capsule().stroke(isSelected ? Color.clear : Color.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.caption)
            HStack {
                Spacer()
                Button("Cancel") { showAddNotePopover = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveAddNote(folder: folder) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func saveAddNote(folder: URL) {
        let trimmed = addNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showAddNotePopover = false
            return
        }
        state.addNote(text: addNoteText, category: addNoteCategory, to: folder)
        showAddNotePopover = false
    }

    private func statusBadge(_ status: ProcessingStatus) -> some View {
        Group {
            if status == .processed {
                Label("Processed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Pending", systemImage: "clock")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption.bold())
    }

    // Shared by "Copy for Claude" (clipboard) and "Process with Claude" (embedded
    // terminal) so the two entry points always describe the same workflow.
    static func processingPrompt(for folder: URL) -> String {
        "Process my meeting notes in \(folder.path): read session.json and the PNG screenshots, and expand each note into full context. IMPORTANT: my notes are shorthand and may be ambiguous or missing details — before creating anything in Trello, go over the notes and ask me clarifying questions about anything unclear (what the task actually is, its scope, and any missing specifics). Do not create any Trello card you are not sure about. Only after I've confirmed, create Trello cards via the Trello MCP for the notes categorized 'Trello task'; after creating each card, write its URL into that note's \"trello\" field in session.json, then set each handled note's status and the session's status to \"processed\"."
    }

    private func copyForClaude(folder: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.processingPrompt(for: folder), forType: .string)
    }

    private func processWithClaude(session: Session, folder: URL) {
        let started = ClaudeTerminalManager.shared.start(
            folder: folder,
            prompt: Self.processingPrompt(for: folder))
        if started {
            claudeTabFolders.insert(folder)
        } else {
            state.lastError = "Claude Code CLI not found — install it (https://claude.com/product/claude-code) or use Copy for Claude instead."
        }
    }

    // MARK: - Category chips

    private struct CategoryCount: Identifiable {
        let category: String
        let count: Int
        var id: String { category }
    }

    // Counts respect search + status filters (not the category selection
    // itself), so chip counts reflect the current context.
    private func categoriesWithCounts(for session: Session) -> [CategoryCount] {
        let contextNotes = session.notes.filter {
            (searchText.isEmpty || $0.text.localizedCaseInsensitiveContains(searchText)) &&
            (statusFilter == .all || $0.status == .pending)
        }
        let present = Set(contextNotes.map(\.category))
        let ordered = state.settings.categories.filter { present.contains($0) }
        let extra = present.subtracting(state.settings.categories).sorted()
        return (ordered + extra).map { cat in
            CategoryCount(category: cat, count: contextNotes.filter { $0.category == cat }.count)
        }
    }

    private func categoryChipRow(_ categories: [CategoryCount]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { item in
                    let color = color(for: item.category)
                    Button {
                        selectedCategory = (selectedCategory == item.category) ? nil : item.category
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(item.category)
                            Text("\(item.count)").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(selectedCategory == item.category ? color.opacity(0.28) : Color.secondary.opacity(0.12),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Note cards

    private func filteredNotes(session: Session) -> [Note] {
        session.notes.filter { note in
            (searchText.isEmpty || note.text.localizedCaseInsensitiveContains(searchText)) &&
            (statusFilter == .all || note.status == .pending) &&
            (selectedCategory == nil || note.category == selectedCategory)
        }
    }

    private func noteCard(_ note: Note, folder: URL) -> some View {
        let isEditing = editingNoteID == note.id
        let color = color(for: note.category)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isEditing {
                    Text(note.category)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color, in: Capsule())
                        .foregroundStyle(.white)
                }
                Image(systemName: note.image != nil ? "photo" : "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(timeString(note.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let trelloURLString = note.trello, let trelloURL = URL(string: trelloURLString) {
                    Button {
                        NSWorkspace.shared.open(trelloURL)
                    } label: {
                        Label("Trello", systemImage: "arrow.up.right")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                if note.status == .processed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("pending").font(.caption).foregroundStyle(.orange)
                }
            }
            if isEditing {
                NoteComposer(text: $editText, category: $editCategory,
                            categories: state.settings.categories,
                            onSubmit: { saveEditNote(id: note.id, folder: folder) },
                            chipsAboveField: true)
                    .onHover { editorHovered = $0 }
                Text("⏎ save · esc cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(note.text)
                    .font(.system(size: 16))
                    .simultaneousGesture(TapGesture(count: 2).onEnded { startEditingNote(note, folder: folder) })
            }
            if let imageName = note.image,
               let nsImage = NSImage(contentsOf: folder.appendingPathComponent(imageName)) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        PreviewWindowController.shared.show(image: nsImage)
                    }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu { noteContextMenu(note, folder: folder) }
        .onExitCommand { if isEditing { editingNoteID = nil } }
    }

    @ViewBuilder
    private func noteContextMenu(_ note: Note, folder: URL) -> some View {
        Button("Edit…") {
            startEditingNote(note, folder: folder)
        }
        Button(note.status == .processed ? "Mark Pending" : "Mark Processed") {
            let newStatus: ProcessingStatus = note.status == .processed ? .pending : .processed
            state.updateNote(id: note.id, in: folder) { $0.status = newStatus }
        }
        Button("Copy Text") {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(note.text, forType: .string)
        }
        if note.image != nil {
            Button("Copy Screenshot") { copyScreenshot(note: note, folder: folder) }
        }
        Divider()
        Button("Delete Note…", role: .destructive) {
            noteDeleteTarget = NoteDeleteTarget(id: note.id, folder: folder)
        }
    }

    private func startEditingNote(_ note: Note, folder: URL) {
        renamingFolder = nil
        editText = note.text
        editCategory = note.category
        editingFolder = folder
        editingNoteID = note.id
    }

    // Focus-loss alone can't detect clicks on non-focusable areas (empty space keeps
    // the field focused), so commit active inline edits on any click outside the editor.
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
            guard editingNoteID != nil || renamingFolder != nil,
                  let window = event.window, window.title == "Sessions" else { return event }
            if event.type == .keyDown {
                // Esc cancels the active inline edit no matter where focus wandered
                // (a chip click can move focus off the field, starving onExitCommand).
                guard event.keyCode == 53 else { return event }
                DispatchQueue.main.async {
                    editingNoteID = nil
                    renamingFolder = nil
                }
                return nil
            }
            // The mouse being over the editor (SwiftUI hover) means this click is
            // interaction with it — field, chips, selection — never a dismissal.
            if editorHovered { return event }
            // Clicks landing on a text view are selection/caret placement — never commit.
            if let hit = window.contentView?.hitTest(event.locationInWindow) {
                var v: NSView? = hit
                while let cur = v {
                    if cur is NSTextView { return event }
                    v = cur.superview
                }
            }
            DispatchQueue.main.async {
                if let folder = renamingFolder { commitRename(folder: folder) }
                if let id = editingNoteID, let folder = editingFolder {
                    saveEditNote(id: id, folder: folder)
                }
            }
            return event
        }
    }

    private func saveEditNote(id: UUID, folder: URL) {
        guard editingNoteID == id else { return }
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editingNoteID = nil
            return
        }
        let text = trimmed
        let category = editCategory
        state.updateNote(id: id, in: folder) { note in
            note.text = text
            note.category = category
        }
        editingNoteID = nil
    }

    private func copyScreenshot(note: Note, folder: URL) {
        guard let imageName = note.image,
              let data = try? Data(contentsOf: folder.appendingPathComponent(imageName)) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
    }

    private func color(for category: String) -> Color {
        categoryColor(category, categories: state.settings.categories)
    }

    // MARK: - Formatting

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func dateOnlyString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }

    private func timeRangeString(_ session: Session) -> String {
        let start = timeString(session.startedAt)
        let end = session.endedAt.map(timeString) ?? "now"
        return "\(start)–\(end) · \(dateOnlyString(session.startedAt))"
    }
}
