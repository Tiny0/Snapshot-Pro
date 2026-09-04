import SwiftUI
import SwiftData

@main
struct AppSnapshotProApp: App {
    let container: ModelContainer

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        do {
            container = try ModelContainer(for: SnapshotScene.self, SceneGroup.self, DevicePreset.self)
            container.mainContext.undoManager = UndoManager()
        } catch {
            fatalError("Could not initialize ModelContainer")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .modelContainer(container)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .newItem) {
                Button("New Screenshot Project") {
                    createNewScene(type: .screenshot)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Icon Project") {
                    createNewScene(type: .icon)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Divider()

                Button("New Group") {
                    createNewGroup()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { container.mainContext.undoManager?.undo() }.keyboardShortcut("z")
                Button("Redo") { container.mainContext.undoManager?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .textEditing) {
                Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }.keyboardShortcut("x")
                Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }.keyboardShortcut("c")
                Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }.keyboardShortcut("v")
                Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }.keyboardShortcut("a")
            }
        }
    }

    @MainActor
    private func createNewScene(type: ProjectType) {
        let name = type == .screenshot ? "New Scene" : "New Icon"
        let newScene = SnapshotScene(name: name, type: type)
        container.mainContext.insert(newScene)
        // 发送通知让 Sidebar 选中新创建的场景
        NotificationCenter.default.post(name: NSNotification.Name("SelectNewScene"), object: newScene.id)
    }

    @MainActor
    private func createNewGroup() {
        let newGroup = SceneGroup(name: "New Group")
        container.mainContext.insert(newGroup)
    }
}
