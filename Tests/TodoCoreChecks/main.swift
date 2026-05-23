import Foundation
import TodoCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure.failed(message)
    }
}

func temporaryStoreURL(_ name: String = UUID().uuidString) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MyTodoChecks", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("\(name).json")
}

func checkAddingTaskPersistsAndReloads() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })

    try store.add(title: "  写日报  ")

    try expect(store.todayItems(showCompleted: true).map(\.title) == ["写日报"], "new task should appear trimmed")

    let reloaded = try TodoStore(storageURL: url, today: { "2026-05-11" })
    try expect(reloaded.todayItems(showCompleted: true).map(\.title) == ["写日报"], "task should reload from disk")
}

func checkCompletingTaskCanBeHiddenFromTodayList() throws {
    let now = Date(timeIntervalSince1970: 1_777_777_777)
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" }, now: { now })
    let item = try store.add(title: "看 PR")

    try store.setCompleted(item.id, isCompleted: true)

    try expect(store.todayItems(showCompleted: true)[0].isCompleted, "completed task should be marked completed")
    try expect(store.todayItems(showCompleted: false) == [], "completed task should hide when requested")
    try expect(store.todayItems(showCompleted: true)[0].completedAt == now, "completed task should record completion date")
}

func checkEditingAndDeletingTasksPersist() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let item = try store.add(title: "约体检")

    try store.updateTitle(item.id, title: "预约体检")
    try expect(store.todayItems(showCompleted: true).map(\.title) == ["预约体检"], "edited title should update")

    try store.delete(item.id)

    let reloaded = try TodoStore(storageURL: url, today: { "2026-05-11" })
    try expect(reloaded.todayItems(showCompleted: true) == [], "deleted task should not reload")
}

func checkRolloverMovesUnfinishedTasksToTodayAndKeepsCompletedArchived() throws {
    let url = try temporaryStoreURL()
    let yesterdayCompleted = TodoItem(
        id: UUID(),
        title: "已完成",
        day: "2026-05-10",
        isCompleted: true,
        createdAt: Date(timeIntervalSince1970: 10),
        completedAt: Date(timeIntervalSince1970: 20)
    )
    let yesterdayOpen = TodoItem(
        id: UUID(),
        title: "未完成",
        day: "2026-05-10",
        isCompleted: false,
        createdAt: Date(timeIntervalSince1970: 30),
        completedAt: nil
    )
    let data = try JSONEncoder.todoItemsEncoder.encode([yesterdayCompleted, yesterdayOpen])
    try data.write(to: url)

    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })

    try expect(store.todayItems(showCompleted: true).map(\.title) == ["未完成"], "only unfinished task should appear today")
    try expect(store.todayItems(showCompleted: true)[0].day == "2026-05-11", "unfinished task should move to today")
    try expect(store.archivedItems().map(\.title) == ["已完成"], "completed task should remain archived")
}

func checkFailedSaveRollsBackInMemoryChanges() throws {
    let blockingFile = try temporaryStoreURL("blocked-directory")
    try Data("not a directory".utf8).write(to: blockingFile)
    let blockedStorageURL = blockingFile.appendingPathComponent("tasks.json")
    let store = try TodoStore(storageURL: blockedStorageURL, today: { "2026-05-11" })

    do {
        _ = try store.add(title: "无法保存")
        throw CheckFailure.failed("add should fail when storage directory cannot be created")
    } catch CheckFailure.failed {
        throw CheckFailure.failed("add should fail when storage directory cannot be created")
    } catch {
        try expect(store.todayItems(showCompleted: true) == [], "failed add should not remain in memory")
    }
}

func checkFailedProjectSaveRollsBackInMemoryChanges() throws {
    let blockingFile = try temporaryStoreURL("blocked-project-directory")
    try Data("not a directory".utf8).write(to: blockingFile)
    let blockedStorageURL = blockingFile.appendingPathComponent("tasks.json")
    let store = try TodoStore(storageURL: blockedStorageURL, today: { "2026-05-11" })

    do {
        _ = try store.addProject(title: "无法保存的项目")
        throw CheckFailure.failed("project add should fail when storage directory cannot be created")
    } catch CheckFailure.failed {
        throw CheckFailure.failed("project add should fail when storage directory cannot be created")
    } catch {
        try expect(store.projects(showArchived: true) == [], "failed project add should not remain in memory")
    }
}

func checkLegacyTodoArrayMigratesToVersionedDatabase() throws {
    let url = try temporaryStoreURL()
    let legacyTodo = TodoItem(
        id: UUID(),
        title: "旧任务",
        day: "2026-05-11",
        isCompleted: false,
        createdAt: Date(timeIntervalSince1970: 100),
        completedAt: nil
    )
    let legacyData = try JSONEncoder.todoItemsEncoder.encode([legacyTodo])
    try legacyData.write(to: url)

    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })

    try expect(store.todayItems(showCompleted: true).map(\.title) == ["旧任务"], "legacy todo should load")
    try expect(store.projects(showArchived: true) == [], "legacy file should start with no projects")

    let savedData = try Data(contentsOf: url)
    let savedDatabase = try JSONDecoder.todoItemsDecoder.decode(TodoDatabase.self, from: savedData)
    try expect(savedDatabase.version == 1, "legacy file should save back as versioned database")
    try expect(savedDatabase.todos.map(\.title) == ["旧任务"], "migrated database should preserve todos")
}

func checkProjectAndStepsPersist() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })

    let project = try store.addProject(title: "写论文")
    let step = try store.addStep(project.id, title: "整理大纲")

    let reloaded = try TodoStore(storageURL: url, today: { "2026-05-11" })
    try expect(reloaded.projects(showArchived: true).map(\.title) == ["写论文"], "project should persist")
    try expect(reloaded.projects(showArchived: true)[0].steps.map(\.title) == ["整理大纲"], "step should persist")
    try expect(reloaded.projects(showArchived: true)[0].steps[0].id == step.id, "step identity should persist")
}

func checkSchedulingProjectStepCreatesLinkedTodayItemOnce() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let project = try store.addProject(title: "写论文")
    let step = try store.addStep(project.id, title: "整理大纲")

    let todo = try store.scheduleStepForToday(projectID: project.id, stepID: step.id)

    let todayItems = store.todayItems(showCompleted: true)
    try expect(todayItems.count == 1, "scheduled step should appear in today")
    try expect(todayItems[0].projectID == project.id, "today item should link to project")
    try expect(todayItems[0].stepID == step.id, "today item should link to step")
    try expect(store.projectTitle(for: todayItems[0]) == "写论文", "today item should expose project title")
    try expect(store.projects(showArchived: true)[0].steps[0].scheduledTodoID == todo.id, "step should remember scheduled todo")

    do {
        _ = try store.scheduleStepForToday(projectID: project.id, stepID: step.id)
        throw CheckFailure.failed("duplicate schedule should fail")
    } catch TodoStore.StoreError.stepAlreadyScheduled {
        try expect(store.todayItems(showCompleted: true).count == 1, "duplicate schedule should not create second todo")
    }
}

func checkTodayCompletionSyncsProjectStep() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" }, now: { now })
    let project = try store.addProject(title: "写论文")
    let step = try store.addStep(project.id, title: "整理大纲")
    let todo = try store.scheduleStepForToday(projectID: project.id, stepID: step.id)

    try store.setCompleted(todo.id, isCompleted: true)

    let savedStep = store.projects(showArchived: true)[0].steps[0]
    try expect(savedStep.isCompleted, "completing today item should complete linked step")
    try expect(savedStep.completedAt == now, "linked step should record completion date")
}

func checkProjectStepCompletionSyncsTodayItem() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_001)
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" }, now: { now })
    let project = try store.addProject(title: "写论文")
    let step = try store.addStep(project.id, title: "整理大纲")
    let todo = try store.scheduleStepForToday(projectID: project.id, stepID: step.id)

    try store.setStepCompleted(projectID: project.id, stepID: step.id, isCompleted: true)

    let savedTodo = store.todayItems(showCompleted: true).first { $0.id == todo.id }
    try expect(savedTodo?.isCompleted == true, "completing project step should complete linked today item")
    try expect(savedTodo?.completedAt == now, "linked today item should record completion date")
}

func checkDeletingLinkedTodayItemOnlyUnschedulesProjectStep() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let project = try store.addProject(title: "写论文")
    let step = try store.addStep(project.id, title: "整理大纲")
    let todo = try store.scheduleStepForToday(projectID: project.id, stepID: step.id)

    try store.delete(todo.id)

    let savedStep = store.projects(showArchived: true)[0].steps[0]
    try expect(store.todayItems(showCompleted: true) == [], "linked today item should be removed")
    try expect(savedStep.title == "整理大纲", "project step should remain")
    try expect(savedStep.scheduledTodoID == nil, "project step should be schedulable again")

    _ = try store.scheduleStepForToday(projectID: project.id, stepID: step.id)
    try expect(store.todayItems(showCompleted: true).count == 1, "unscheduled step can be added today again")
}

func checkArchivedProjectsHideByDefault() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let active = try store.addProject(title: "活跃项目")
    let archived = try store.addProject(title: "归档项目")

    try store.setProjectArchived(archived.id, isArchived: true)

    try expect(store.projects(showArchived: false).map(\.id) == [active.id], "archived projects should hide by default")
    try expect(store.projects(showArchived: true).map(\.title) == ["活跃项目", "归档项目"], "show archived should include archived projects")
}

let checks = [
    ("adding task persists and reloads", checkAddingTaskPersistsAndReloads),
    ("completing task can be hidden", checkCompletingTaskCanBeHiddenFromTodayList),
    ("editing and deleting persist", checkEditingAndDeletingTasksPersist),
    ("rollover archives completed tasks", checkRolloverMovesUnfinishedTasksToTodayAndKeepsCompletedArchived),
    ("failed save rolls back memory", checkFailedSaveRollsBackInMemoryChanges),
    ("failed project save rolls back memory", checkFailedProjectSaveRollsBackInMemoryChanges),
    ("legacy todo array migrates to database", checkLegacyTodoArrayMigratesToVersionedDatabase),
    ("project and steps persist", checkProjectAndStepsPersist),
    ("scheduling project step links today item once", checkSchedulingProjectStepCreatesLinkedTodayItemOnce),
    ("today completion syncs project step", checkTodayCompletionSyncsProjectStep),
    ("project step completion syncs today item", checkProjectStepCompletionSyncsTodayItem),
    ("deleting linked today item only unschedules project step", checkDeletingLinkedTodayItemOnlyUnschedulesProjectStep),
    ("archived projects hide by default", checkArchivedProjectsHideByDefault)
]

do {
    for (name, check) in checks {
        try check()
        print("PASS: \(name)")
    }
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
