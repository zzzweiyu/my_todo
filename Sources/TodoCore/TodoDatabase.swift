import Foundation

public struct TodoDatabase: Codable, Equatable, Sendable {
    public var version: Int
    public var todos: [TodoItem]
    public var projects: [Project]

    public init(version: Int = 1, todos: [TodoItem] = [], projects: [Project] = []) {
        self.version = version
        self.todos = todos
        self.projects = projects
    }
}

