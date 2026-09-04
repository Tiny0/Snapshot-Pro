import SwiftUI
import SwiftData

struct EditorView: View {
    var scene: SnapshotScene
    var isFocused: Bool
    var zoom: Double

    var body: some View {
        let visualBaseWidth: CGFloat = 400 * CGFloat(zoom)
        let previewScale = visualBaseWidth / CGFloat(scene.baseWidth)

        let totalWidth = CGFloat(scene.baseWidth * Double(scene.screenCount) * previewScale)
        let totalHeight = CGFloat(scene.baseHeight * previewScale)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Color(hex: scene.backgroundColor)

                // 辅助线层
                HStack(spacing: 0) {
                    ForEach(0..<scene.screenCount, id: \.self) { _ in
                        Rectangle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            .frame(width: visualBaseWidth)
                    }
                }
                .zIndex(100)
                .allowsHitTesting(false)

                // 渲染图片图层 (按 orderIndex 从大到小排列绘制，确保 orderIndex 较小的在最上面)
                let sortedImages = scene.imageLayers.sorted(by: { $0.orderIndex > $1.orderIndex })
                ForEach(sortedImages) { layer in
                    ImageLayerView(scene: scene, layer: layer, pScale: previewScale)
                        .zIndex(10 + Double(scene.imageLayers.count - layer.orderIndex))
                }

                // 渲染文本图层
                let sortedTexts = scene.textLayers.sorted(by: { $0.orderIndex > $1.orderIndex })
                ForEach(sortedTexts) { layer in
                    TextLayerView(scene: scene, layer: layer, pScale: previewScale)
                        .zIndex(50 + Double(scene.textLayers.count - layer.orderIndex))
                        .allowsHitTesting(false) // 穿透交互
                }
            }
            .frame(width: totalWidth, height: totalHeight)
            .cornerRadius(12 * CGFloat(zoom))
            .clipped()
            .shadow(color: isFocused ? .accentColor.opacity(0.5) : .black.opacity(0.2), radius: 20 * CGFloat(zoom))
            .overlay(
                RoundedRectangle(cornerRadius: 12 * CGFloat(zoom))
                    .stroke(Color.accentColor, lineWidth: isFocused ? 4 * CGFloat(zoom) : 0)
            )

            Text("\(scene.name) (\(scene.screenCount) Screens)")
                .font(.system(size: 11 * CGFloat(zoom), weight: .bold))
                .foregroundColor(isFocused ? .accentColor : .secondary)
                .padding(.top, 12 * CGFloat(zoom))
                .lineLimit(1)
        }
    }
}

// MARK: - 图片图层组件
struct ImageLayerView: View {
    var scene: SnapshotScene
    @Bindable var layer: ImageLayer
    var pScale: Double

    var body: some View {
        ZStack {
            if let data = layer.imageData, let nsImage = NSImage(data: data) {
                let imgSize = nsImage.size
                let containerWidth = CGFloat(scene.baseWidth) * pScale
                let containerHeight = CGFloat(scene.baseHeight) * pScale
                let fitScale = min(containerWidth / imgSize.width, containerHeight / imgSize.height)

                let visualWidth = imgSize.width * fitScale
                let visualHeight = imgSize.height * fitScale
                let visualShortSide = min(visualWidth, visualHeight)

                let bezelWidth: CGFloat = {
                    if !layer.showDeviceFrame { return 0 }
                    switch layer.deviceFrameStyle {
                    case .iphone17: return visualShortSide * 0.025
                    case .ipad_pro: return visualShortSide * 0.045
                    case .minimal: return visualShortSide * 0.03
                    default: return 0 // .rounded, .macos, .none 无需内缩边框
                    }
                }()

                let padding: EdgeInsets = {
                    if !layer.showDeviceFrame { return EdgeInsets() }
                    switch layer.deviceFrameStyle {
                    case .minimal, .iphone17, .ipad_pro:
                        return EdgeInsets(top: bezelWidth, leading: bezelWidth, bottom: bezelWidth, trailing: bezelWidth)
                    case .macos:
                        return EdgeInsets(top: visualHeight * 0.06, leading: 0, bottom: 0, trailing: 0)
                    default: return EdgeInsets()
                    }
                }()

                let radiusPercent: CGFloat = {
                    switch layer.deviceFrameStyle {
                    case .iphone17: return 0.13
                    case .macos: return 0.025
                    case .ipad_pro: return 0.05
                    case .minimal, .rounded: return 0.08
                    case .none: return 0
                    }
                }()
                let outerCornerRadius = visualShortSide * radiusPercent
                let innerCornerRadius = max(0, outerCornerRadius - bezelWidth)

                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: innerCornerRadius))
                    .padding(padding)
                    .overlay(
                        Group {
                            if layer.showDeviceFrame {
                                DeviceFrameShape(
                                    style: layer.deviceFrameStyle,
                                    outerCornerRadius: outerCornerRadius,
                                    bezelWidth: bezelWidth,
                                    visualShortSide: visualShortSide,
                                    visualHeight: visualHeight,
                                    titleColor: Color(hex: layer.bezelColor)
                                )
                            }
                        }
                    )
            } else {
                // 空状态占位符
                RoundedRectangle(cornerRadius: 30 * pScale)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30 * pScale)
                            .stroke(style: StrokeStyle(lineWidth: max(3, 10 * pScale), dash: [15 * pScale, 10 * pScale]))
                            .foregroundColor(.white.opacity(0.5))
                    )
                    .frame(width: CGFloat(scene.baseWidth * 0.7 * pScale), height: CGFloat(scene.baseHeight * 0.7 * pScale))
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 60 * pScale))
                            Text("Drop Screenshot Here")
                                .font(.system(size: 18 * pScale, weight: .bold))
                            Text("Layer \(scene.imageLayers.firstIndex(where: { $0.id == layer.id }).map { $0 + 1 } ?? 1)")
                                .font(.system(size: 14 * pScale))
                                .padding(.top, 4 * pScale)
                        }
                        .foregroundColor(.white.opacity(0.8))
                    )
            }
        }
        .scaleEffect(layer.imageScale)
        .offset(x: CGFloat(layer.offsetX * pScale), y: CGFloat(layer.offsetY * pScale))
        .shadow(color: .black.opacity(layer.showShadow ? 0.3 : 0), radius: 30 * pScale, x: 0, y: 10 * pScale)
        .dropDestination(for: Data.self) { items, _ in
            if let firstData = items.first {
                layer.imageData = firstData
                return true
            }
            return false
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 文本图层组件
struct TextLayerView: View {
    var scene: SnapshotScene
    var layer: TextLayer
    var pScale: Double

    var body: some View {
        let baseTitleSize = scene.baseHeight * 0.05
        let baseSubtitleSize = scene.baseHeight * 0.025
        let basePadding = scene.baseHeight * 0.06
        let baseSpacing = scene.baseHeight * 0.01
        let visualBaseWidth = CGFloat(scene.baseWidth * pScale)

        Group {
            if layer.isTextIndependent {
                HStack(spacing: 0) {
                    ForEach(0..<scene.screenCount, id: \.self) { i in
                        VStack(alignment: layer.textAlignment.horizontalAlignment, spacing: CGFloat(baseSpacing * pScale)) {
                            Text(i < layer.perScreenTitles.count ? layer.perScreenTitles[i] : layer.title)
                                .font(.system(size: CGFloat(baseTitleSize * pScale), weight: .bold, design: layer.fontDesign))
                                .foregroundColor(Color(hex: layer.titleColor))
                            Text(i < layer.perScreenSubtitles.count ? layer.perScreenSubtitles[i] : layer.subtitle)
                                .font(.system(size: CGFloat(baseSubtitleSize * pScale), weight: .medium, design: layer.fontDesign))
                                .foregroundColor(Color(hex: layer.subtitleColor).opacity(0.8))
                                .lineSpacing(5 * CGFloat(pScale))
                        }
                        .frame(width: visualBaseWidth)
                    }
                }
            } else {
                VStack(alignment: layer.textAlignment.horizontalAlignment, spacing: CGFloat(baseSpacing * pScale)) {
                    Text(layer.title)
                        .font(.system(size: CGFloat(baseTitleSize * pScale), weight: .bold, design: layer.fontDesign))
                        .foregroundColor(Color(hex: layer.titleColor))
                    Text(layer.subtitle)
                        .font(.system(size: CGFloat(baseSubtitleSize * pScale), weight: .medium, design: layer.fontDesign))
                        .foregroundColor(Color(hex: layer.subtitleColor).opacity(0.8))
                        .lineSpacing(5 * CGFloat(pScale))
                }
                .padding(.horizontal, 40 * CGFloat(pScale))
            }
        }
        .multilineTextAlignment(layer.textAlignment.swiftUIAlignment)
        .padding(.top, CGFloat(basePadding * pScale))
        .scaleEffect(layer.textScale)
        .offset(x: CGFloat(layer.textOffsetX * pScale), y: CGFloat(layer.textOffsetY * pScale))
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// --- 自动设备外壳组件 ---
struct DeviceFrameShape: View {
    let style: DeviceFrameStyle
    let outerCornerRadius: CGFloat
    let bezelWidth: CGFloat
    let visualShortSide: CGFloat
    let visualHeight: CGFloat
    let titleColor: Color

    var body: some View {
        let shouldShowIsland = style == .iphone17
        let shouldShowTrafficLights = style == .macos

        GeometryReader { geo in
            ZStack {
                if style == .iphone17 {
                    let metalWidth = bezelWidth * 0.4
                    let blackBezelWidth = bezelWidth * 0.6
                    ZStack {
                        let colors: [Color] = [
                            Color(white: 0.35), Color(white: 0.6), Color(white: 0.8), Color(white: 0.45), Color(white: 0.15)
                        ]
                        let segW = metalWidth / 5
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: outerCornerRadius)
                                .inset(by: segW * CGFloat(i))
                                .strokeBorder(colors[i], lineWidth: segW)
                        }
                        RoundedRectangle(cornerRadius: outerCornerRadius)
                            .inset(by: metalWidth)
                            .strokeBorder(Color(white: 0.05), lineWidth: blackBezelWidth)
                    }
                    .overlay(iphoneButtons(size: geo.size, bezel: bezelWidth, isIPhone17: true))

                } else if style == .ipad_pro {
                    let metalWidth = bezelWidth * 0.075
                    let blackBezelWidth = bezelWidth * 0.925
                    ZStack {
                        RoundedRectangle(cornerRadius: outerCornerRadius).strokeBorder(Color(white: 0.8), lineWidth: metalWidth)
                        RoundedRectangle(cornerRadius: outerCornerRadius).inset(by: metalWidth).strokeBorder(Color(white: 0.05), lineWidth: blackBezelWidth)
                        Circle().fill(Color(white: 0.15)).frame(width: bezelWidth * 0.15).padding(.top, bezelWidth * 0.4).frame(maxHeight: .infinity, alignment: .top)
                    }
                    .overlay(ipadButtons(size: geo.size, bezel: bezelWidth))

                } else if style == .minimal {
                    RoundedRectangle(cornerRadius: outerCornerRadius)
                        .inset(by: bezelWidth / 2)
                        .stroke(titleColor.opacity(0.8), lineWidth: bezelWidth)
                }

                if shouldShowIsland {
                    let islandWidth = geo.size.width * 0.26
                    let islandHeight = visualHeight * 0.03
                    let topOffset = bezelWidth * 1.1
                    Capsule().fill(Color.black).frame(width: islandWidth, height: islandHeight).padding(.top, topOffset).frame(maxHeight: .infinity, alignment: .top)
                } else if shouldShowTrafficLights {
                    let barHeight = visualHeight * 0.06
                    VStack(spacing: 0) {
                        HStack(spacing: barHeight * 0.2) {
                            let dotSize = barHeight * 0.3
                            Circle().fill(Color.red).frame(width: dotSize)
                            Circle().fill(Color.yellow).frame(width: dotSize)
                            Circle().fill(Color.green).frame(width: dotSize)
                            Spacer()
                        }
                        .padding(.horizontal, barHeight * 0.4).frame(height: barHeight).background(Color(nsColor: .windowBackgroundColor)).clipShape(UnevenRoundedRectangle(topLeadingRadius: outerCornerRadius, topTrailingRadius: outerCornerRadius))
                        Divider(); Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func iphoneButtons(size: CGSize, bezel: CGFloat, isIPhone17: Bool = false) -> some View {
        let btnWidth = bezel * (isIPhone17 ? 0.15 : 0.4)
        let buttonColors: [Color] = isIPhone17 ? [
            Color(white: 0.35), Color(white: 0.6), Color(white: 0.8), Color(white: 0.45), Color(white: 0.15)
        ] : [Color(white: 0.88), Color(white: 0.88), Color(white: 0.88), Color(white: 0.88), Color(white: 0.88)]
        ZStack {
            VStack(spacing: size.height * 0.04) {
                buttonShape(w: btnWidth, h: isIPhone17 ? size.height * 0.04 : size.height * 0.03, colors: buttonColors, isLeft: true)
                buttonShape(w: btnWidth, h: size.height * 0.06, colors: buttonColors, isLeft: true)
                buttonShape(w: btnWidth, h: size.height * 0.06, colors: buttonColors, isLeft: true)
                Spacer()
            }
            .padding(.top, size.height * 0.15).frame(maxWidth: .infinity, alignment: .leading).offset(x: -btnWidth)
            VStack {
                buttonShape(w: btnWidth, h: size.height * 0.09, colors: buttonColors, isLeft: false)
                Spacer()
            }
            .padding(.top, size.height * 0.22).frame(maxWidth: .infinity, alignment: .trailing).offset(x: btnWidth)
        }
    }

    @ViewBuilder
    private func buttonShape(w: CGFloat, h: CGFloat, colors: [Color], isLeft: Bool) -> some View {
        let seg = w / 5
        HStack(spacing: 0) {
            let sortedColors = isLeft ? colors : colors.reversed()
            ForEach(0..<5, id: \.self) { i in
                Rectangle().fill(sortedColors[i]).frame(width: seg, height: h)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    @ViewBuilder
    private func ipadButtons(size: CGSize, bezel: CGFloat) -> some View {
        let btnW = bezel * 0.1
        ZStack {
            VStack(spacing: size.height * 0.02) {
                RoundedRectangle(cornerRadius: 1).fill(Color(white: 0.75)).frame(width: btnW, height: size.height * 0.04)
                RoundedRectangle(cornerRadius: 1).fill(Color(white: 0.75)).frame(width: btnW, height: size.height * 0.04)
                Spacer()
            }
            .padding(.top, size.height * 0.1).frame(maxWidth: .infinity, alignment: .trailing).offset(x: btnW)
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 1).fill(Color(white: 0.75)).frame(width: size.width * 0.08, height: btnW)
            }
            .padding(.trailing, size.width * 0.15).frame(maxHeight: .infinity, alignment: .top).offset(y: -btnW)
        }
    }
}
