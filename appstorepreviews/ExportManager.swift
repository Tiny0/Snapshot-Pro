import SwiftUI
import AppKit
import ImageIO

@MainActor
class ExportManager {
    static func exportAll(scene: SnapshotScene) {
        showExportSettings { includeAlpha in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.title = "Select Export Folder"
            panel.begin { response in
                if response == .OK, let folderURL = panel.url {
                    if scene.projectType == .icon {
                        switch scene.iconSpec {
                        case .macOS: self.exportMacOSIconSet(scene: scene, folder: folderURL, includeAlpha: includeAlpha)
                        case .iOS: self.exportiOSIcon(scene: scene, folder: folderURL, includeAlpha: includeAlpha)
                        case .other: self.exportCustomIcon(scene: scene, folder: folderURL, includeAlpha: includeAlpha)
                        }
                    } else {
                        self.renderAndExportSlices(scene: scene, folder: folderURL, includeAlpha: includeAlpha)
                    }
                }
            }
        }
    }

    private static func showExportSettings(completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Export Settings"
        alert.informativeText = "Do you want to include the Alpha channel (transparency)?\nNote: App Store iOS icons must NOT have an Alpha channel."
        let checkbox = NSButton(checkboxWithTitle: "Include Alpha Channel", target: nil, action: nil)
        checkbox.state = .on
        alert.accessoryView = checkbox
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn { completion(checkbox.state == .on) }
    }

    private static func exportiOSIcon(scene: SnapshotScene, folder: URL, includeAlpha: Bool) {
        let iconView = IconCanvasView(code: scene.drawingCode, ismacOS: false, showCorners: scene.iconShowCorners).frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: iconView)
        if let image = renderer.nsImage { saveImage(image, name: "\(scene.name)_iOS_AppStore_1024.png", folder: folder, includeAlpha: includeAlpha) }
        showCompletionAlert(folder: folder)
    }

    private static func exportMacOSIconSet(scene: SnapshotScene, folder: URL, includeAlpha: Bool) {
        let sizes: [(String, CGFloat)] = [("1024", 1024), ("512", 512), ("256", 256), ("128", 128), ("64", 64), ("32", 32), ("16", 16)]
        for (suffix, size) in sizes {
            let iconView = IconCanvasView(code: scene.drawingCode, ismacOS: true, showCorners: true).frame(width: size, height: size)
            let renderer = ImageRenderer(content: iconView)
            if let image = renderer.nsImage { saveImage(image, name: "\(scene.name)_macOS_\(suffix).png", folder: folder, includeAlpha: includeAlpha) }
        }
        showCompletionAlert(folder: folder)
    }

    private static func exportCustomIcon(scene: SnapshotScene, folder: URL, includeAlpha: Bool) {
        let iconView = IconCanvasView(code: scene.drawingCode, ismacOS: false, showCorners: scene.iconShowCorners).frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: iconView)
        if let image = renderer.nsImage { saveImage(image, name: "\(scene.name)_Custom_Icon.png", folder: folder, includeAlpha: includeAlpha) }
        showCompletionAlert(folder: folder)
    }

    private static func renderAndExportSlices(scene: SnapshotScene, folder: URL, includeAlpha: Bool) {
        let baseWidth = CGFloat(scene.baseWidth)
        let baseHeight = CGFloat(scene.baseHeight)
        let totalWidth = baseWidth * CGFloat(scene.screenCount)

        for i in 0..<scene.screenCount {
            let finalImage = NSImage(size: NSSize(width: baseWidth, height: baseHeight))
            finalImage.lockFocus()
            guard let context = NSGraphicsContext.current?.cgContext else {
                finalImage.unlockFocus(); continue
            }

            // 1. 绘制背景色
            let bgColor = NSColor(Color(hex: scene.backgroundColor))
            bgColor.set()
            context.fill(CGRect(x: 0, y: 0, width: baseWidth, height: baseHeight))

            // 2. 绘制所有截图图层 (按 orderIndex 从大到小绘制，确保小的在顶层)
            let sortedImages = scene.imageLayers.sorted(by: { $0.orderIndex > $1.orderIndex })
            for layer in sortedImages {
                drawImageLayer(scene: scene, layer: layer, i: i, context: context, baseWidth: baseWidth, baseHeight: baseHeight, totalWidth: totalWidth)
            }

            // 3. 绘制所有文本图层
            let deltaX = (totalWidth / 2) - (CGFloat(i) * baseWidth + baseWidth / 2)
            let sortedTexts = scene.textLayers.sorted(by: { $0.orderIndex > $1.orderIndex })
            for layer in sortedTexts {
                drawTextLayer(scene: scene, layer: layer, i: i, baseWidth: baseWidth, totalWidth: totalWidth, deltaX: deltaX)
            }

            finalImage.unlockFocus()
            saveImage(finalImage, name: "\(scene.name)_Part_\(i+1).png", folder: folder, includeAlpha: includeAlpha)
        }
        showCompletionAlert(folder: folder)
    }

    private static func drawImageLayer(scene: SnapshotScene, layer: ImageLayer, i: Int, context: CGContext, baseWidth: CGFloat, baseHeight: CGFloat, totalWidth: CGFloat) {
        guard let data = layer.imageData, let originalImage = NSImage(data: data) else { return }
        let imgSize = originalImage.size
        let scaleW = totalWidth / imgSize.width
        let scaleH = baseHeight / imgSize.height
        let fitScale = min(scaleW, scaleH)

        let deltaX = (totalWidth / 2) - (CGFloat(i) * baseWidth + baseWidth / 2)
        let posX = baseWidth / 2 + deltaX + CGFloat(layer.offsetX)
        let posY = baseHeight / 2 - CGFloat(layer.offsetY)

        var imageRect = CGRect(x: posX - (imgSize.width * fitScale * layer.imageScale) / 2,
                             y: posY - (imgSize.height * fitScale * layer.imageScale) / 2,
                             width: imgSize.width * fitScale * layer.imageScale,
                             height: imgSize.height * fitScale * layer.imageScale)

        let shortSide = min(imageRect.width, imageRect.height)
        var currentPadding = CGFloat(0)

        if layer.showDeviceFrame {
            switch layer.deviceFrameStyle {
            case .iphone17:
                currentPadding = shortSide * 0.025
                imageRect = imageRect.insetBy(dx: currentPadding, dy: currentPadding)
            case .ipad_pro:
                currentPadding = shortSide * 0.045
                imageRect = imageRect.insetBy(dx: currentPadding, dy: currentPadding)
            case .minimal:
                currentPadding = shortSide * 0.03
                imageRect = imageRect.insetBy(dx: currentPadding, dy: currentPadding)
            case .macos:
                let topPad = imageRect.height * 0.06
                imageRect = CGRect(x: imageRect.origin.x, y: imageRect.origin.y, width: imageRect.width, height: imageRect.height - topPad)
            default: break
            }
        }

        if layer.showShadow {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        }

        let radiusPercent: CGFloat = {
            switch layer.deviceFrameStyle {
            case .iphone17: return 0.13
            case .ipad_pro: return 0.05
            case .macos: return 0.025
            case .minimal, .rounded: return 0.08
            case .none: return 0
            }
        }()
        let outerCornerRadius = min(imageRect.width + currentPadding*2, imageRect.height + currentPadding*2) * radiusPercent
        let innerCornerRadius = max(0, outerCornerRadius - currentPadding)
        let frameRect = imageRect.insetBy(dx: -currentPadding, dy: -currentPadding)
        let imagePath = NSBezierPath(roundedRect: imageRect, xRadius: innerCornerRadius, yRadius: innerCornerRadius)
        let shadowPath = NSBezierPath(roundedRect: frameRect, xRadius: outerCornerRadius, yRadius: outerCornerRadius)

        // --- 核心修复：绘制阴影 (基于最外层边界投射) ---
        if layer.showShadow {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            // 使用外层路径投射阴影，确保阴影不会被外壳遮挡
            NSColor(Color(hex: scene.backgroundColor)).setFill()
            shadowPath.fill()
            context.restoreGState()
        }

        context.saveGState()
        imagePath.addClip()
        originalImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        context.restoreGState()

        if layer.showDeviceFrame {
            context.saveGState()
            context.setShadow(offset: .zero, blur: 0, color: nil)

            if layer.deviceFrameStyle == .iphone17 {
                let metalW = currentPadding * 0.4
                let blackW = currentPadding * 0.6
                let metalColors = [NSColor(white: 0.35, alpha: 1), NSColor(white: 0.6, alpha: 1), NSColor(white: 0.8, alpha: 1), NSColor(white: 0.45, alpha: 1), NSColor(white: 0.15, alpha: 1)]
                let segW = metalW / 5
                for i in 0..<5 {
                    let offset = segW * CGFloat(i)
                    let ringPath = NSBezierPath(roundedRect: frameRect.insetBy(dx: offset + segW/2, dy: offset + segW/2), xRadius: max(0, outerCornerRadius - (offset + segW/2)), yRadius: max(0, outerCornerRadius - (offset + segW/2)))
                    metalColors[i].setStroke(); ringPath.lineWidth = segW; ringPath.stroke()
                }
                let blackPath = NSBezierPath(roundedRect: frameRect.insetBy(dx: metalW + blackW/2, dy: metalW + blackW/2), xRadius: max(0, outerCornerRadius - (metalW + blackW/2)), yRadius: max(0, outerCornerRadius - (metalW + blackW/2)))
                NSColor(white: 0.05, alpha: 1).setStroke(); blackPath.lineWidth = blackW; blackPath.stroke()

                let btnW = currentPadding * 0.15
                let btnSeg = btnW / 5
                let drawButton: (NSRect, Bool) -> Void = { rect, isLeft in
                    for i in 0..<5 {
                        let colorIndex = isLeft ? i : (4 - i)
                        metalColors[colorIndex].setFill()
                        let segRect = NSRect(x: rect.origin.x + CGFloat(i) * btnSeg, y: rect.origin.y, width: btnSeg, height: rect.size.height)
                        NSBezierPath(rect: segRect).fill()
                    }
                }
                drawButton(NSRect(x: frameRect.maxX - 1, y: frameRect.midY + frameRect.height * 0.05, width: btnW, height: frameRect.height * 0.09), false)
                drawButton(NSRect(x: frameRect.minX - btnW + 1, y: frameRect.midY + frameRect.height * 0.15, width: btnW, height: frameRect.height * 0.04), true)
                drawButton(NSRect(x: frameRect.minX - btnW + 1, y: frameRect.midY + frameRect.height * 0.05, width: btnW, height: frameRect.height * 0.06), true)
                drawButton(NSRect(x: frameRect.minX - btnW + 1, y: frameRect.midY - frameRect.height * 0.05, width: btnW, height: frameRect.height * 0.06), true)

                // 灵动岛
                let islandW = frameRect.width * 0.26; let islandH = frameRect.height * 0.03; let topOffset = currentPadding * 1.1
                let islandRect = NSRect(x: frameRect.midX - islandW/2, y: frameRect.maxY - islandH - topOffset, width: islandW, height: islandH)
                NSColor.black.setFill(); NSBezierPath(roundedRect: islandRect, xRadius: islandH/2, yRadius: islandH/2).fill()

            } else if layer.deviceFrameStyle == .ipad_pro {
                let metalW = currentPadding * 0.075; let blackW = currentPadding * 0.925
                let metalPath = NSBezierPath(roundedRect: frameRect.insetBy(dx: metalW/2, dy: metalW/2), xRadius: outerCornerRadius - metalW/2, yRadius: outerCornerRadius - metalW/2)
                NSColor(white: 0.75, alpha: 1).setStroke(); metalPath.lineWidth = metalW; metalPath.stroke()
                let blackPath = NSBezierPath(roundedRect: frameRect.insetBy(dx: metalW + blackW/2, dy: metalW + blackW/2), xRadius: max(0, outerCornerRadius - (metalW + blackW/2)), yRadius: max(0, outerCornerRadius - (metalW + blackW/2)))
                NSColor(white: 0.05, alpha: 1).setStroke(); blackPath.lineWidth = blackW; blackPath.stroke()

                // iPad 按键
                let btnW = currentPadding * 0.1
                NSColor(white: 0.75, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: frameRect.maxX - 1, y: frameRect.midY + frameRect.height * 0.35, width: btnW, height: frameRect.height * 0.04), xRadius: 1, yRadius: 1).fill()
                NSBezierPath(roundedRect: NSRect(x: frameRect.maxX - 1, y: frameRect.midY + frameRect.height * 0.28, width: btnW, height: frameRect.height * 0.04), xRadius: 1, yRadius: 1).fill()
                NSBezierPath(roundedRect: NSRect(x: frameRect.midX + frameRect.width * 0.3, y: frameRect.maxY - 1, width: frameRect.width * 0.08, height: btnW), xRadius: 1, yRadius: 1).fill()

            } else if layer.deviceFrameStyle == .minimal {
                NSColor(Color(hex: layer.bezelColor)).withAlphaComponent(0.8).setStroke()
                let minimalPath = NSBezierPath(roundedRect: frameRect, xRadius: outerCornerRadius, yRadius: outerCornerRadius)
                minimalPath.lineWidth = currentPadding
                minimalPath.stroke()
            } else if layer.deviceFrameStyle == .macos {
                let barH = imageRect.height * 0.06; let barRect = NSRect(x: imageRect.minX, y: imageRect.maxY, width: imageRect.width, height: barH)
                NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: barRect, xRadius: outerCornerRadius, yRadius: outerCornerRadius).fill()
                for (idx, color) in [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen].enumerated() {
                    let dotSize = barH * 0.3; let dotRect = NSRect(x: imageRect.minX + (barH * 0.4) + CGFloat(idx) * (dotSize + barH * 0.2), y: barRect.midY - dotSize/2, width: dotSize, height: dotSize)
                    color.setFill(); NSBezierPath(ovalIn: dotRect).fill()
                }
            }
            context.restoreGState()
        }

        if layer.showShadow { context.restoreGState() }
    }

    private static func drawTextLayer(scene: SnapshotScene, layer: TextLayer, i: Int, baseWidth: CGFloat, totalWidth: CGFloat, deltaX: CGFloat) {
        let textOverlay = VStack(alignment: layer.textAlignment.horizontalAlignment, spacing: CGFloat(scene.baseHeight * 0.01)) {
            let currentTitle = layer.isTextIndependent ? (i < layer.perScreenTitles.count ? layer.perScreenTitles[i] : layer.title) : layer.title
            let currentSubtitle = layer.isTextIndependent ? (i < layer.perScreenSubtitles.count ? layer.perScreenSubtitles[i] : layer.subtitle) : layer.subtitle
            Text(currentTitle).font(.system(size: CGFloat(scene.baseHeight * 0.05), weight: .bold, design: layer.fontDesign)).foregroundColor(Color(hex: layer.titleColor))
            Text(currentSubtitle).font(.system(size: CGFloat(scene.baseHeight * 0.025), weight: .medium, design: layer.fontDesign)).foregroundColor(Color(hex: layer.subtitleColor).opacity(0.8)).lineSpacing(5)
        }
        .multilineTextAlignment(layer.textAlignment.swiftUIAlignment)
        .padding(.top, CGFloat(scene.baseHeight * 0.06))
        .padding(.horizontal, 40)
        .frame(width: layer.isTextIndependent ? baseWidth : totalWidth)
        .scaleEffect(layer.textScale)
        .offset(x: (layer.isTextIndependent ? 0 : deltaX) + CGFloat(layer.textOffsetX), y: CGFloat(layer.textOffsetY))
        .frame(width: baseWidth, height: CGFloat(scene.baseHeight), alignment: .top)

        let textRenderer = ImageRenderer(content: textOverlay)
        textRenderer.scale = 1.0
        if let textImage = textRenderer.nsImage { textImage.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0) }
    }

    private static func saveImage(_ image: NSImage, name: String, folder: URL, includeAlpha: Bool) {
        let width = Int(image.size.width); let height = Int(image.size.height); let fileURL = folder.appendingPathComponent(name)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: includeAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        if !includeAlpha { context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
        var rect = NSRect(x: 0, y: 0, width: width, height: height)
        if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) { context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height)) }
        guard let finalCGImage = context.makeImage(), let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, "public.png" as CFString, 1, nil) else { return }
        let options: [CFString: Any] = ["HasAlpha" as CFString: includeAlpha ? kCFBooleanTrue! : kCFBooleanFalse!]
        CGImageDestinationAddImage(destination, finalCGImage, options as CFDictionary); CGImageDestinationFinalize(destination)
    }

    private static func showCompletionAlert(folder: URL) {
        let alert = NSAlert(); alert.messageText = "Export Successful"; alert.informativeText = "Assets have been saved."; alert.addButton(withTitle: "Show in Finder"); alert.addButton(withTitle: "Done")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(folder) }
    }
}
