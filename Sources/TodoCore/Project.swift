import Foundation

public struct Project: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var steps: [ProjectStep]
    public var isArchived: Bool
    public let createdAt: Date
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        steps: [ProjectStep] = [],
        isArchived: Bool = false,
        createdAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.steps = steps
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    public var totalStepCount: Int {
        steps.reduce(0) { total, step in
            total + step.totalStepCount
        }
    }

    public var completedStepCount: Int {
        steps.reduce(0) { total, step in
            total + step.completedStepCount
        }
    }
}

public struct ProjectStep: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var isCompleted: Bool
    public let createdAt: Date
    public var completedAt: Date?
    public var scheduledTodoID: UUID?
    public var children: [ProjectStep]

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        scheduledTodoID: UUID? = nil,
        children: [ProjectStep] = []
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.scheduledTodoID = scheduledTodoID
        self.children = children
    }

    public var totalStepCount: Int {
        1 + children.reduce(0) { total, child in
            total + child.totalStepCount
        }
    }

    public var completedStepCount: Int {
        (isCompleted ? 1 : 0) + children.reduce(0) { total, child in
            total + child.completedStepCount
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case isCompleted
        case createdAt
        case completedAt
        case scheduledTodoID
        case children
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.scheduledTodoID = try container.decodeIfPresent(UUID.self, forKey: .scheduledTodoID)
        self.children = try container.decodeIfPresent([ProjectStep].self, forKey: .children) ?? []
    }
}
