import Foundation

public enum ProcessingStatus: String, Codable, Sendable {
    case pending, processed
}

public struct Note: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public var category: String
    public var text: String
    public var image: String?
    public var status: ProcessingStatus

    public init(id: UUID, timestamp: Date, category: String, text: String,
                image: String?, status: ProcessingStatus) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.text = text
        self.image = image
        self.status = status
    }

    // Explicit encode so image serializes as JSON null (Claude's contract shows the key).
    enum CodingKeys: String, CodingKey { case id, timestamp, category, text, image, status }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(category, forKey: .category)
        try c.encode(text, forKey: .text)
        try c.encode(image, forKey: .image)   // encodes null when nil
        try c.encode(status, forKey: .status)
    }
}

public struct Session: Codable, Equatable, Sendable {
    public var name: String
    public let startedAt: Date
    public var endedAt: Date?
    public var status: ProcessingStatus
    public var notes: [Note]

    public init(name: String, startedAt: Date, endedAt: Date?,
                status: ProcessingStatus, notes: [Note]) {
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.notes = notes
    }

    public var isActive: Bool { endedAt == nil }

    enum CodingKeys: String, CodingKey { case name, startedAt, endedAt, status, notes }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)   // null while active
        try c.encode(status, forKey: .status)
        try c.encode(notes, forKey: .notes)
    }
}

public enum SessionJSON {
    public static func encode(_ session: Session) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(session)
    }

    public static func decode(_ data: Data) throws -> Session {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Session.self, from: data)
    }
}
