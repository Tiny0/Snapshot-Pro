import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SceneGroup.name) private var groups: [SceneGroup]
    @Query(filter: #Predicate<SnapshotScene> { $0.group == nil }, sort: \SnapshotScene.name) private var ungroupedScenes: [SnapshotScene]

    @Binding var selection: Set<UUID>

    var body: some View {
        List(selection: $selection) {
            // 1. 未分组场景
            Section("All Projects") {
                ForEach(ungroupedScenes) { scene in
                    NavigationLink(value: scene.id) {
                        SceneRow(scene: scene)
                    }
                }
            }

            // 2. 自定义分组
            ForEach(groups) { group in
                DisclosureGroup {
                    ForEach(group.scenes.sorted(by: { $0.name < $1.name })) { scene in
                        NavigationLink(value: scene.id) {
                            SceneRow(scene: scene)
                        }
                    }
                } label: {
                    EditableGroupHeader(group: group, modelContext: modelContext)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                Button(action: { addScene(type: .screenshot) }) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .help("New Screenshot Project")
                .buttonStyle(.plain)

                Button(action: { addScene(type: .icon) }) {
                    Image(systemName: "app.badge.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                }
                .help("New Icon Project")
                .buttonStyle(.plain)

                Spacer()

                Button(action: addGroup) {
                    Image(systemName: "folder.badge.plus")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .help("New Group")
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(.ultraThinMaterial)
    }

    private func addGroup() {
        let newGroup = SceneGroup(name: "New Group")
        modelContext.insert(newGroup)
    }

    private func addScene(type: ProjectType) {
        let name = type == .screenshot ? "New Scene" : "New Icon"
        let newScene = SnapshotScene(name: name, type: type)
        modelContext.insert(newScene)
        selection = [newScene.id]
    }
}

// 分组标题组件
struct EditableGroupHeader: View {
    @Bindable var group: SceneGroup
    let modelContext: ModelContext
    @State private var isRenaming = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            if isRenaming {
                TextField("", text: $group.name)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { isRenaming = false }
            } else {
                Text(group.name)
                    .font(.headline.weight(.medium))
            }

            Spacer()

            Button(action: {
                let newScene = SnapshotScene(name: "New Scene")
                newScene.group = group
                modelContext.insert(newScene)
            }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Rename Group") {
                isRenaming = true
                isFocused = true
            }

            Button("Duplicate Group") {
                duplicateGroup(group)
            }

            Divider()

            Button("Delete Group", role: .destructive) {
                modelContext.delete(group)
            }
        }
    }

    private func duplicateGroup(_ original: SceneGroup) {
        // 1. 创建新分组
        let newGroup = SceneGroup(name: "\(original.name) Copy")
        modelContext.insert(newGroup)

        // 2. 复制原分组内的所有场景
        for scene in original.scenes {
            let newScene = SnapshotScene(name: scene.name, type: scene.projectType)
            // 复制属性
            newScene.canvasName = scene.canvasName
            newScene.baseWidth = scene.baseWidth
            newScene.baseHeight = scene.baseHeight
            newScene.cornerRadius = scene.cornerRadius
            newScene.screenCount = scene.screenCount
            newScene.backgroundColor = scene.backgroundColor

            // 复制图标属性
            newScene.iconSpec = scene.iconSpec
            newScene.iconShowCorners = scene.iconShowCorners
            newScene.drawingCode = scene.drawingCode

            // 清空初始化时自动创建的默认层
            newScene.imageLayers = []
            newScene.textLayers = []

            // 深度复制图片层
            for layer in scene.imageLayers {
                let newLayer = ImageLayer()
                newLayer.name = layer.name
                newLayer.imageData = layer.imageData
                newLayer.imageScale = layer.imageScale
                newLayer.offsetX = layer.offsetX
                newLayer.offsetY = layer.offsetY
                newLayer.showShadow = layer.showShadow
                newLayer.bezelColor = layer.bezelColor
                newLayer.showDeviceFrame = layer.showDeviceFrame
                newLayer.deviceFrameStyle = layer.deviceFrameStyle
                newScene.imageLayers.append(newLayer)
            }

            // 深度复制文本层
            for layer in scene.textLayers {
                let newLayer = TextLayer()
                newLayer.name = layer.name
                newLayer.title = layer.title
                newLayer.subtitle = layer.subtitle
                newLayer.titleColor = layer.titleColor
                newLayer.subtitleColor = layer.subtitleColor
                newLayer.textAlignment = layer.textAlignment
                newLayer.textScale = layer.textScale
                newLayer.textOffsetX = layer.textOffsetX
                newLayer.textOffsetY = layer.textOffsetY
                newLayer.fontDesignRaw = layer.fontDesignRaw
                newLayer.isTextIndependent = layer.isTextIndependent
                newLayer.perScreenTitles = layer.perScreenTitles
                newLayer.perScreenSubtitles = layer.perScreenSubtitles
                newScene.textLayers.append(newLayer)
            }

            // 关联新分组
            newScene.group = newGroup
            modelContext.insert(newScene)
        }
    }
}

// 场景行组件
struct SceneRow: View {
    let scene: SnapshotScene
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SceneGroup.name) private var allGroups: [SceneGroup]
    @State private var isRenaming = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            if isRenaming {
                @Bindable var bindableScene = scene
                TextField("", text: $bindableScene.name)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { isRenaming = false }
            } else {
                // 根据项目类型显示不同的图标和颜色
                Label {
                    Text(scene.name)
                } icon: {
                    Image(systemName: scene.projectType == .icon ? "app.badge.fill" : "photo")
                        .foregroundColor(scene.projectType == .icon ? .orange : .blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename Scene") {
                isRenaming = true
                isFocused = true
            }

            Menu("Move to Group") {
                Button("None (Ungrouped)") { scene.group = nil }
                Divider()
                ForEach(allGroups) { group in
                    Button(group.name) { scene.group = group }
                }
            }

            Divider()

            Button("Duplicate") { duplicateScene(scene) }
            Button("Delete", role: .destructive) { modelContext.delete(scene) }
        }
    }

    private func duplicateScene(_ original: SnapshotScene) {
        let newScene = SnapshotScene(name: "\(original.name) Copy", type: original.projectType)
        newScene.canvasName = original.canvasName
        newScene.baseWidth = original.baseWidth
        newScene.baseHeight = original.baseHeight
        newScene.cornerRadius = original.cornerRadius
        newScene.screenCount = original.screenCount
        newScene.backgroundColor = original.backgroundColor

        // 复制图标属性
        newScene.iconSpec = original.iconSpec
        newScene.iconShowCorners = original.iconShowCorners
        newScene.drawingCode = original.drawingCode

        // 清空初始化时自动创建的默认层
        newScene.imageLayers = []
        newScene.textLayers = []

        // 深度复制图片层
        for layer in original.imageLayers {
            let newLayer = ImageLayer()
            newLayer.name = layer.name
            newLayer.imageData = layer.imageData
            newLayer.imageScale = layer.imageScale
            newLayer.offsetX = layer.offsetX
            newLayer.offsetY = layer.offsetY
            newLayer.showShadow = layer.showShadow
            newLayer.bezelColor = layer.bezelColor
            newLayer.showDeviceFrame = layer.showDeviceFrame
            newLayer.deviceFrameStyle = layer.deviceFrameStyle
            newScene.imageLayers.append(newLayer)
        }

        // 深度复制文本层
        for layer in original.textLayers {
            let newLayer = TextLayer()
            newLayer.name = layer.name
            newLayer.title = layer.title
            newLayer.subtitle = layer.subtitle
            newLayer.titleColor = layer.titleColor
            newLayer.subtitleColor = layer.subtitleColor
            newLayer.textAlignment = layer.textAlignment
            newLayer.textScale = layer.textScale
            newLayer.textOffsetX = layer.textOffsetX
            newLayer.textOffsetY = layer.textOffsetY
            newLayer.fontDesignRaw = layer.fontDesignRaw
            newLayer.isTextIndependent = layer.isTextIndependent
            newLayer.perScreenTitles = layer.perScreenTitles
            newLayer.perScreenSubtitles = layer.perScreenSubtitles
            newScene.textLayers.append(newLayer)
        }

        newScene.group = original.group
        modelContext.insert(newScene)
    }
}
