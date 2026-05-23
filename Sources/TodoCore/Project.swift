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
        steps.count
    }

    public var completedStepCount: Int {
        steps.filter(\.isCompleted).count
    }
}

public struct ProjectStep: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var isCompleted: Bool
    public let createdAt: Date
    public var completedAt: Date?
    public var scheduledTodoID: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        scheduledTodoID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.scheduledTodoID = scheduledTodoID
    }
}

