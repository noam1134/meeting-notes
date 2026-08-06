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
    public var trello: String?

    public init(id: UUID, timestamp: Date, category: String, text: String,
                image: String?, status: ProcessingStatus, trello: String?) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.text = text
        self.image = image
        self.status = status
        self.trello = trello
    }

    // Explicit init so old sessions (predating the trello field) still decode.
    enum CodingKeys: String, CodingKey { case id, timestamp, category, text, image, status, trello }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        category = try c.decode(String.self, forKey: .category)
        text = try c.decode(String.self, forKey: .text)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        status = try c.decode(ProcessingStatus.self, forKey: .status)
        trello = try c.decodeIfPresent(String.self, forKey: .trello)
    }

    // Explicit encode so image/trello serialize as JSON null (Claude's contract shows the key).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(category, forKey: .category)
        try c.encode(text, forKey: .text)
        try c.encode(image, forKey: .image)   // encodes null when nil
        try c.encode(status, forKey: .status)
        try c.encode(trello, forKey: .trello) // encodes null when nil
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
