import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    func toHex() -> String? {
        // 先转为 NSColor，并强制转换到兼容的 RGB 颜色空间
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else {
            // 如果转换失败，尝试从组件手动提取
            return nil
        }

        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // 修正：判断颜色是深色还是浅色
    func isLight() -> Bool {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else { return false }

        // 使用感知亮度标准公式 (归一化到 0.0 - 1.0)
        let luminance = (0.299 * rgbColor.redComponent + 0.587 * rgbColor.greenComponent + 0.114 * rgbColor.blueComponent)
        return luminance > 0.6
    }

    // 新增：调整颜色的饱和度和亮度，生成高级背景色
    func adjustedForBackground(isDark: Bool = false) -> Color {
        // 核心修复：先强制转换到 DeviceRGB 颜色空间，确保 getHue 能成功获取正确的色相
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else { return self }

        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgbColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        if isDark {
            return Color(hue: Double(h), saturation: 0.2, brightness: 0.15)
        } else {
            // 活力消减色逻辑：保持色相，极低饱和度 (6%)，极高亮度 (97%)
            return Color(hue: Double(h), saturation: 0.2, brightness: 0.6)
        }
    }
}

extension NSImage {
    // 新增：提取图片的主色调（采样均值法）
    func extractAverageColor() -> NSColor? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // 1. 使用 Core Image 滤镜进行区域平均采样
        let inputImage = CIImage(cgImage: cgImage)
        let extentVector = CIVector(x: inputImage.extent.origin.x,
                                  y: inputImage.extent.origin.y,
                                  z: inputImage.extent.size.width,
                                  w: inputImage.extent.size.height)

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: inputImage,
            kCIInputExtentKey: extentVector
        ]) else { return nil }

        guard let outputImage = filter.outputImage else { return nil }

        // 2. 读取 1x1 结果像素
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(outputImage,
                      toBitmap: &bitmap,
                      rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8,
                      colorSpace: nil)

        return NSColor(red: CGFloat(bitmap[0]) / 255.0,
                       green: CGFloat(bitmap[1]) / 255.0,
                       blue: CGFloat(bitmap[2]) / 255.0,
                       alpha: CGFloat(bitmap[3]) / 255.0)
    }

    // 新增：提取调色盘（多色采样法）
    func extractPalette(count: Int = 5) -> [NSColor] {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }

        // 1. 极大压缩图片到 32x32 像素，方便聚类分析
        let width = 32
        let height = 32
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(data: &rawData, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                     space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 2. 统计颜色频率（忽略极暗和极亮的背景干扰）
        var colorCounts: [Int: Int] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = rawData[offset]
                let g = rawData[offset + 1]
                let b = rawData[offset + 2]

                // 简单的颜色量化：将 256 级简化为 16 级 (4-bit per channel)
                let quantizedR = Int(r / 16)
                let quantizedG = Int(g / 16)
                let quantizedB = Int(b / 16)

                // 排除极黑和极白
                let brightness = quantizedR + quantizedG + quantizedB
                if brightness < 3 || brightness > 42 { continue }

                let key = (quantizedR << 8) | (quantizedG << 4) | quantizedB
                colorCounts[key, default: 0] += 1
            }
        }

        // 3. 取频率最高的几种颜色
        let sortedKeys = colorCounts.sorted { $0.value > $1.value }.map { $0.key }

        var results: [NSColor] = []
        for key in sortedKeys.prefix(count) {
            let r = CGFloat((key >> 8) & 0xF) * 17 / 255.0
            let g = CGFloat((key >> 4) & 0xF) * 17 / 255.0
            let b = CGFloat(key & 0xF) * 17 / 255.0
            results.append(NSColor(red: r, green: g, blue: b, alpha: 1.0))
        }

        return results
    }
}
