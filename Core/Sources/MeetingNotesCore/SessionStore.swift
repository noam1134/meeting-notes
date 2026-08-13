import Foundation

public enum SessionListItem: Equatable {
    case readable(session: Session, folder: URL)
    case unreadable(folder: URL)
}

public enum SessionStoreError: Error, Equatable {
    case noActiveSession
    case corruptSession(URL)
    case noteNotFound(UUID)
}

public final class SessionStore {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    private static let folderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    @discardableResult
    public func startSession(named name: String?, at date: Date = Date()) throws -> URL {
        let stamp = Self.folderFormatter.string(from: date)
        let slug = name.map { n in
            n.lowercased()
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                .joined(separator: "-")
                .replacingOccurrences(of: "/", with: "-")
        }
        let folderName = [stamp, slug].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "-")
        // isDirectory: false pins the URL's string form so it doesn't depend on
        // whether the directory already exists on disk at construction time
        // (appendingPathComponent auto-detects and appends a trailing slash
        // for existing directories, which would break URL equality below).
        let folder = try uniqueFolder(for: folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let session = Session(name: name ?? stamp, startedAt: date,
                              endedAt: nil, status: .pending, notes: [])
        try write(session, to: folder)
        return folder
    }

    // Appends a numeric suffix (-2, -3, …) until an unused folder name is found,
    // so two sessions started in the same minute never collide and silently
    // clobber each other's session.json.
    private func uniqueFolder(for baseName: String) throws -> URL {
        var folder = rootURL.appendingPathComponent(baseName, isDirectory: false)
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = rootURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: false)
            suffix += 1
        }
        return folder
    }

    public func activeSessionFolder() throws -> URL? {
        for item in listSessions() {
            if case let .readable(session, folder) = item, session.isActive { return folder }
        }
        return nil
    }

    public func loadSession(in folder: URL) throws -> Session {
        let data = try Data(contentsOf: folder.appendingPathComponent("session.json"))
        do { return try SessionJSON.decode(data) }
        catch { throw SessionStoreError.corruptSession(folder) }
    }

    public func endActiveSession(at date: Date = Date()) throws {
        guard let folder = try activeSessionFolder() else { throw SessionStoreError.noActiveSession }
        var session = try loadSession(in: folder)
        session.endedAt = date
        try write(session, to: folder)
    }

    @discardableResult
    public func addNote(text: String, category: String, imageData: Data?,
                        at date: Date = Date()) throws -> Note {
        guard let folder = try activeSessionFolder() else { throw SessionStoreError.noActiveSession }
        return try addNote(text: text, category: category, imageData: imageData, to: folder, at: date)
    }

    @discardableResult
    public func addNote(text: String, category: String, imageData: Data?,
                        to folder: URL, at date: Date = Date()) throws -> Note {
        var session = try loadSession(in: folder)   // reload: tolerate external edits
        var imageName: String?
        if let imageData {
            let name = nextImageName(in: folder, notes: session.notes)
            // .withoutOverwriting: if the name were ever taken anyway, fail loudly
            // rather than silently replacing another note's screenshot.
            try imageData.write(to: folder.appendingPathComponent(name), options: .withoutOverwriting)
            imageName = name
        }
        let note = Note(id: UUID(), timestamp: date, category: category,
                        text: text, image: imageName, status: .pending, trello: nil)
        session.notes.append(note)
        try write(session, to: folder)
        // Reload so the returned Note matches disk exactly (JSON round-trip
        // truncates timestamp to whole seconds via ISO8601 encoding).
        let persisted = try loadSession(in: folder)
        return persisted.notes.last ?? note
    }

    // Probes img-001, img-002, … until one is free — free meaning no note claims it
    // AND no file sits there. Deriving the number from a count instead (notes with
    // images + 1) went backwards whenever an image note was deleted, so the next
    // capture reused a live filename and overwrote that note's screenshot.
    private func nextImageName(in folder: URL, notes: [Note]) -> String {
        let claimed = Set(notes.compactMap(\.image))
        var index = 1
        while true {
            let name = String(format: "img-%03d.png", index)
            if !claimed.contains(name),
               !FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
                return name
            }
            index += 1
        }
    }

    public func updateNote(id: UUID, in folder: URL, mutate: (inout Note) -> Void) throws {
        var session = try loadSession(in: folder)   // reload: tolerate external edits
        guard let index = session.notes.firstIndex(where: { $0.id == id }) else {
            throw SessionStoreError.noteNotFound(id)
        }
        mutate(&session.notes[index])
        try write(session, to: folder)
    }

    public func deleteNote(id: UUID, in folder: URL) throws {
        var session = try loadSession(in: folder)   // reload: tolerate external edits
        guard let index = session.notes.firstIndex(where: { $0.id == id }) else {
            throw SessionStoreError.noteNotFound(id)
        }
        let note = session.notes.remove(at: index)
        // Sessions written before nextImageName() can have two notes sharing one
        // filename; only drop the file once nothing points at it any more.
        if let imageName = note.image,
           !session.notes.contains(where: { $0.image == imageName }) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(imageName))
        }
        try write(session, to: folder)
    }

    public func renameSession(in folder: URL, to name: String) throws {
        var session = try loadSession(in: folder)   // reload: tolerate external edits
        session.name = name
        try write(session, to: folder)
    }

    public func setSessionStatus(_ status: ProcessingStatus, in folder: URL) throws {
        var session = try loadSession(in: folder)   // reload: tolerate external edits
        session.status = status
        try write(session, to: folder)
    }

    public func deleteSession(in folder: URL) throws {
        try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
    }

    public func listSessions() -> [SessionListItem] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: rootURL.path)) ?? []
        // Reconstruct URLs from rootURL rather than using the enumerator's URLs
        // directly: contentsOfDirectory(at:) resolves symlinks (e.g. /var ->
        // /private/var) and marks directories with a trailing slash, which
        // would make these URLs != the ones handed out by startSession(named:).
        let folders = names.compactMap { name -> URL? in
            let folder = rootURL.appendingPathComponent(name, isDirectory: false)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return folder
        }
        return folders
            .sorted { $0.lastPathComponent > $1.lastPathComponent }   // name embeds timestamp
            .map { folder in
                if let session = try? loadSession(in: folder) {
                    return .readable(session: session, folder: folder)
                }
                return .unreadable(folder: folder)
            }
    }

    private func write(_ session: Session, to folder: URL) throws {
        let data = try SessionJSON.encode(session)
        try data.write(to: folder.appendingPathComponent("session.json"), options: .atomic)
    }
}
