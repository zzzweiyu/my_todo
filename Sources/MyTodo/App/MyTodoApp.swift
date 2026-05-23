import SwiftUI
import TodoCore

@main
struct MyTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: TodoStore

    init() {
        do {
            let todoStore = try TodoStore()
            _store = StateObject(wrappedValue: todoStore)
        } catch {
            fatalError("Unable to open todo storage: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            TodoPanelView(store: store)
        } label: {
            Label("MyTodo", systemImage: store.todayItems(showCompleted: false).isEmpty ? "checklist" : "checklist.unchecked")
        }
        .menuBarExtraStyle(.window)
    }
}
