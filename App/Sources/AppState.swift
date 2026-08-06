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

    init(store: SessionStore = SessionStore(
        rootURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/MeetingNotes"))) {
        self.store = store
        self.settings = AppSettings.load()
        refresh()
    }

    func refresh() {
        sessions = store.listSessions()
        activeSession = sessions.compactMap { item -> Session? in
            if case let .readable(session, _) = item, session.isActive { return session }
            return nil
        }.first
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
