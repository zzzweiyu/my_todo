import Foundation

public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var day: String
    public var isCompleted: Bool
    public let createdAt: Date
    public var completedAt: Date?
    public var projectID: UUID?
    public var stepID: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        day: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        projectID: UUID? = nil,
        stepID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.day = day
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.projectID = projectID
        self.stepID = stepID
    }
}

public extension JSONEncoder {
    static var todoItemsEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var todoItemsDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
