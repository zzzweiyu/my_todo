import Combine
import Foundation

public struct WeekRange: Equatable, Sendable {
    public let startDay: String
    public let endDay: String

    public init(startDay: String, endDay: String) {
        self.startDay = startDay
        self.endDay = endDay
    }

    public func contains(day: String) -> Bool {
        startDay <= day && day <= endDay
    }
}

public struct WeeklyEvidenceItem: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let projectPath: String?
    public let status: WeeklyReportStatus
    public let note: String?
    public let isCompleted: Bool
    public let day: String?
    public let completedAt: Date?
}

public struct WeeklySummary: Equatable, Sendable {
    public let range: WeekRange
    public let evidence: [WeeklyEvidenceItem]

    public init(range: WeekRange, evidence: [WeeklyEvidenceItem]) {
        self.range = range
        self.evidence = evidence.sorted(by: Self.sortEvidence)
    }

    public var open: [WeeklyEvidenceItem] {
        evidence.filter { !$0.isCompleted }
    }

    public var completed: [WeeklyEvidenceItem] {
        evidence.filter(\.isCompleted)
    }

    public var blockers: [WeeklyEvidenceItem] {
        evidence.filter { $0.status == .blocker }
    }

    public var followUps: [WeeklyEvidenceItem] {
        evidence.filter { $0.status == .followUp }
    }

    public var completionFraction: Double {
        guard !evidence.isEmpty else {
            return 0
        }
        return Double(completed.count) / Double(evidence.count)
    }

    private static func sortEvidence(_ lhs: WeeklyEvidenceItem, _ rhs: WeeklyEvidenceItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return !lhs.isCompleted
        }
        let lhsDate = lhs.completedAt ?? .distantPast
        let rhsDate = rhs.completedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.title < rhs.title
    }
}

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
    @Published public private(set) var weeklyReportDrafts: [WeeklyReportDraft]

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
        self.weeklyReportDrafts = loaded.database.weeklyReportDrafts

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

    public func updateWeeklyReportMetadata(
        _ id: UUID,
        status: WeeklyReportStatus,
        note: String?
    ) throws {
        let cleanNote = normalizedOptionalNote(note)
        try mutate {
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                throw StoreError.itemNotFound
            }

            items[index].weeklyReportStatus = status
            items[index].weeklyReportNote = cleanNote

            if let projectID = items[index].projectID, let stepID = items[index].stepID {
                try updateStepInMemory(projectID: projectID, stepID: stepID) { step in
                    step.weeklyReportStatus = status
                    step.weeklyReportNote = cleanNote
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

    public func clearCompletedToday() throws {
        try mutate {
            let currentDay = today()
            let completedItems = items.filter { $0.day == currentDay && $0.isCompleted }

            for item in completedItems {
                if let projectID = item.projectID, let stepID = item.stepID {
                    try updateStepInMemory(projectID: projectID, stepID: stepID) { step in
                        if step.scheduledTodoID == item.id {
                            step.scheduledTodoID = nil
                        }
                    }
                }
            }

            let completedIDs = Set(completedItems.map(\.id))
            items.removeAll { completedIDs.contains($0.id) }
        }
    }

    public func restoreArchivedItemToToday(_ id: UUID) throws {
        try mutate {
            let currentDay = today()
            guard let index = items.firstIndex(where: { $0.id == id && $0.isCompleted && $0.day != currentDay }) else {
                throw StoreError.itemNotFound
            }

            items[index].day = currentDay
            items[index].isCompleted = false
            items[index].completedAt = nil

            if let projectID = items[index].projectID, let stepID = items[index].stepID {
                try updateStepInMemory(projectID: projectID, stepID: stepID) { step in
                    step.isCompleted = false
                    step.completedAt = nil
                    step.scheduledTodoID = id
                }
            }

            sortItems()
        }
    }

    @discardableResult
    public func refreshForCurrentDay() throws -> Bool {
        let previousItems = items
        let previousProjects = projectItems

        do {
            let changed = rollOpenItemsForwardIfNeeded()
            if changed {
                try save()
            }
            return changed
        } catch {
            items = previousItems
            projectItems = previousProjects
            throw error
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

    @discardableResult
    public func addChildStep(projectID: UUID, parentStepID: UUID, title: String) throws -> ProjectStep {
        let cleanTitle = try normalizedTitle(title)
        return try mutate {
            let step = ProjectStep(title: cleanTitle, createdAt: now())
            try updateStepInMemory(projectID: projectID, stepID: parentStepID) { parent in
                parent.children.append(step)
            }
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
                let removed = try removeStepInMemory(
                    from: &projectItems[projectIndex].steps,
                    stepID: stepID
                )
                for scheduledTodoID in removed.scheduledTodoIDs {
                    items.removeAll { $0.id == scheduledTodoID }
                }
                return
            }

            let removed = projectItems[projectIndex].steps.remove(at: stepIndex)
            for scheduledTodoID in removed.scheduledTodoIDs {
                items.removeAll { $0.id == scheduledTodoID }
            }
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

    public func updateStepWeeklyReportMetadata(
        projectID: UUID,
        stepID: UUID,
        status: WeeklyReportStatus,
        note: String?
    ) throws {
        let cleanNote = normalizedOptionalNote(note)
        try mutate {
            try updateStepInMemory(projectID: projectID, stepID: stepID) { step in
                step.weeklyReportStatus = status
                step.weeklyReportNote = cleanNote

                if let scheduledTodoID = step.scheduledTodoID,
                   let todoIndex = items.firstIndex(where: { $0.id == scheduledTodoID }) {
                    items[todoIndex].weeklyReportStatus = status
                    items[todoIndex].weeklyReportNote = cleanNote
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
            guard let step = findStep(in: projectItems[projectIndex].steps, stepID: stepID) else {
                throw StoreError.stepNotFound
            }

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
            try updateStepInMemory(projectID: projectID, stepID: stepID) { step in
                step.scheduledTodoID = item.id
            }
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

    public func projectPath(for item: TodoItem) -> String? {
        projectPathComponents(for: item)?.joined(separator: " / ")
    }

    public func projectPathComponents(for item: TodoItem) -> [String]? {
        guard let projectID = item.projectID,
              let project = projectItems.first(where: { $0.id == projectID }) else {
            return nil
        }

        guard let stepID = item.stepID,
              let stepPath = stepPath(in: project.steps, stepID: stepID) else {
            return [project.title]
        }

        return [project.title] + stepPath
    }

    public func weeklySummary(containing day: String? = nil) -> WeeklySummary {
        let range = Self.weekRange(containing: day ?? today())
        let todoEvidence = items.compactMap { weeklyEvidence(for: $0, range: range) }
        let scheduledTodoIDs = Set(items.map(\.id))
        let projectEvidence = projectItems
            .filter { !$0.isArchived }
            .flatMap { project in
                weeklyEvidence(
                    for: project.steps,
                    projectTitle: project.title,
                    parentPath: [],
                    range: range,
                    scheduledTodoIDs: scheduledTodoIDs
                )
            }

        return WeeklySummary(range: range, evidence: todoEvidence + projectEvidence)
    }

    public func weeklyReportDraft(weekStartDay: String) -> WeeklyReportDraft? {
        weeklyReportDrafts.first { $0.weekStartDay == weekStartDay }
    }

    public func saveWeeklyReportDraft(weekStartDay: String, markdown: String) throws {
        let cleanMarkdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        try mutate {
            let updatedAt = now()
            if let index = weeklyReportDrafts.firstIndex(where: { $0.weekStartDay == weekStartDay }) {
                weeklyReportDrafts[index].markdown = cleanMarkdown
                weeklyReportDrafts[index].updatedAt = updatedAt
            } else {
                weeklyReportDrafts.append(WeeklyReportDraft(
                    weekStartDay: weekStartDay,
                    markdown: cleanMarkdown,
                    createdAt: updatedAt,
                    updatedAt: updatedAt
                ))
            }
            weeklyReportDrafts.sort { $0.weekStartDay < $1.weekStartDay }
        }
    }

    public static func weekRange(containing day: String) -> WeekRange {
        guard let date = date(fromDay: day) else {
            return WeekRange(startDay: day, endDay: day)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .current

        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        let startDate = calendar.date(byAdding: .day, value: -daysFromMonday, to: date) ?? date
        let endDate = calendar.date(byAdding: .day, value: 6, to: startDate) ?? startDate

        return WeekRange(
            startDay: dayFormatter.string(from: startDate),
            endDay: dayFormatter.string(from: endDate)
        )
    }

    public static func date(fromDay day: String) -> Date? {
        dayFormatter.date(from: day)
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
        let previousDrafts = weeklyReportDrafts

        do {
            let result = try updates()
            try save()
            return result
        } catch {
            items = previousItems
            projectItems = previousProjects
            weeklyReportDrafts = previousDrafts
            throw error
        }
    }

    private func mutate(_ updates: () throws -> Void) throws {
        let previousItems = items
        let previousProjects = projectItems
        let previousDrafts = weeklyReportDrafts

        do {
            try updates()
            try save()
        } catch {
            items = previousItems
            projectItems = previousProjects
            weeklyReportDrafts = previousDrafts
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

        guard try updateStep(in: &projectItems[projectIndex].steps, stepID: stepID, update) else {
            throw StoreError.stepNotFound
        }
        sortSteps(&projectItems[projectIndex].steps)
    }

    private func updateStep(
        in steps: inout [ProjectStep],
        stepID: UUID,
        _ update: (inout ProjectStep) throws -> Void
    ) throws -> Bool {
        for index in steps.indices {
            if steps[index].id == stepID {
                try update(&steps[index])
                return true
            }

            if try updateStep(in: &steps[index].children, stepID: stepID, update) {
                return true
            }
        }

        return false
    }

    private func findStep(in steps: [ProjectStep], stepID: UUID) -> ProjectStep? {
        for step in steps {
            if step.id == stepID {
                return step
            }

            if let child = findStep(in: step.children, stepID: stepID) {
                return child
            }
        }

        return nil
    }

    private func stepPath(in steps: [ProjectStep], stepID: UUID) -> [String]? {
        for step in steps {
            if step.id == stepID {
                return [step.title]
            }

            if let childPath = stepPath(in: step.children, stepID: stepID) {
                return [step.title] + childPath
            }
        }

        return nil
    }

    private func removeStepInMemory(from steps: inout [ProjectStep], stepID: UUID) throws -> ProjectStep {
        if let index = steps.firstIndex(where: { $0.id == stepID }) {
            return steps.remove(at: index)
        }

        for index in steps.indices {
            if let removed = try? removeStepInMemory(from: &steps[index].children, stepID: stepID) {
                return removed
            }
        }

        throw StoreError.stepNotFound
    }

    private func save() throws {
        let directory = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = TodoDatabase(
            todos: items,
            projects: projectItems,
            weeklyReportDrafts: weeklyReportDrafts
        )
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

    private func normalizedOptionalNote(_ note: String?) -> String? {
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleanNote.isEmpty ? nil : cleanNote
    }

    private func weeklyEvidence(for item: TodoItem, range: WeekRange) -> WeeklyEvidenceItem? {
        let completedDay = item.completedAt.map { Self.dayFormatter.string(from: $0) }
        let isRelevant: Bool

        if item.isCompleted {
            isRelevant = completedDay.map(range.contains(day:)) ?? range.contains(day: item.day)
        } else {
            isRelevant = range.contains(day: item.day)
        }

        guard isRelevant else {
            return nil
        }

        return WeeklyEvidenceItem(
            id: item.id,
            title: item.title,
            projectPath: projectPath(for: item),
            status: item.weeklyReportStatus,
            note: item.weeklyReportNote,
            isCompleted: item.isCompleted,
            day: item.day,
            completedAt: item.completedAt
        )
    }

    private func weeklyEvidence(
        for steps: [ProjectStep],
        projectTitle: String,
        parentPath: [String],
        range: WeekRange,
        scheduledTodoIDs: Set<UUID>
    ) -> [WeeklyEvidenceItem] {
        steps.flatMap { step in
            let path = parentPath + [step.title]
            var evidence: [WeeklyEvidenceItem] = []

            if step.scheduledTodoID.map({ !scheduledTodoIDs.contains($0) }) ?? true {
                let completedDay = step.completedAt.map { Self.dayFormatter.string(from: $0) }
                let isCompletedInWeek = completedDay.map(range.contains(day:)) ?? false
                let shouldInclude = isCompletedInWeek || step.weeklyReportStatus != .normal

                if shouldInclude {
                    evidence.append(WeeklyEvidenceItem(
                        id: step.id,
                        title: step.title,
                        projectPath: ([projectTitle] + path).joined(separator: " / "),
                        status: step.weeklyReportStatus,
                        note: step.weeklyReportNote,
                        isCompleted: step.isCompleted,
                        day: nil,
                        completedAt: step.completedAt
                    ))
                }
            }

            evidence.append(contentsOf: weeklyEvidence(
                for: step.children,
                projectTitle: projectTitle,
                parentPath: path,
                range: range,
                scheduledTodoIDs: scheduledTodoIDs
            ))
            return evidence
        }
    }

    private func sortItems() {
        items.sort(by: itemSort)
    }

    private func sortProjects() {
        projectItems.sort(by: projectSort)
    }

    private func sortSteps(projectIndex: Int) {
        sortSteps(&projectItems[projectIndex].steps)
    }

    private func sortSteps(_ steps: inout [ProjectStep]) {
        for index in steps.indices {
            sortSteps(&steps[index].children)
        }

        steps.sort { lhs, rhs in
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

private extension ProjectStep {
    var scheduledTodoIDs: [UUID] {
        var ids = scheduledTodoID.map { [$0] } ?? []
        ids.append(contentsOf: children.flatMap(\.scheduledTodoIDs))
        return ids
    }
}
