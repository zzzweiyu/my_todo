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

func checkClearingCompletedTodayKeepsOpenAndArchivedItems() throws {
    let url = try temporaryStoreURL()
    let archived = TodoItem(
        title: "历史完成",
        day: "2026-05-10",
        isCompleted: true,
        createdAt: Date(timeIntervalSince1970: 10),
        completedAt: Date(timeIntervalSince1970: 20)
    )
    let data = try JSONEncoder.todoItemsEncoder.encode(TodoDatabase(todos: [archived], projects: []))
    try data.write(to: url)

    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let open = try store.add(title: "未完成")
    let completed = try store.add(title: "已完成")
    try store.setCompleted(completed.id, isCompleted: true)

    try store.clearCompletedToday()

    try expect(store.todayItems(showCompleted: true).map(\.id) == [open.id], "clearing completed today should keep open item")
    try expect(store.archivedItems().map(\.title) == ["历史完成"], "clearing completed today should not remove archived items")
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

func checkArchivedTaskCanBeRestoredToToday() throws {
    let completedAt = Date(timeIntervalSince1970: 20)
    let archived = TodoItem(
        title: "历史完成",
        day: "2026-05-10",
        isCompleted: true,
        createdAt: Date(timeIntervalSince1970: 10),
        completedAt: completedAt,
        weeklyReportStatus: .followUp,
        weeklyReportNote: "恢复后继续跟进"
    )
    let url = try temporaryStoreURL()
    let data = try JSONEncoder.todoItemsEncoder.encode(TodoDatabase(todos: [archived], projects: []))
    try data.write(to: url)

    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })

    try store.restoreArchivedItemToToday(archived.id)

    try expect(store.archivedItems() == [], "restored archived item should leave archive")
    let restored = store.todayItems(showCompleted: true)[0]
    try expect(restored.id == archived.id, "restore should keep item identity")
    try expect(restored.day == "2026-05-11", "restored item should move to today")
    try expect(!restored.isCompleted, "restored item should become open")
    try expect(restored.completedAt == nil, "restored item should clear completion date")
    try expect(restored.weeklyReportStatus == .followUp, "restore should preserve weekly report status")
    try expect(restored.weeklyReportNote == "恢复后继续跟进", "restore should preserve weekly report note")
}

func checkRestoringArchivedProjectTaskSyncsLinkedStep() throws {
    var currentDay = "2026-05-10"
    let completedAt = Date(timeIntervalSince1970: 30)
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { currentDay }, now: { completedAt })
    let project = try store.addProject(title: "写论文")
    let step = try store.addStep(project.id, title: "整理大纲")
    let todo = try store.scheduleStepForToday(projectID: project.id, stepID: step.id)

    try store.setCompleted(todo.id, isCompleted: true)
    currentDay = "2026-05-11"

    try expect(store.archivedItems().map(\.id) == [todo.id], "completed linked task should be archived on a later day")

    try store.restoreArchivedItemToToday(todo.id)

    let restoredTodo = store.todayItems(showCompleted: true)[0]
    let restoredStep = store.projects(showArchived: true)[0].steps[0]
    try expect(restoredTodo.id == todo.id, "restored linked todo should keep identity")
    try expect(restoredTodo.day == "2026-05-11", "restored linked todo should move to today")
    try expect(!restoredTodo.isCompleted, "restored linked todo should become open")
    try expect(restoredTodo.completedAt == nil, "restored linked todo should clear completion date")
    try expect(!restoredStep.isCompleted, "restoring linked todo should reopen project step")
    try expect(restoredStep.completedAt == nil, "restoring linked todo should clear step completion date")
    try expect(restoredStep.scheduledTodoID == todo.id, "restoring linked todo should keep step linked to today item")
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

func checkNestedProjectStepsPersistAndCountRecursively() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let project = try store.addProject(title: "写论文")
    let parent = try store.addStep(project.id, title: "整理大纲")
    let child = try store.addChildStep(projectID: project.id, parentStepID: parent.id, title: "列章节")

    try store.setStepCompleted(projectID: project.id, stepID: child.id, isCompleted: true)

    let savedProject = store.projects(showArchived: true)[0]
    try expect(savedProject.totalStepCount == 2, "project should count parent and child steps")
    try expect(savedProject.completedStepCount == 1, "project should count completed child step")

    let reloaded = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let reloadedParent = reloaded.projects(showArchived: true)[0].steps[0]
    try expect(reloadedParent.children.map(\.title) == ["列章节"], "child step should persist under parent")
    try expect(reloadedParent.children[0].isCompleted, "child completion should persist")
}

func checkProjectStepOpenCountsRecurseThroughChildren() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let project = try store.addProject(title: "写论文")
    let parent = try store.addStep(project.id, title: "整理大纲")
    let scheduledChild = try store.addChildStep(projectID: project.id, parentStepID: parent.id, title: "列章节")
    let doneChild = try store.addChildStep(projectID: project.id, parentStepID: parent.id, title: "删除废稿")

    _ = try store.scheduleStepForToday(projectID: project.id, stepID: scheduledChild.id)
    try store.setStepCompleted(projectID: project.id, stepID: doneChild.id, isCompleted: true)

    let savedProject = store.projects(showArchived: true)[0]
    try expect(savedProject.openStepCount == 2, "project should count open parent and scheduled child")
    try expect(savedProject.unscheduledOpenStepCount == 1, "project should count only open steps not already scheduled")
}

func checkNestedProjectStepSchedulesAndSyncsTodayItem() throws {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" }, now: { now })
    let project = try store.addProject(title: "写论文")
    let parent = try store.addStep(project.id, title: "整理大纲")
    let child = try store.addChildStep(projectID: project.id, parentStepID: parent.id, title: "列章节")

    let todo = try store.scheduleStepForToday(projectID: project.id, stepID: child.id)

    try expect(store.todayItems(showCompleted: true).map(\.stepID) == [child.id], "scheduled child should create linked today item")
    try expect(store.projects(showArchived: true)[0].steps[0].children[0].scheduledTodoID == todo.id, "child should remember scheduled todo")

    try store.setCompleted(todo.id, isCompleted: true)

    let savedChild = store.projects(showArchived: true)[0].steps[0].children[0]
    try expect(savedChild.isCompleted, "completing linked today item should complete nested child")
    try expect(savedChild.completedAt == now, "nested child should record completion date")
}

func checkOpenScheduledProjectStepsRefreshWhenDayChanges() throws {
    var currentDay = "2026-05-24"
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { currentDay })
    let project = try store.addProject(title: "跨日项目")
    let parent = try store.addStep(project.id, title: "父步骤")
    let child = try store.addChildStep(projectID: project.id, parentStepID: parent.id, title: "子任务")
    let todo = try store.scheduleStepForToday(projectID: project.id, stepID: child.id)

    currentDay = "2026-05-25"
    let didRefresh = try store.refreshForCurrentDay()

    let todayItems = store.todayItems(showCompleted: true)
    try expect(didRefresh, "refresh should detect open items from a previous day")
    try expect(todayItems.map(\.id) == [todo.id], "scheduled child todo should appear on the new day")
    try expect(todayItems[0].day == "2026-05-25", "scheduled child todo should roll forward to current day")
    try expect(
        store.projects(showArchived: true)[0].steps[0].children[0].scheduledTodoID == todo.id,
        "child step should keep its linked scheduled todo"
    )

    let reloaded = try TodoStore(storageURL: url, today: { currentDay })
    try expect(reloaded.todayItems(showCompleted: true).map(\.id) == [todo.id], "refresh should persist rolled scheduled child todo")
}

func checkScheduledNestedStepExposesFullProjectPath() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let project = try store.addProject(title: "写论文")
    let parent = try store.addStep(project.id, title: "整理大纲")
    let child = try store.addChildStep(projectID: project.id, parentStepID: parent.id, title: "列章节")

    let todo = try store.scheduleStepForToday(projectID: project.id, stepID: child.id)

    try expect(store.projectPath(for: todo) == "写论文 / 整理大纲 / 列章节", "scheduled nested step should expose full parent path")
}

func checkScheduledNestedStepExposesProjectPathComponents() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let project = try store.addProject(title: "写论文")
    let parent = try store.addStep(project.id, title: "整理大纲")
    let child = try store.addChildStep(projectID: project.id, parentStepID: parent.id, title: "列章节")

    let todo = try store.scheduleStepForToday(projectID: project.id, stepID: child.id)

    try expect(
        store.projectPathComponents(for: todo) == ["写论文", "整理大纲", "列章节"],
        "scheduled nested step should expose path components for grouped today display"
    )
}

func checkDeletingParentStepRemovesNestedScheduledTodos() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-11" })
    let project = try store.addProject(title: "写论文")
    let parent = try store.addStep(project.id, title: "整理大纲")
    let child = try store.addChildStep(projectID: project.id, parentStepID: parent.id, title: "列章节")

    _ = try store.scheduleStepForToday(projectID: project.id, stepID: child.id)
    try store.deleteStep(projectID: project.id, stepID: parent.id)

    try expect(store.projects(showArchived: true)[0].steps == [], "deleting parent should remove nested child")
    try expect(store.todayItems(showCompleted: true) == [], "deleting parent should remove nested linked today item")
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

func checkLegacyWeeklyReportFieldsDefaultToNormal() throws {
    let legacyTodoJSON = """
    {
      "version": 1,
      "todos": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "旧任务",
          "day": "2026-05-25",
          "isCompleted": false,
          "createdAt": "2026-05-25T01:00:00Z"
        }
      ],
      "projects": [
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "title": "旧项目",
          "steps": [
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "title": "旧步骤",
              "isCompleted": false,
              "createdAt": "2026-05-25T01:10:00Z"
            }
          ],
          "isArchived": false,
          "createdAt": "2026-05-25T01:05:00Z"
        }
      ]
    }
    """
    let url = try temporaryStoreURL()
    try Data(legacyTodoJSON.utf8).write(to: url)

    let store = try TodoStore(storageURL: url, today: { "2026-05-25" })

    try expect(store.todayItems(showCompleted: true)[0].weeklyReportStatus == .normal, "legacy todo should default weekly status to normal")
    try expect(store.todayItems(showCompleted: true)[0].weeklyReportNote == nil, "legacy todo should default report note to nil")
    try expect(store.projects(showArchived: true)[0].steps[0].weeklyReportStatus == .normal, "legacy step should default weekly status to normal")
    try expect(store.projects(showArchived: true)[0].steps[0].weeklyReportNote == nil, "legacy step should default report note to nil")
}

func checkWeeklyReportMetadataSyncsBetweenLinkedTodoAndStep() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-25" })
    let project = try store.addProject(title: "AI 周报")
    let step = try store.addStep(project.id, title: "接入周报标记")
    let todo = try store.scheduleStepForToday(projectID: project.id, stepID: step.id)

    try store.updateWeeklyReportMetadata(
        todo.id,
        status: .blocker,
        note: "Keychain 权限需要确认"
    )

    let linkedStep = store.projects(showArchived: true)[0].steps[0]
    try expect(linkedStep.weeklyReportStatus == .blocker, "todo metadata should sync status to linked step")
    try expect(linkedStep.weeklyReportNote == "Keychain 权限需要确认", "todo metadata should sync note to linked step")

    try store.updateStepWeeklyReportMetadata(
        projectID: project.id,
        stepID: step.id,
        status: .followUp,
        note: "下周验证复制 Markdown"
    )

    let linkedTodo = store.todayItems(showCompleted: true)[0]
    try expect(linkedTodo.weeklyReportStatus == .followUp, "step metadata should sync status to linked todo")
    try expect(linkedTodo.weeklyReportNote == "下周验证复制 Markdown", "step metadata should sync note to linked todo")
}

func checkWeekRangeUsesMondayThroughSunday() throws {
    let range = TodoStore.weekRange(containing: "2026-05-27")

    try expect(range.startDay == "2026-05-25", "week should start on Monday")
    try expect(range.endDay == "2026-05-31", "week should end on Sunday")
    try expect(range.contains(day: "2026-05-25"), "week should include Monday")
    try expect(range.contains(day: "2026-05-31"), "week should include Sunday")
    try expect(!range.contains(day: "2026-06-01"), "week should exclude next Monday")
}

func checkWeeklySummaryUsesCompletedAtForCompletedItems() throws {
    let monday = Date(timeIntervalSince1970: 1_769_359_200) // 2026-01-25T18:00:00Z local-safe seed is not used for range
    let completedInWeek = TodoItem(
        title: "完成周报 PRD",
        day: "2026-05-20",
        isCompleted: true,
        createdAt: monday,
        completedAt: TodoStore.date(fromDay: "2026-05-26")
    )
    let completedOutsideWeek = TodoItem(
        title: "上周完成",
        day: "2026-05-18",
        isCompleted: true,
        createdAt: monday,
        completedAt: TodoStore.date(fromDay: "2026-05-24")
    )
    let data = try JSONEncoder.todoItemsEncoder.encode(TodoDatabase(todos: [completedInWeek, completedOutsideWeek], projects: []))
    let url = try temporaryStoreURL()
    try data.write(to: url)

    let store = try TodoStore(storageURL: url, today: { "2026-05-27" })
    let summary = store.weeklySummary(containing: "2026-05-27")

    try expect(summary.completed.map(\.title) == ["完成周报 PRD"], "weekly completed items should use completedAt week")
}

func checkWeeklySummaryGroupsOpenBlockersAndFollowUps() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-27" })
    let open = try store.add(title: "实现本周视图")
    let blocker = try store.add(title: "Keychain 权限卡点")
    let followUp = try store.add(title: "跟进 AI 输出格式")
    let previousWeekCompleted = TodoItem(
        title: "上周完成任务",
        day: "2026-05-22",
        isCompleted: true,
        createdAt: Date(timeIntervalSince1970: 20),
        completedAt: TodoStore.date(fromDay: "2026-05-24")
    )
    let data = try JSONEncoder.todoItemsEncoder.encode(TodoDatabase(
        todos: store.todayItems(showCompleted: true) + [previousWeekCompleted],
        projects: store.projects(showArchived: true)
    ))
    try data.write(to: url)

    let reloaded = try TodoStore(storageURL: url, today: { "2026-05-27" })
    try reloaded.updateWeeklyReportMetadata(blocker.id, status: .blocker, note: "需要确认系统权限")
    try reloaded.updateWeeklyReportMetadata(followUp.id, status: .followUp, note: "下周复核 prompt")

    let summary = reloaded.weeklySummary(containing: "2026-05-27")

    try expect(summary.open.map(\.id).contains(open.id), "weekly summary should include open task from current week")
    try expect(summary.blockers.map(\.title) == ["Keychain 权限卡点"], "weekly summary should group blockers")
    try expect(summary.followUps.map(\.title) == ["跟进 AI 输出格式"], "weekly summary should group follow-ups")
    try expect(!summary.completed.map(\.title).contains("上周完成任务"), "weekly summary should exclude completed tasks outside the week")
    try expect(summary.blockers[0].note == "需要确认系统权限", "weekly evidence should keep blocker note")
}

func checkWeeklyReportDraftPersistsByWeekStart() throws {
    let url = try temporaryStoreURL()
    let store = try TodoStore(storageURL: url, today: { "2026-05-27" })
    let currentWeek = TodoStore.weekRange(containing: "2026-05-27")
    let nextWeek = TodoStore.weekRange(containing: "2026-06-03")

    try store.saveWeeklyReportDraft(
        weekStartDay: currentWeek.startDay,
        markdown: "## 本周完成\n- 完成核心模型"
    )
    try store.saveWeeklyReportDraft(
        weekStartDay: nextWeek.startDay,
        markdown: "## 本周完成\n- 下周草稿"
    )

    let reloaded = try TodoStore(storageURL: url, today: { "2026-05-27" })

    try expect(
        reloaded.weeklyReportDraft(weekStartDay: currentWeek.startDay)?.markdown == "## 本周完成\n- 完成核心模型",
        "weekly report draft should persist for its week"
    )
    try expect(
        reloaded.weeklyReportDraft(weekStartDay: nextWeek.startDay)?.markdown == "## 本周完成\n- 下周草稿",
        "weekly report drafts should be isolated by week start"
    )
}

let checks = [
    ("adding task persists and reloads", checkAddingTaskPersistsAndReloads),
    ("completing task can be hidden", checkCompletingTaskCanBeHiddenFromTodayList),
    ("clearing completed today keeps open and archived items", checkClearingCompletedTodayKeepsOpenAndArchivedItems),
    ("editing and deleting persist", checkEditingAndDeletingTasksPersist),
    ("rollover archives completed tasks", checkRolloverMovesUnfinishedTasksToTodayAndKeepsCompletedArchived),
    ("archived task can be restored to today", checkArchivedTaskCanBeRestoredToToday),
    ("restoring archived project task syncs linked step", checkRestoringArchivedProjectTaskSyncsLinkedStep),
    ("failed save rolls back memory", checkFailedSaveRollsBackInMemoryChanges),
    ("failed project save rolls back memory", checkFailedProjectSaveRollsBackInMemoryChanges),
    ("legacy todo array migrates to database", checkLegacyTodoArrayMigratesToVersionedDatabase),
    ("project and steps persist", checkProjectAndStepsPersist),
    ("nested project steps persist and count recursively", checkNestedProjectStepsPersistAndCountRecursively),
    ("project step open counts recurse through children", checkProjectStepOpenCountsRecurseThroughChildren),
    ("nested project step schedules and syncs today item", checkNestedProjectStepSchedulesAndSyncsTodayItem),
    ("open scheduled project steps refresh when day changes", checkOpenScheduledProjectStepsRefreshWhenDayChanges),
    ("scheduled nested step exposes full project path", checkScheduledNestedStepExposesFullProjectPath),
    ("scheduled nested step exposes project path components", checkScheduledNestedStepExposesProjectPathComponents),
    ("deleting parent step removes nested scheduled todos", checkDeletingParentStepRemovesNestedScheduledTodos),
    ("scheduling project step links today item once", checkSchedulingProjectStepCreatesLinkedTodayItemOnce),
    ("today completion syncs project step", checkTodayCompletionSyncsProjectStep),
    ("project step completion syncs today item", checkProjectStepCompletionSyncsTodayItem),
    ("deleting linked today item only unschedules project step", checkDeletingLinkedTodayItemOnlyUnschedulesProjectStep),
    ("archived projects hide by default", checkArchivedProjectsHideByDefault),
    ("legacy weekly report fields default to normal", checkLegacyWeeklyReportFieldsDefaultToNormal),
    ("weekly report metadata syncs between linked todo and step", checkWeeklyReportMetadataSyncsBetweenLinkedTodoAndStep),
    ("week range uses Monday through Sunday", checkWeekRangeUsesMondayThroughSunday),
    ("weekly summary uses completedAt for completed items", checkWeeklySummaryUsesCompletedAtForCompletedItems),
    ("weekly summary groups open blockers and follow-ups", checkWeeklySummaryGroupsOpenBlockersAndFollowUps),
    ("weekly report draft persists by week start", checkWeeklyReportDraftPersistsByWeekStart)
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
