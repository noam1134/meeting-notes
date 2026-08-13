import SwiftUI
import Combine
import MeetingNotesCore

struct SessionBrowser: View {
    @Bindable var state: AppState
    @State private var selected: URL?
    @State private var searchText = ""
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
    @State private var headerRenameFolder: URL?
    @State private var headerRenameText = ""
    @FocusState private var headerRenameFocused: Bool
    @AppStorage("sidebarPendingExpanded") private var pendingExpanded = true
    @AppStorage("sidebarProcessedExpanded") private var processedExpanded = true
    // Per note, the filename of the leftmost screenshot in its strip — the
    // scroll anchor the chevrons write to and the swipe reports back.
    @State private var stripAnchor: [UUID: String] = [:]
    @State private var claudeTabFolders: Set<URL> = []
    @State private var terminalRevision = 0

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
            ClaudeTerminalManager.shared.onNeedsAttention = { folder, name in
                // Skip the ping when the user is already looking at this terminal.
                let alreadyWatching = NSApp.isActive && selected == folder && claudeTabFolders.contains(folder)
                if !alreadyWatching {
                    NotificationManager.notifyClaudeNeedsYou(sessionName: name, folderPath: folder.path)
                }
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .mnOpenSession)) { note in
            if let folder = note.object as? URL {
                selected = folder
                claudeTabFolders.insert(folder)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Group {
            if state.sessions.isEmpty {
                emptySidebarPlaceholder
            } else {
                List(selection: $selected) {
                    Section(isExpanded: $pendingExpanded) {
                        ForEach(pendingRows) { row in
                            sidebarRow(row.session, folder: row.id).tag(row.id)
                        }
                    } header: {
                        sectionHeader("Pending", count: pendingRows.count, expanded: $pendingExpanded)
                    }
                    Section(isExpanded: $processedExpanded) {
                        ForEach(processedRows) { row in
                            sidebarRow(row.session, folder: row.id).tag(row.id)
                        }
                    } header: {
                        sectionHeader("Processed", count: processedRows.count, expanded: $processedExpanded)
                    }
                    if !unreadableRows.isEmpty {
                        Section("Unreadable") {
                            ForEach(unreadableRows) { row in
                                unreadableSidebarRow(row.folder).tag(row.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }

    /// Whole-row toggle: clicking anywhere in the header (not just the
    /// disclosure arrow) expands/collapses the section.
    private func sectionHeader(_ title: String, count: Int, expanded: Binding<Bool>) -> some View {
        HStack(spacing: 0) {
            Text(count == 0 ? title : "\(title) · \(count)")
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) { expanded.wrappedValue.toggle() }
        }
    }

    private var emptySidebarPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("No meetings yet")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                shortcutHint("⌃⇧N", "quick note")
                shortcutHint("⌃⇧S", "screenshot")
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcutHint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
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
                Text("\(rowDateString(session.startedAt)) · \(session.notes.count) note\(session.notes.count == 1 ? "" : "s")")
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
            // Live Claude state, visible from anywhere: spinner = working,
            // orange exclamation = waiting for the user's answer.
            if ClaudeTerminalManager.shared.isRunning(folder) {
                if ClaudeTerminalManager.shared.isAwaitingInput(folder) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.body.bold())
                } else {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                }
            }
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

    private func commitHeaderRename(folder: URL) {
        guard headerRenameFolder == folder else { return }
        let trimmed = headerRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        headerRenameFolder = nil
        guard !trimmed.isEmpty else { return }
        state.renameSession(in: folder, to: trimmed)
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
    private var unreadableRows: [UnreadableRow] {
        state.sessions.compactMap { item in
            if case let .unreadable(folder) = item { return UnreadableRow(id: folder) }
            return nil
        }
    }

    private var readableRows: [SessionRow] {
        state.sessions.compactMap { item -> SessionRow? in
            if case let .readable(session, folder) = item { return SessionRow(id: folder, session: session) }
            return nil
        }
        .sorted { a, b in
            if a.session.isActive != b.session.isActive { return a.session.isActive }
            return a.session.startedAt > b.session.startedAt
        }
    }

    /// Sessions move between these two lists automatically: any status change
    /// (Claude's edits included, via the FSEvents watcher) re-derives them.
    private var pendingRows: [SessionRow] { readableRows.filter { $0.session.status != .processed } }
    private var processedRows: [SessionRow] { readableRows.filter { $0.session.status == .processed } }

    /// "14:03" today, "Yesterday 21:51", "5 Aug 10:17" — the status lists mix
    /// days, so rows carry their own date context.
    private func rowDateString(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return timeString(date) }
        if cal.isDateInYesterday(date) { return "Yesterday \(timeString(date))" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return "\(f.string(from: date)) \(timeString(date))"
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
                        if manager.isAwaitingInput(folder) {
                            Label("Claude is waiting for your answer — type in the terminal",
                                  systemImage: "bell.fill")
                                .font(.caption.bold()).foregroundStyle(.orange)
                        } else {
                            ProgressView().controlSize(.small)
                            Text("Claude is working…")
                                .font(.caption).foregroundStyle(.green)
                        }
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
                if headerRenameFolder == folder {
                    TextField("Session name", text: $headerRenameText)
                        .textFieldStyle(.plain)
                        .font(.title2.bold())
                        .focused($headerRenameFocused)
                        .onHover { editorHovered = $0 }
                        .onSubmit { commitHeaderRename(folder: folder) }
                        .onExitCommand { headerRenameFolder = nil }
                        .onAppear { headerRenameFocused = true }
                } else {
                    Text(session.name)
                        .font(.title2.bold())
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            headerRenameText = session.name
                            headerRenameFolder = folder
                        })
                        .help("Double-click to rename")
                }
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
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(SoftButtonStyle(iconOnly: true))
            .keyboardShortcut("n", modifiers: [.command])
            .help("Add note (⌘N)")
            .popover(isPresented: $showAddNotePopover) {
                addNotePopover(folder: folder)
            }
            Button {
                copyForClaude(folder: folder)
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(SoftButtonStyle())
            .help("Copy the processing prompt for Claude")
            Button {
                processWithClaude(session: session, folder: folder)
            } label: {
                Label("Process with Claude", systemImage: "sparkles")
            }
            .buttonStyle(AccentButtonStyle())
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
            sessionName: session.name,
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

    // Counts respect the search filter (not the category selection itself),
    // so chip counts reflect the current context.
    private func categoriesWithCounts(for session: Session) -> [CategoryCount] {
        let contextNotes = session.notes.filter {
            searchText.isEmpty || $0.text.localizedCaseInsensitiveContains(searchText)
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
            (selectedCategory == nil || note.category == selectedCategory)
        }
        // Pending notes first (they still need attention); chronological within
        // each group.
        .sorted { a, b in
            if (a.status == .pending) != (b.status == .pending) {
                return a.status == .pending
            }
            return a.timestamp < b.timestamp
        }
    }

    private func noteCard(_ note: Note, folder: URL) -> some View {
        let isEditing = editingNoteID == note.id
        let color = color(for: note.category)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isEditing {
                    Text(note.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color.opacity(0.95))
                }
                HStack(spacing: 4) {
                    Image(systemName: note.images.isEmpty ? "text.alignleft" : "photo")
                    if note.images.count > 1 { Text("\(note.images.count)") }
                    Text(timeString(note.timestamp))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                Spacer()
                if let trelloURLString = note.trello, let trelloURL = URL(string: trelloURLString) {
                    Button {
                        NSWorkspace.shared.open(trelloURL)
                    } label: {
                        Label("Trello", systemImage: "arrow.up.right")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(Color.blue.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                if note.status == .processed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green.opacity(0.85))
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                        Text("Pending")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(.orange.opacity(0.14), in: Capsule())
                }
            }
            // Text takes the full width; screenshots sit in a centered strip
            // beneath it, however many the note holds.
            if isEditing {
                VStack(alignment: .leading, spacing: 6) {
                    NoteComposer(text: $editText, category: $editCategory,
                                categories: state.settings.categories,
                                onSubmit: { saveEditNote(id: note.id, folder: folder) },
                                chipsAboveField: true)
                        .onHover { editorHovered = $0 }
                    Text("⏎ save · esc cancel")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(note.text)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { startEditingNote(note, folder: folder) })
            }
            noteThumbnailStrip(note, folder: folder)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.secondary)
                .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isEditing ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.6),
                                  lineWidth: isEditing ? 1.5 : 1))
                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        )

        .contextMenu { noteContextMenu(note, folder: folder) }
        .onExitCommand { if isEditing { editingNoteID = nil } }
    }

    // MARK: - Screenshot strip

    private struct LoadedShot: Identifiable {
        let name: String
        let image: NSImage
        var id: String { name }
    }

    private static let thumbSlot = CGSize(width: 168, height: 104)
    private static let thumbGap: CGFloat = 8
    private static let shotsPerPage = 3

    // Uniform slots rather than aspect-sized ones: it keeps the viewport width
    // (and so the paging maths) independent of what was captured.
    private static func stripViewportWidth(count: Int) -> CGFloat {
        let visible = CGFloat(min(count, shotsPerPage))
        return visible * thumbSlot.width + max(visible - 1, 0) * thumbGap
    }

    private func loadedShots(_ note: Note, folder: URL) -> [LoadedShot] {
        note.images.compactMap { name in
            guard let image = NSImage(contentsOf: folder.appendingPathComponent(name)),
                  image.size.height > 0 else { return nil }   // ref without a readable file
            return LoadedShot(name: name, image: image)
        }
    }

    @ViewBuilder
    private func noteThumbnailStrip(_ note: Note, folder: URL) -> some View {
        let shots = loadedShots(note, folder: folder)
        if !shots.isEmpty {
            let pageCount = Int(ceil(Double(shots.count) / Double(Self.shotsPerPage)))
            let anchorIndex = shots.firstIndex { $0.name == stripAnchor[note.id] } ?? 0
            let page = anchorIndex / Self.shotsPerPage
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    if pageCount > 1 {
                        stripChevron("chevron.left", enabled: page > 0) {
                            scrollStrip(note, shots: shots, toPage: page - 1)
                        }
                    }
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: Self.thumbGap) {
                            ForEach(shots) { shot in
                                thumbnailSlot(shot, in: shots, note: note, folder: folder)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.never)
                    .scrollTargetBehavior(.viewAligned)   // two-finger swipe settles on a shot
                    .scrollPosition(id: Binding(
                        get: { stripAnchor[note.id] ?? shots.first?.name },
                        set: { stripAnchor[note.id] = $0 }))
                    .frame(width: Self.stripViewportWidth(count: shots.count),
                           height: Self.thumbSlot.height)
                    if pageCount > 1 {
                        stripChevron("chevron.right", enabled: page < pageCount - 1) {
                            scrollStrip(note, shots: shots, toPage: page + 1)
                        }
                    }
                }
                if pageCount > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Circle()
                                .fill(Color.primary.opacity(index == page ? 0.55 : 0.18))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)   // centers the strip in the card
            .padding(.top, 2)
        }
    }

    private func scrollStrip(_ note: Note, shots: [LoadedShot], toPage page: Int) {
        let target = min(max(page, 0) * Self.shotsPerPage, shots.count - 1)
        withAnimation(.easeOut(duration: 0.22)) {
            stripAnchor[note.id] = shots[target].name
        }
    }

    private func stripChevron(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.07)))
                .overlay(Circle().strokeBorder(.separator.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
    }

    private func thumbnailSlot(_ shot: LoadedShot, in shots: [LoadedShot],
                               note: Note, folder: URL) -> some View {
        Image(nsImage: shot.image)
            .resizable()
            .scaledToFit()
            .frame(width: Self.thumbSlot.width, height: Self.thumbSlot.height)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator.opacity(0.6), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture {
                PreviewWindowController.shared.show(
                    images: shots.map(\.image),
                    startIndex: shots.firstIndex { $0.name == shot.name } ?? 0)
            }
            .contextMenu {
                Button("Copy Screenshot") { copyScreenshot(named: shot.name, folder: folder) }
                Button("Remove Screenshot", role: .destructive) {
                    state.detachImage(noteID: note.id, in: folder, named: shot.name)
                }
            }
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
        Button("Add Screenshot…") {
            CaptureController.begin(state: state,
                                    destination: .existingNote(id: note.id, folder: folder))
        }
        // Copy/Remove for a specific screenshot live on the thumbnail itself —
        // ambiguous here once a note holds several.
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
            guard editingNoteID != nil || renamingFolder != nil || headerRenameFolder != nil,
                  let window = event.window, window.title == "Sessions" else { return event }
            if event.type == .keyDown {
                // Esc cancels the active inline edit no matter where focus wandered
                // (a chip click can move focus off the field, starving onExitCommand).
                guard event.keyCode == 53 else { return event }
                DispatchQueue.main.async {
                    editingNoteID = nil
                    renamingFolder = nil
                    headerRenameFolder = nil
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
                if let folder = headerRenameFolder { commitHeaderRename(folder: folder) }
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

    private func copyScreenshot(named name: String, folder: URL) {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return }
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


extension Notification.Name {
    /// Posted by the app delegate when a "Claude needs you" notification is
    /// clicked — the browser selects that session and shows its Claude tab.
    static let mnOpenSession = Notification.Name("mnOpenSession")
}


/// Quiet pill button — subtle fill, hairline border, gentle hover.
private struct SoftButtonStyle: ButtonStyle {
    var iconOnly = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.primary)
            .padding(.horizontal, iconOnly ? 0 : 10)
            .padding(.vertical, iconOnly ? 0 : 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : (hovering ? 0.11 : 0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Primary action pill — accent fill, white label.
private struct AccentButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : (hovering ? 1.0 : 0.9)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
