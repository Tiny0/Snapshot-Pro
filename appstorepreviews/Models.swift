import Foundation
import SwiftUI
import SwiftData

enum ProjectType: String, Codable {
    case screenshot = "Screenshot"
    case icon = "Icon"
}

enum IconSpec: String, Codable, CaseIterable {
    case macOS = "macOS Icon Set"
    case iOS = "iOS App Store Icon"
    case other = "Other (Android / Web / etc.)"
}

enum DeviceFrameStyle: String, Codable, CaseIterable {
    case none = "Raw (Square)"
    case rounded = "Only Rounded"
    case minimal = "Minimal Border"
    case macos = "macOS (Window)"
    case ipad_pro = "iPad Pro (Realistic)"
    case iphone17 = "iPhone (Realistic)"
}

enum TextAlignmentType: String, Codable, CaseIterable {
    case left = "Left"
    case center = "Center"
    case right = "Right"

    var swiftUIAlignment: TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

@Model
final class DevicePreset {
    var id: UUID = UUID()
    var name: String = ""
    var width: Double = 0.0
    var height: Double = 0.0
    var cornerRadius: Double = 0.0

    init(name: String, width: Double, height: Double, cornerRadius: Double = 40) {
        self.id = UUID()
        self.name = name
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    static func seed(context: ModelContext) {
        let defaults = [
            DevicePreset(name: "iPhone 6.7\" (Portrait)", width: 1290, height: 2796),
            DevicePreset(name: "iPhone 6.7\" (Landscape)", width: 2796, height: 1290),
            DevicePreset(name: "iPhone 5.5\" (Portrait)", width: 1242, height: 2208),
            DevicePreset(name: "iPad Pro 12.9\"", width: 2048, height: 2732),
            DevicePreset(name: "MacBook Pro", width: 3456, height: 2234, cornerRadius: 15)
        ]
        for preset in defaults {
            context.insert(preset)
        }
    }
}

@Model
final class ImageLayer {
    var id: UUID = UUID()
    var name: String = ""
    var orderIndex: Int = 0
    @Attribute(.externalStorage)
    var imageData: Data?

    var imageScale: Double = 1.0
    var offsetX: Double = 0.0
    var offsetY: Double = 0.0
    var showShadow: Bool = true
    var bezelColor: String = "#FFFFFF"

    var showDeviceFrame: Bool = false
    var deviceFrameStyleRaw: String = DeviceFrameStyle.iphone17.rawValue
    var deviceFrameStyle: DeviceFrameStyle {
        get { DeviceFrameStyle(rawValue: deviceFrameStyleRaw) ?? .iphone17 }
        set { deviceFrameStyleRaw = newValue.rawValue }
    }

    var scene: SnapshotScene?

    init() {
        self.id = UUID()
        self.name = "New Layer"
    }
}

@Model
final class TextLayer {
    var id: UUID = UUID()
    var name: String = "New Text"
    var orderIndex: Int = 0
    var title: String = "Your App Title"
    var subtitle: String = "Short description goes here"

    var titleColor: String = "#FFFFFF"
    var subtitleColor: String = "#FFFFFF"

    var textAlignmentRaw: String = TextAlignmentType.center.rawValue
    var textAlignment: TextAlignmentType {
        get { TextAlignmentType(rawValue: textAlignmentRaw) ?? .center }
        set { textAlignmentRaw = newValue.rawValue }
    }

    var textScale: Double = 1.0
    var textOffsetX: Double = 0.0
    var textOffsetY: Double = 0.0

    var fontDesignRaw: String = "rounded"
    var fontDesign: Font.Design {
        switch fontDesignRaw {
        case "default": return .default
        case "monospaced": return .monospaced
        case "serif": return .serif
        default: return .rounded
        }
    }

    var isTextIndependent: Bool = false
    var perScreenTitles: [String] = []
    var perScreenSubtitles: [String] = []

    var scene: SnapshotScene?

    init() {
        self.id = UUID()
    }
}

@Model
final class SceneGroup {
    var id: UUID = UUID()
    var name: String = ""
    @Relationship(deleteRule: .cascade, inverse: \SnapshotScene.group)
    var scenes: [SnapshotScene] = []
    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}

@Model
final class SnapshotScene {
    var id: UUID = UUID()
    var name: String = ""

    var projectTypeRaw: String = ProjectType.screenshot.rawValue
    var projectType: ProjectType {
        get { ProjectType(rawValue: projectTypeRaw) ?? .screenshot }
        set { projectTypeRaw = newValue.rawValue }
    }

    // --- 基础画布属性 ---
    var canvasName: String = "iPhone 6.7\" (Portrait)"
    var baseWidth: Double = 1290
    var baseHeight: Double = 2796
    var cornerRadius: Double = 40
    var screenCount: Int = 1
    var backgroundColor: String = "#3498db"

    // --- 智能配色调色盘 ---
    var extractedPalette: [String] = []

    // --- 图层数组 ---
    @Relationship(deleteRule: .cascade, inverse: \ImageLayer.scene)
    var imageLayers: [ImageLayer] = []

    @Relationship(deleteRule: .cascade, inverse: \TextLayer.scene)
    var textLayers: [TextLayer] = []

    // --- 图标项目属性 ---
    var drawingCode: String = ""
    var iconSpecRaw: String = IconSpec.iOS.rawValue
    var iconSpec: IconSpec {
        get { IconSpec(rawValue: iconSpecRaw) ?? .iOS }
        set { iconSpecRaw = newValue.rawValue }
    }
    var iconShowCorners: Bool = false

    var group: SceneGroup?

    init(name: String, type: ProjectType = .screenshot) {
        self.id = UUID()
        self.name = name
        self.projectTypeRaw = type.rawValue

        if type == .screenshot {
            // 默认添加一个图片层和一个文字层
            let img = ImageLayer()
            img.name = "Layer 1"
            img.orderIndex = 0
            let txt = TextLayer()
            txt.name = "Text 1"
            txt.orderIndex = 0
            self.imageLayers = [img]
            self.textLayers = [txt]
        }

        if type == .icon {
            self.iconShowCorners = false
            self.iconSpecRaw = IconSpec.iOS.rawValue
            self.drawingCode = "{\"background\": \"#3498db\", \"layers\": [{\"type\": \"symbol\", \"name\": \"sparkles\", \"color\": \"#FFFFFF\", \"scale\": 0.6}]}"
        }
    }
}
