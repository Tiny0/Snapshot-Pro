import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct InspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var scene: SnapshotScene
    @Query(sort: \DevicePreset.name) private var presets: [DevicePreset]

    @State private var newPresetName: String = ""
    @State private var isShowingSaveAlert = false

    // 折叠状态控制
    @State private var isCanvasExpanded = true
    @State private var isIconSpecExpanded = true
    @State private var isDrawingCodeExpanded = true

    // 图层折叠状态 (使用 ID 跟踪)
    @State private var expandedImageLayers: Set<UUID> = []
    @State private var expandedTextLayers: Set<UUID> = []

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $scene.name)
                if scene.projectType == .screenshot {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ColorPicker("Background", selection: Binding(
                                get: { Color(hex: scene.backgroundColor) },
                                set: { newValue in
                                    scene.backgroundColor = newValue.toHex() ?? "#000000"
                                    applyRecommendedStyleToAll()
                                }
                            ))

                            Button(action: applySmartImageColor) {
                                Image(systemName: "wand.and.stars")
                            }
                            .buttonStyle(.plain)
                            .help("Extract & Apply Smart Color from First Image")

                            if scene.group != nil {
                                Button(action: syncStyleToGroup) {
                                    Image(systemName: "uiwindow.split.2x1")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                                .help("Sync this style to all scenes in group")
                            }
                        }
                    }

                    if !scene.extractedPalette.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(scene.extractedPalette, id: \.self) { hex in
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 20, height: 20)
                                        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                                        .onTapGesture {
                                            withAnimation {
                                                scene.backgroundColor = hex
                                                applyRecommendedStyleToAll()
                                            }
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if scene.projectType == .screenshot {
                canvasSection
                imageLayersSection
                textLayersSection
            } else {
                iconSections
            }
        }
        .formStyle(.grouped)
        .alert("Save Preset", isPresented: $isShowingSaveAlert) {
            TextField("Preset Name", text: $newPresetName)
            Button("Save") { saveAsNewPreset() }
            Button("Cancel", role: .cancel) { newPresetName = "" }
        } message: {
            Text("Enter a name for this custom canvas size.")
        }
        .onAppear {
            // 初始化时展开第一个图层
            if let firstImg = scene.imageLayers.first?.id { expandedImageLayers.insert(firstImg) }
            if let firstTxt = scene.textLayers.first?.id { expandedTextLayers.insert(firstTxt) }
        }
    }

    // MARK: - 画布设置
    @ViewBuilder
    private var canvasSection: some View {
        Section {
            DisclosureGroup("Canvas Size & Presets", isExpanded: $isCanvasExpanded) {
                VStack(spacing: 12) {
                    Picker("Presets", selection: Binding(
                        get: { scene.canvasName },
                        set: { newName in
                            scene.canvasName = newName
                            if let preset = presets.first(where: { $0.name == newName }) {
                                scene.baseWidth = preset.width
                                scene.baseHeight = preset.height
                                scene.cornerRadius = preset.cornerRadius
                            }
                        }
                    )) {
                        if !presets.contains(where: { $0.name == scene.canvasName }) {
                            Text(scene.canvasName).tag(scene.canvasName)
                        }
                        Divider()
                        ForEach(presets) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("", value: $scene.baseWidth, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                            .onChange(of: scene.baseWidth) { markAsModified() }
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("", value: $scene.baseHeight, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                            .onChange(of: scene.baseHeight) { markAsModified() }
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            newPresetName = "Custom \(Int(scene.baseWidth))x\(Int(scene.baseHeight))"
                            isShowingSaveAlert = true
                        }) {
                            Label("Save New", systemImage: "plus.square.on.square")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)

                        if let currentPreset = presets.first(where: { $0.name == scene.canvasName }),
                           !isSystemPreset(currentPreset.name) {
                            Spacer()
                            Button(role: .destructive) { deletePreset(currentPreset) } label: {
                                Image(systemName: "trash").foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)

                    Stepper("Screen Count: \(scene.screenCount)", value: $scene.screenCount, in: 1...10)
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 截图图层管理
    @ViewBuilder
    private var imageLayersSection: some View {
        Section(header: HStack {
            Text("Screenshot Controls")
            Spacer()
            if scene.imageLayers.count < 3 {
                Button(action: addImageLayer) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }) {
            let sortedImageLayers = scene.imageLayers.sorted(by: { $0.orderIndex < $1.orderIndex })
            ForEach(Array(sortedImageLayers.enumerated()), id: \.element.id) { index, layer in
                @Bindable var layer = layer
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedImageLayers.contains(layer.id) },
                    set: { isExpanded in
                        if isExpanded { expandedImageLayers.insert(layer.id) }
                        else { expandedImageLayers.remove(layer.id) }
                    }
                )) {
                    ImageLayerInspector(scene: scene, layer: layer)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.stack").font(.caption).foregroundColor(.accentColor)
                        TextField("", text: $layer.name)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.leading)

                        if layer.imageData != nil {
                            Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundColor(.green)
                        }

                        Spacer()

                        // 排序按钮
                        HStack(spacing: 8) {
                            Button(action: { moveImageLayer(from: index, to: index - 1) }) {
                                Image(systemName: "chevron.up")
                            }.disabled(index == 0)

                            Button(action: { moveImageLayer(from: index, to: index + 1) }) {
                                Image(systemName: "chevron.down")
                            }.disabled(index == scene.imageLayers.count - 1)

                            Button(role: .destructive, action: { deleteImageLayer(layer) }) {
                                Image(systemName: "trash")
                            }.disabled(scene.imageLayers.count <= 1)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 文本图层管理
    @ViewBuilder
    private var textLayersSection: some View {
        Section(header: HStack {
            Text("Text Controls")
            Spacer()
            if scene.textLayers.count < 3 {
                Button(action: addTextLayer) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }) {
            let sortedTextLayers = scene.textLayers.sorted(by: { $0.orderIndex < $1.orderIndex })
            ForEach(Array(sortedTextLayers.enumerated()), id: \.element.id) { index, layer in
                @Bindable var layer = layer
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedTextLayers.contains(layer.id) },
                    set: { isExpanded in
                        if isExpanded { expandedTextLayers.insert(layer.id) }
                        else { expandedTextLayers.remove(layer.id) }
                    }
                )) {
                    TextLayerInspector(scene: scene, layer: layer)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.quote").font(.caption).foregroundColor(.accentColor)
                        TextField("", text: $layer.name)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.leading)

                        Spacer()
                        HStack(spacing: 8) {
                            Button(action: { moveTextLayer(from: index, to: index - 1) }) {
                                Image(systemName: "chevron.up")
                            }.disabled(index == 0)

                            Button(action: { moveTextLayer(from: index, to: index + 1) }) {
                                Image(systemName: "chevron.down")
                            }.disabled(index == scene.textLayers.count - 1)

                            Button(role: .destructive, action: { deleteTextLayer(layer) }) {
                                Image(systemName: "trash")
                            }.disabled(scene.textLayers.count <= 1)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 图标设置 (保持原有逻辑)
    @ViewBuilder
    private var iconSections: some View {
        Section {
            DisclosureGroup("App Icon Spec", isExpanded: $isIconSpecExpanded) {
                VStack(spacing: 12) {
                    Picker("Target Platform", selection: $scene.iconSpec) {
                        ForEach(IconSpec.allCases, id: \.self) { spec in
                            Text(spec.rawValue).tag(spec)
                        }
                    }
                    if scene.iconSpec == .other {
                        Toggle("Apply Rounded Corners", isOn: $scene.iconShowCorners)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        Section {
            Button(action: copyAIPrompt) {
                Label("Copy AI Designer Prompt", systemImage: "doc.on.doc.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } header: { Text("AI Designer") }
        Section {
            DisclosureGroup("Drawing Code (JSON)", isExpanded: $isDrawingCodeExpanded) {
                VStack(spacing: 12) {
                    TextEditor(text: $scene.drawingCode)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    Button("Reset to Template") {
                        scene.drawingCode = "{\"background\": \"#1A1A1A\", \"layers\": [{\"type\": \"shape\", \"form\": \"rect\", \"color\": \"#007AFF\", \"scale\": 0.6}]}"
                    }.buttonStyle(.borderless)
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 辅助方法
    private func addImageLayer() {
        let newLayer = ImageLayer()
        newLayer.name = "Layer \(scene.imageLayers.count + 1)"
        newLayer.orderIndex = (scene.imageLayers.map { $0.orderIndex }.max() ?? -1) + 1
        scene.imageLayers.append(newLayer)
        expandedImageLayers.insert(newLayer.id)
    }

    private func deleteImageLayer(_ layer: ImageLayer) {
        if let idx = scene.imageLayers.firstIndex(where: { $0.id == layer.id }) {
            scene.imageLayers.remove(at: idx)
            modelContext.delete(layer)
        }
    }

    private func moveImageLayer(from: Int, to: Int) {
        withAnimation(.spring()) {
            var layers = scene.imageLayers.sorted(by: { $0.orderIndex < $1.orderIndex })
            let element = layers.remove(at: from)
            layers.insert(element, at: to)
            for (index, layer) in layers.enumerated() {
                layer.orderIndex = index
            }
            try? modelContext.save()
        }
    }

    private func addTextLayer() {
        let newLayer = TextLayer()
        newLayer.name = "Text \(scene.textLayers.count + 1)"
        newLayer.orderIndex = (scene.textLayers.map { $0.orderIndex }.max() ?? -1) + 1
        scene.textLayers.append(newLayer)
        expandedTextLayers.insert(newLayer.id)
    }

    private func deleteTextLayer(_ layer: TextLayer) {
        if let idx = scene.textLayers.firstIndex(where: { $0.id == layer.id }) {
            scene.textLayers.remove(at: idx)
            modelContext.delete(layer)
        }
    }

    private func moveTextLayer(from: Int, to: Int) {
        withAnimation(.spring()) {
            var layers = scene.textLayers.sorted(by: { $0.orderIndex < $1.orderIndex })
            let element = layers.remove(at: from)
            layers.insert(element, at: to)
            for (index, layer) in layers.enumerated() {
                layer.orderIndex = index
            }
            try? modelContext.save()
        }
    }

    private func saveAsNewPreset() {
        guard !newPresetName.isEmpty else { return }
        let newPreset = DevicePreset(name: newPresetName, width: scene.baseWidth, height: scene.baseHeight, cornerRadius: scene.cornerRadius)
        modelContext.insert(newPreset)
        scene.canvasName = newPresetName
        newPresetName = ""
    }

    private func markAsModified() {
        if let matchingPreset = presets.first(where: { $0.width == scene.baseWidth && $0.height == scene.baseHeight }) {
            if scene.canvasName != matchingPreset.name { scene.canvasName = matchingPreset.name }
        } else {
            if scene.canvasName != "Modified Size" { scene.canvasName = "Modified Size" }
        }
    }

    private func deletePreset(_ preset: DevicePreset) {
        modelContext.delete(preset)
        if let first = presets.first(where: { isSystemPreset($0.name) }) {
            scene.canvasName = first.name
            scene.baseWidth = first.width
            scene.baseHeight = first.height
        }
    }

    private func isSystemPreset(_ name: String) -> Bool {
        let systems = ["iPhone 6.7\"", "iPhone 5.5\"", "iPad Pro 12.9\"", "MacBook Pro"]
        return systems.contains { system in name.contains(system) }
    }

    private func copyAIPrompt() {
        let prompt = """
        Task: Design a modern, minimalist App Icon using a specific JSON format.

        JSON Schema:
        {
          "background": "#HEXCOLOR",
          "layers": [
            {
              "type": "symbol" | "shape",
              "name": "SF Symbol Name" (if type is symbol),
              "form": "circle" | "rect" | "triangle" (if type is shape),
              "color": "#HEXCOLOR",
              "scale": 0.1 to 1.0,
              "widthScale": optional number (default 1.0),
              "heightScale": optional number (default 1.0),
              "x": -1.0 to 1.0 (horizontal offset),
              "y": -1.0 to 1.0 (vertical offset),
              "opacity": 0.0 to 1.0,
              "rotation": degrees,
              "cornerRadius": 0.0 to 1.0 (for rect shape),
              "strokeWidth": optional number
            }
          ]
        }

        Design Tips for "Refraction/Prism" style:
        1. Use "triangle" for the prism core.
        2. Use very thin "rect" with rotation to create light beams.
        3. Overlap layers with different "opacity" (0.3-0.6) to create refraction effects.

        Requirements:
        1. Use vibrant, modern color palettes (e.g., Cyberpunk, Tech Minimal).
        2. Keep it simple and recognizable.
        3. Only output the raw JSON.

        Design a professional-looking icon for a: [USER_INPUT_DESCRIPTION]
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }

    private func applyRecommendedStyleToAll() {
        let bgColor = Color(hex: scene.backgroundColor)
        withAnimation(.easeInOut) {
            for layer in scene.textLayers {
                if bgColor.isLight() {
                    layer.titleColor = "#333333"
                    layer.subtitleColor = "#333333"
                } else {
                    layer.titleColor = "#FFFFFF"
                    layer.subtitleColor = "#FFFFFF"
                }
            }
        }
    }

    private func applySmartImageColor() {
        let sortedLayers = scene.imageLayers.sorted(by: { $0.orderIndex < $1.orderIndex })
        guard let firstLayer = sortedLayers.first,
              let data = firstLayer.imageData,
              let img = NSImage(data: data) else { return }
        let palette = img.extractPalette(count: 6)
        scene.extractedPalette = palette.map { Color(nsColor: $0).toHex() ?? "#FFFFFF" }
        if let firstNSColor = palette.first {
            let avgColor = Color(nsColor: firstNSColor)
            let smartBg = avgColor.adjustedForBackground(isDark: false)
            scene.backgroundColor = smartBg.toHex() ?? "#FFFFFF"
            applyRecommendedStyleToAll()
        }
    }

    private func syncStyleToGroup() {
        guard let group = scene.group else { return }
        withAnimation {
            for otherScene in group.scenes {
                if otherScene.id != scene.id {
                    otherScene.backgroundColor = scene.backgroundColor
                    // 同步所有文字图层的样式（假设结构一致）
                    for (i, layer) in scene.textLayers.enumerated() {
                        if i < otherScene.textLayers.count {
                            let otherLayer = otherScene.textLayers[i]
                            otherLayer.titleColor = layer.titleColor
                            otherLayer.subtitleColor = layer.subtitleColor
                            otherLayer.fontDesignRaw = layer.fontDesignRaw
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 图片图层检查器组件
struct ImageLayerInspector: View {
    @Bindable var scene: SnapshotScene
    @Bindable var layer: ImageLayer

    var body: some View {
        VStack(spacing: 12) {
            // 图片导入区域
            HStack {
                if let data = layer.imageData, let nsImg = NSImage(data: data) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "plus").foregroundColor(.secondary))
                }

                Button("Select Image") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    if panel.runModal() == .OK {
                        if let url = panel.url, let data = try? Data(contentsOf: url) {
                            layer.imageData = data
                        }
                    }
                }

                if layer.imageData != nil {
                    Button(role: .destructive) { layer.imageData = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain)
                }
            }

            ControlSlider(label: "Scale", value: $layer.imageScale, range: 0.1...5.0, resetValue: 1.0, isPercentage: true)
            ControlSlider(label: "X Offset", value: $layer.offsetX, range: -5000...5000, resetValue: 0)
            ControlSlider(label: "Y Offset", value: $layer.offsetY, range: -2000...2000, resetValue: 0)

            Toggle("Show Shadow", isOn: $layer.showShadow)
            Toggle("Show Device Frame", isOn: $layer.showDeviceFrame)

            if layer.showDeviceFrame {
                HStack {
                    Picker("Frame Style", selection: $layer.deviceFrameStyle) {
                        ForEach(DeviceFrameStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.menu)

                    if layer.deviceFrameStyle == .minimal {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: layer.bezelColor) },
                            set: { layer.bezelColor = $0.toHex() ?? "#FFFFFF" }
                        )).labelsHidden()
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .dropDestination(for: Data.self) { items, _ in
            if let firstData = items.first {
                layer.imageData = firstData
                return true
            }
            return false
        }
    }
}

// MARK: - 文本图层检查器组件
struct TextLayerInspector: View {
    @Bindable var scene: SnapshotScene
    @Bindable var layer: TextLayer

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Font", selection: $layer.fontDesignRaw) {
                    Text("Rounded").tag("rounded")
                    Text("Default").tag("default")
                    Text("Monospaced").tag("monospaced")
                    Text("Serif").tag("serif")
                }

                ColorPicker("", selection: Binding(
                    get: { Color(hex: layer.titleColor) },
                    set: { layer.titleColor = $0.toHex() ?? "#FFFFFF" }
                )).labelsHidden()
            }

            Toggle("Independent Text per Screen", isOn: $layer.isTextIndependent)
                .onChange(of: layer.isTextIndependent) { _, newValue in
                    if newValue { syncTextArrays() }
                }

            if layer.isTextIndependent {
                ForEach(0..<scene.screenCount, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screen \(index + 1)").font(.caption.bold()).foregroundColor(.accentColor)
                        TextField("Title", text: Binding(
                            get: { index < layer.perScreenTitles.count ? layer.perScreenTitles[index] : layer.title },
                            set: { newValue in
                                ensureArraySize(index)
                                layer.perScreenTitles[index] = newValue
                            }
                        ))
                        TextField("Subtitle", text: Binding(
                            get: { index < layer.perScreenSubtitles.count ? layer.perScreenSubtitles[index] : layer.subtitle },
                            set: { newValue in
                                ensureArraySize(index)
                                layer.perScreenSubtitles[index] = newValue
                            }
                        ))
                    }
                    .padding(.vertical, 4)
                    if index < scene.screenCount - 1 { Divider() }
                }
            } else {
                TextField("Title", text: $layer.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subtitle").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $layer.subtitle)
                        .font(.system(size: 13))
                        .frame(minHeight: 60)
                        .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
            }

            Picker("Alignment", selection: $layer.textAlignment) {
                ForEach(TextAlignmentType.allCases, id: \.self) { type in
                    Image(systemName: "text.align\(type.rawValue.lowercased())").tag(type)
                }
            }
            .pickerStyle(.segmented)

            ControlSlider(label: "Text Scale", value: $layer.textScale, range: 0.1...3.0, resetValue: 1.0, isPercentage: true)
            ControlSlider(label: "Text X Offset", value: $layer.textOffsetX, range: -2000...2000, resetValue: 0)
            ControlSlider(label: "Text Y Offset", value: $layer.textOffsetY, range: -1000...1000, resetValue: 0)
        }
        .padding(.vertical, 8)
        .onChange(of: scene.screenCount) { _, _ in
            if layer.isTextIndependent { syncTextArrays() }
        }
    }

    private func syncTextArrays() {
        while layer.perScreenTitles.count < scene.screenCount { layer.perScreenTitles.append(layer.title) }
        while layer.perScreenSubtitles.count < scene.screenCount { layer.perScreenSubtitles.append(layer.subtitle) }
    }

    private func ensureArraySize(_ index: Int) {
        if index >= layer.perScreenTitles.count { syncTextArrays() }
    }
}

struct ControlSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let resetValue: Double
    var isPercentage: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formattedLabel).font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(action: { withAnimation(.spring()) { value = resetValue } }) {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .foregroundColor(value == resetValue ? .secondary.opacity(0.5) : .accentColor)
                }
                .buttonStyle(.plain)
            }
            Slider(value: $value, in: range)
        }
    }

    private var formattedLabel: String {
        let displayValue = isPercentage ? "\(Int(value * 100))%" : "\(Int(value)) px"
        return "\(label): \(displayValue)"
    }
}
