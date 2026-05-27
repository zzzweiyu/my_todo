import Foundation

public enum WeeklyReportStatus: String, Codable, CaseIterable, Sendable {
    case normal
    case blocker
    case followUp
}

public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var day: String
    public var isCompleted: Bool
    public let createdAt: Date
    public var completedAt: Date?
    public var projectID: UUID?
    public var stepID: UUID?
    public var weeklyReportStatus: WeeklyReportStatus
    public var weeklyReportNote: String?

    public init(
        id: UUID = UUID(),
        title: String,
        day: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        projectID: UUID? = nil,
        stepID: UUID? = nil,
        weeklyReportStatus: WeeklyReportStatus = .normal,
        weeklyReportNote: String? = nil
    ) {
        self.id = id
        self.title = title
        self.day = day
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.projectID = projectID
        self.stepID = stepID
        self.weeklyReportStatus = weeklyReportStatus
        self.weeklyReportNote = weeklyReportNote
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case day
        case isCompleted
        case createdAt
        case completedAt
        case projectID
        case stepID
        case weeklyReportStatus
        case weeklyReportNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.day = try container.decode(String.self, forKey: .day)
        self.isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        self.stepID = try container.decodeIfPresent(UUID.self, forKey: .stepID)
        self.weeklyReportStatus = try container.decodeIfPresent(WeeklyReportStatus.self, forKey: .weeklyReportStatus) ?? .normal
        self.weeklyReportNote = try container.decodeIfPresent(String.self, forKey: .weeklyReportNote)
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
