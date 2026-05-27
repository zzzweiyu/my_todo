import Foundation

public struct WeeklyReportDraft: Codable, Equatable, Identifiable, Sendable {
    public var id: String { weekStartDay }
    public let weekStartDay: String
    public var markdown: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        weekStartDay: String,
        markdown: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.weekStartDay = weekStartDay
        self.markdown = markdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TodoDatabase: Codable, Equatable, Sendable {
    public var version: Int
    public var todos: [TodoItem]
    public var projects: [Project]
    public var weeklyReportDrafts: [WeeklyReportDraft]

    public init(
        version: Int = 1,
        todos: [TodoItem] = [],
        projects: [Project] = [],
        weeklyReportDrafts: [WeeklyReportDraft] = []
    ) {
        self.version = version
        self.todos = todos
        self.projects = projects
        self.weeklyReportDrafts = weeklyReportDrafts
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case todos
        case projects
        case weeklyReportDrafts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.todos = try container.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
        self.projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        self.weeklyReportDrafts = try container.decodeIfPresent([WeeklyReportDraft].self, forKey: .weeklyReportDrafts) ?? []
    }
}
