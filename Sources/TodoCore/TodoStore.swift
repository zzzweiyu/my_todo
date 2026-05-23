import Combine
import Foundation

public final class TodoStore: ObservableObject {
    public enum StoreError: Error, Equatable {
        case blankTitle
        case itemNotFound
        case projectNotFound
        case stepNotFound
        case stepAlreadyScheduled
    }

    @Published public private(set) var items: [TodoItem]
    @Published public private(set) var projectItems: [Project]

    private let storageURL: URL
    private let today: () -> String
    private let now: () -> Date

    public convenience init() throws {
        try self.init(storageURL: Self.defaultStorageURL())
    }

    public init(
        storageURL: URL,
        today: @escaping () -> String = TodoStore.currentDayString,
        now: @escaping () -> Date = Date.init
    ) throws {
        self.storageURL = storageURL
        self.today = today
        self.now = now

        let loaded = try Self.loadDatabase(from: storageURL)
        self.items = loaded.database.todos
        self.projectItems = loaded.database.projects

        let rolledForward = rollOpenItemsForwardIfNeeded()
        if loaded.needsSave || rolledForward {
            try save()
        }
    }

    @discardableResult
    public func add(title: String) throws -> TodoItem {
        let cleanTitle = try normalizedTitle(title)
        return try mutate {
            let item = TodoItem(title: cleanTitle, day: today(), createdAt: now())
            items.append(item)
            sortItems()
            return item
        }
    }

    public func updateTitle(_ id: UUID, title: String) throws {
        let cleanTitle = try normalizedTitle(title)
        try mutate {
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                throw StoreError.itemNotFound
            }

            items[index].title = cleanTitle
            if let projectID = items[index].projectID, let stepID = items[index].stepID {
                try updateStepInMemory(projectID: projectID, stepID: stepID) { step in
                    step.title = cleanTitle
                }
            }
        }
    }

    public func setCompleted(_ id: UUID, isCompleted: Bool) throws {
        try mutate {
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                throw StoreError.itemNotFound
            }

            let completionDate = isCompleted ? now() : nil
            items[index].isCompleted = isCompleted
            items[index].completedAt = completionDate

            if let projectID = items[index].projectID, let stepID = items[index].stepID {
                try updateStepInMemory(projectID: projectID, stepID: stepID) { step in
                    step.isCompleted = isCompleted
                    step.completedAt = completionDate
                }
            }
        }
    }

    public func delete(_ id: UUID) throws {
        try mutate {
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                throw StoreError.itemNotFound
            }

            let item = items.remove(at: index)
            if let projectID = item.projectID, let stepID = item.stepID {
                try updateStepInMemory(projectID: projectID, stepID: stepID) { step in
                    if step.scheduledTodoID == item.id {
                        step.scheduledTodoID = nil
                    }
                }
            }
        }
    }

    @discardableResult
    public func addProject(title: String) throws -> Project {
        let cleanTitle = try normalizedTitle(title)
        return try mutate {
            let project = Project(title: cleanTitle, createdAt: now())
            projectItems.append(project)
            sortProjects()
            return project
        }
    }

    public func updateProjectTitle(_ id: UUID, title: String) throws {
        let cleanTitle = try normalizedTitle(title)
        try mutate {
            guard let index = projectItems.firstIndex(where: { $0.id == id }) else {
                throw StoreError.projectNotFound
            }
            projectItems[index].title = cleanTitle
        }
    }

    public func setProjectArchived(_ id: UUID, isArchived: Bool) throws {
        try mutate {
            guard let index = projectItems.firstIndex(where: { $0.id == id }) else {
                throw StoreError.projectNotFound
            }
            projectItems[index].isArchived = isArchived
            projectItems[index].archivedAt = isArchived ? now() : nil
        }
    }

    @discardableResult
    public func addStep(_ projectID: UUID, title: String) throws -> ProjectStep {
        let cleanTitle = try normalizedTitle(title)
        return try mutate {
            guard let projectIndex = projectItems.firstIndex(where: { $0.id == projectID }) else {
                throw StoreError.projectNotFound
            }
            let step = ProjectStep(title: cleanTitle, createdAt: now())
            projectItems[projectIndex].steps.append(step)
            sortSteps(projectIndex: projectIndex)
            return step
        }
    }

    public func updateStepTitle(projectID: UUID, stepID: UUID, title: String) throws {
        let cleanTitle = try normalizedTitle(title)
        try mutate {
            try updateStepInMemory(projectID: projectID, stepID: stepID) { step in
                step.title = cleanTitle
                if let scheduledTodoID = step.scheduledTodoID,
                   let todoIndex = items.firstIndex(where: { $0.id == scheduledTodoID }) {
                    items[todoIndex].title = cleanTitle
                }
            }
        }
    }

    public func deleteStep(projectID: UUID, stepID: UUID) throws {
        try mutate {
            guard let projectIndex = projectItems.firstIndex(where: { $0.id == projectID }) else {
                throw StoreError.projectNotFound
            }
            guard let stepIndex = projectItems[projectIndex].steps.firstIndex(where: { $0.id == stepID }) else {
                throw StoreError.stepNotFound
            }

            if let scheduledTodoID = projectItems[projectIndex].steps[stepIndex].scheduledTodoID {
                items.removeAll { $0.id == scheduledTodoID }
            }
            projectItems[projectIndex].steps.remove(at: stepIndex)
        }
    }

    public func setStepCompleted(projectID: UUID, stepID: UUID, isCompleted: Bool) throws {
        try mutate {
            let completionDate = isCompleted ? now() : nil
            try updateStepInMemory(projectID: projectID, stepID: stepID) { step in
                step.isCompleted = isCompleted
                step.completedAt = completionDate

                if let scheduledTodoID = step.scheduledTodoID,
                   let todoIndex = items.firstIndex(where: { $0.id == scheduledTodoID }) {
                    items[todoIndex].isCompleted = isCompleted
                    items[todoIndex].completedAt = completionDate
                }
            }
        }
    }

    @discardableResult
    public func scheduleStepForToday(projectID: UUID, stepID: UUID) throws -> TodoItem {
        try mutate {
            guard let projectIndex = projectItems.firstIndex(where: { $0.id == projectID }) else {
                throw StoreError.projectNotFound
            }
            guard let stepIndex = projectItems[projectIndex].steps.firstIndex(where: { $0.id == stepID }) else {
                throw StoreError.stepNotFound
            }

            let step = projectItems[projectIndex].steps[stepIndex]
            if let scheduledTodoID = step.scheduledTodoID,
               items.contains(where: { $0.id == scheduledTodoID }) {
                throw StoreError.stepAlreadyScheduled
            }

            let item = TodoItem(
                title: step.title,
                day: today(),
                isCompleted: step.isCompleted,
                createdAt: now(),
                completedAt: step.completedAt,
                projectID: projectID,
                stepID: stepID
            )
            items.append(item)
            projectItems[projectIndex].steps[stepIndex].scheduledTodoID = item.id
            sortItems()
            return item
        }
    }

    public func todayItems(showCompleted: Bool) -> [TodoItem] {
        let currentDay = today()
        return items
            .filter { $0.day == currentDay }
            .filter { showCompleted || !$0.isCompleted }
            .sorted(by: itemSort)
    }

    public func archivedItems() -> [TodoItem] {
        let currentDay = today()
        return items
            .filter { $0.isCompleted && $0.day != currentDay }
            .sorted(by: itemSort)
    }

    public func projects(showArchived: Bool) -> [Project] {
        projectItems
            .filter { showArchived || !$0.isArchived }
            .sorted(by: projectSort)
    }

    public func projectTitle(for item: TodoItem) -> String? {
        guard let projectID = item.projectID else {
            return nil
        }
        return projectItems.first(where: { $0.id == projectID })?.title
    }

    public static func defaultStorageURL(
        fileManager: FileManager = .default,
        bundleIdentifier: String = "com.local.MyTodo"
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("tasks.json")
    }

    public static func currentDayString() -> String {
        Self.dayFormatter.string(from: Date())
    }

    @discardableResult
    private func rollOpenItemsForwardIfNeeded() -> Bool {
        let currentDay = today()
        var changed = false

        for index in items.indices where !items[index].isCompleted && items[index].day != currentDay {
            items[index].day = currentDay
            changed = true
        }

        if changed {
            sortItems()
        }
        return changed
    }

    private func mutate<T>(_ updates: () throws -> T) throws -> T {
        let previousItems = items
        let previousProjects = projectItems

        do {
            let result = try updates()
            try save()
            return result
        } catch {
            items = previousItems
            projectItems = previousProjects
            throw error
        }
    }

    private func mutate(_ updates: () throws -> Void) throws {
        let previousItems = items
        let previousProjects = projectItems

        do {
            try updates()
            try save()
        } catch {
            items = previousItems
            projectItems = previousProjects
            throw error
        }
    }

    private func updateStepInMemory(
        projectID: UUID,
        stepID: UUID,
        _ update: (inout ProjectStep) throws -> Void
    ) throws {
        guard let projectIndex = projectItems.firstIndex(where: { $0.id == projectID }) else {
            throw StoreError.projectNotFound
        }
        guard let stepIndex = projectItems[projectIndex].steps.firstIndex(where: { $0.id == stepID }) else {
            throw StoreError.stepNotFound
        }

        try update(&projectItems[projectIndex].steps[stepIndex])
        sortSteps(projectIndex: projectIndex)
    }

    private func save() throws {
        let directory = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = TodoDatabase(todos: items, projects: projectItems)
        let data = try JSONEncoder.todoItemsEncoder.encode(database)
        try data.write(to: storageURL, options: [.atomic])
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            throw StoreError.blankTitle
        }
        return cleanTitle
    }

    private func sortItems() {
        items.sort(by: itemSort)
    }

    private func sortProjects() {
        projectItems.sort(by: projectSort)
    }

    private func sortSteps(projectIndex: Int) {
        projectItems[projectIndex].steps.sort { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func itemSort(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return !lhs.isCompleted
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func projectSort(_ lhs: Project, _ rhs: Project) -> Bool {
        if lhs.isArchived != rhs.isArchived {
            return !lhs.isArchived
        }
        return lhs.createdAt < rhs.createdAt
    }

    private static func loadDatabase(from url: URL) throws -> (database: TodoDatabase, needsSave: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (TodoDatabase(), false)
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return (TodoDatabase(), false)
        }

        if let database = try? JSONDecoder.todoItemsDecoder.decode(TodoDatabase.self, from: data) {
            return (database, false)
        }

        let legacyItems = try JSONDecoder.todoItemsDecoder.decode([TodoItem].self, from: data)
        return (TodoDatabase(todos: legacyItems, projects: []), true)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

