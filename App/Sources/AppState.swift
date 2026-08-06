import Foundation
import Observation
import MeetingNotesCore

@Observable
final class AppState {
    let store: SessionStore
    var activeSession: Session?
    var sessions: [SessionListItem] = []
    var settings: AppSettings
    var lastError: String?
    private var watcher: FolderWatcher?

    // Sessions that have ended but not yet been processed — drives the menu
    // bar badge and the morning-reminder notification.
    var pendingSessionCount: Int {
        sessions.reduce(into: 0) { count, item in
            if case let .readable(session, _) = item, session.status == .pending, !session.isActive {
                count += 1
            }
        }
    }

    // Tracks the last count a notification refresh was issued for, so
    // refresh() only touches UNUserNotificationCenter when the count
    // actually changes (not on every unrelated note edit).
    private var lastNotifiedPendingCount: Int?

    init(store: SessionStore = SessionStore(
        rootURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/MeetingNotes"))) {
        self.store = store
        self.settings = AppSettings.load()
        try? FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
        refresh()
        // Embedded Claude runs edit session.json while the app stays active,
        // so refresh-on-activate never fires — watch the folder instead.
        watcher = FolderWatcher(url: store.rootURL) { [weak self] in self?.refresh() }
    }

    func refresh() {
        sessions = store.listSessions()
        activeSession = sessions.compactMap { item -> Session? in
            if case let .readable(session, _) = item, session.isActive { return session }
            return nil
        }.first

        let count = pendingSessionCount
        if count != lastNotifiedPendingCount {
            lastNotifiedPendingCount = count
            updateMorningReminder()
        }
    }

    func setMorningReminderEnabled(_ enabled: Bool) {
        settings.morningReminderEnabled = enabled
        settings.save()
        updateMorningReminder()
    }

    private func updateMorningReminder() {
        guard settings.morningReminderEnabled else {
            NotificationManager.refresh(enabled: false, pendingCount: 0)
            return
        }
        let count = pendingSessionCount
        NotificationManager.requestAuthorizationIfNeeded { granted in
            guard granted else { return }
            NotificationManager.refresh(enabled: true, pendingCount: count)
        }
    }

    func startMeeting(named name: String?) {
        run { try self.store.startSession(named: name?.isEmpty == true ? nil : name) }
    }

    func endMeeting() {
        run { try self.store.endActiveSession() }
    }

    func addNote(text: String, category: String, imageData: Data?) {
        run { try self.store.addNote(text: text, category: category, imageData: imageData) }
    }

    func addNote(text: String, category: String, to folder: URL) {
        run { try self.store.addNote(text: text, category: category, imageData: nil, to: folder) }
    }

    func updateNote(id: UUID, in folder: URL, mutate: @escaping (inout Note) -> Void) {
        run { try self.store.updateNote(id: id, in: folder, mutate: mutate) }
    }

    func deleteNote(id: UUID, in folder: URL) {
        run { try self.store.deleteNote(id: id, in: folder) }
    }

    func renameSession(in folder: URL, to name: String) {
        run { try self.store.renameSession(in: folder, to: name) }
    }

    func setSessionStatus(_ status: ProcessingStatus, in folder: URL) {
        run { try self.store.setSessionStatus(status, in: folder) }
    }

    func deleteSession(in folder: URL) {
        run { try self.store.deleteSession(in: folder) }
    }

    private func run(_ body: () throws -> Void) {
        do {
            try body()
            lastError = nil
        } catch {
            lastError = String(describing: error)   // never silently drop a note
        }
        refresh()
    }
}
