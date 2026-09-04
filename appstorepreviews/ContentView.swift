import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SnapshotScene.name) private var scenes: [SnapshotScene]
    @Query(sort: \DevicePreset.name) private var presets: [DevicePreset]

    @State private var selection = Set<UUID>()
    @State private var focusedSceneId: UUID?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showInspector = true
    @State private var canvasZoom: Double = 0.6

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
        } detail: {
            if !selection.isEmpty {
                editorContent
            } else {
                ContentUnavailableView("Select Scenes", systemImage: "photo.on.rectangle.angled")
            }
        }
        .inspector(isPresented: $showInspector) {
            if let focusedScene = currentFocusedScene {
                InspectorView(scene: focusedScene)
                    .inspectorColumnWidth(min: 250, ideal: 300, max: 450)
            } else {
                ContentUnavailableView("No Selection", systemImage: "selection.pin.in.out")
            }
        }
        .navigationTitle("Snapshot Pro")
        .onAppear {
            if presets.isEmpty {
                DevicePreset.seed(context: modelContext)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SelectNewScene"))) { notification in
            if let id = notification.object as? UUID {
                selection = [id]
                focusedSceneId = id
            }
        }
        .onChange(of: selection) { old, new in
            if !new.isEmpty && (focusedSceneId == nil || !new.contains(focusedSceneId!)) {
                focusedSceneId = new.first
            }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        VStack(spacing: 0) {
            canvasToolbar
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                ScrollView([.horizontal, .vertical]) {
                    HStack(spacing: 40) {
                        ForEach(sortedSelectedScenes) { scene in
                            SceneCanvasItem(
                                scene: scene,
                                isFocused: focusedSceneId == scene.id,
                                canvasZoom: canvasZoom
                            )
                            .onTapGesture { focusedSceneId = scene.id }
                        }
                    }
                    .padding(100)
                    .frame(maxWidth: .infinity, minHeight: 600)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let focused = currentFocusedScene {
                    Button(action: { ExportManager.exportAll(scene: focused) }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                Button(action: { withAnimation { showInspector.toggle() } }) {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
            }
        }
    }

    private var canvasToolbar: some View {
        HStack {
            // 关键：给文字一个固定宽度，防止长度变化推挤滑块导致抖动
            HStack(spacing: 0) {
                Text("Canvas Zoom: ")
                Text("\(Int(canvasZoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 45, alignment: .leading)
            }
            .font(.caption)

            Slider(value: $canvasZoom, in: 0.1...5.0)
                .frame(width: 200)
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var sortedSelectedScenes: [SnapshotScene] {
        scenes.filter { selection.contains($0.id) }
    }

    private var currentFocusedScene: SnapshotScene? {
        scenes.first(where: { $0.id == focusedSceneId })
    }
}

struct SceneCanvasItem: View {
    let scene: SnapshotScene
    let isFocused: Bool
    let canvasZoom: Double

    var body: some View {
        if scene.projectType == .icon {
            // 图标预览逻辑：macOS 强制圆角，iOS 预览显圆角，Other 随开关
            let ismacOS = scene.iconSpec == .macOS
            let showPreviewCorners = (scene.iconSpec == .iOS) || (scene.iconSpec == .other && scene.iconShowCorners) || ismacOS

            IconCanvasView(code: scene.drawingCode, ismacOS: ismacOS, showCorners: showPreviewCorners)
                .frame(width: 300 * CGFloat(canvasZoom), height: 300 * CGFloat(canvasZoom))
                .shadow(color: isFocused ? .accentColor.opacity(0.5) : .black.opacity(0.2), radius: 20)
                .overlay(
                    Group {
                        if showPreviewCorners {
                            RoundedRectangle(cornerRadius: 300 * CGFloat(canvasZoom) * 0.225)
                                .stroke(Color.accentColor, lineWidth: isFocused ? 4 : 0)
                        } else {
                            Rectangle()
                                .stroke(Color.accentColor, lineWidth: isFocused ? 4 : 0)
                        }
                    }
                )
        } else {
            // 截图预览模式 (原有逻辑)
            EditorView(
                scene: scene,
                isFocused: isFocused,
                zoom: canvasZoom
            )
        }
    }
}
