import SwiftUI

struct IconData: Codable {
    var background: String
    var layers: [IconLayer]
}

struct IconLayer: Codable {
    var type: String
    var name: String?
    var form: String?
    var color: String
    var scale: Double
    var widthScale: Double?
    var heightScale: Double?
    var x: Double?
    var y: Double?
    var opacity: Double?
    var rotation: Double?
    var cornerRadius: Double?
    var strokeWidth: Double?
}

struct IconCanvasView: View {
    let code: String
    let ismacOS: Bool
    let showCorners: Bool

    var body: some View {
        Canvas { context, size in
            let fullRect = CGRect(origin: .zero, size: size)

            guard let data = code.data(using: .utf8),
                  let icon = try? JSONDecoder().decode(IconData.self, from: data) else {
                context.fill(Path(fullRect), with: .color(.gray.opacity(0.3)))
                return
            }

            // 逻辑：如果是 macOS，强制留白；否则 100%
            let drawSize = ismacOS ? size.width * 0.8 : size.width
            let offset = (size.width - drawSize) / 2
            let drawRect = CGRect(x: offset, y: offset, width: drawSize, height: drawSize)

            // 裁切逻辑：如果是 macOS，强制圆角；如果是 iOS，跟随 showCorners 开关
            let shouldClip = ismacOS || showCorners
            if shouldClip {
                context.clip(to: Path(roundedRect: drawRect, cornerRadius: drawSize * 0.225))
            }

            // 填充背景
            context.fill(Path(drawRect), with: .color(Color(hex: icon.background)))

            for (index, layer) in icon.layers.enumerated() {
                let baseSize = drawSize * layer.scale
                let width = baseSize * (layer.widthScale ?? 1.0)
                let height = baseSize * (layer.heightScale ?? 1.0)

                let lx = drawRect.midX + (layer.x ?? 0) * (drawSize/2) - (width/2)
                let ly = drawRect.midY + (layer.y ?? 0) * (drawSize/2) - (height/2)
                let rect = CGRect(x: lx, y: ly, width: width, height: height)

                var layerContext = context
                layerContext.opacity = layer.opacity ?? 1.0

                if let rotation = layer.rotation {
                    layerContext.translateBy(x: rect.midX, y: rect.midY)
                    layerContext.rotate(by: .degrees(rotation))
                    layerContext.translateBy(x: -rect.midX, y: -rect.midY)
                }

                if layer.type == "symbol", layer.name != nil {
                    if let image = context.resolveSymbol(id: "sym_\(index)") {
                        layerContext.draw(image, in: rect)
                    }
                } else if layer.type == "shape" {
                    let path: Path
                    if layer.form == "circle" {
                        path = Path(ellipseIn: rect)
                    } else if layer.form == "triangle" {
                        var p = Path()
                        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
                        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                        p.closeSubpath()
                        path = p
                    } else {
                        let cornerRadius = (layer.cornerRadius ?? 0) * (min(width, height)/2)
                        path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                    }

                    if let stroke = layer.strokeWidth {
                        layerContext.stroke(path, with: .color(Color(hex: layer.color)), lineWidth: stroke * (drawSize/100))
                    } else {
                        layerContext.fill(path, with: .color(Color(hex: layer.color)))
                    }
                }
            }
        } symbols: {
            if let data = code.data(using: .utf8),
               let icon = try? JSONDecoder().decode(IconData.self, from: data) {
                ForEach(0..<icon.layers.count, id: \.self) { index in
                    let layer = icon.layers[index]
                    if layer.type == "symbol", let name = layer.name {
                        Image(systemName: name)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .fontWeight(.bold)
                            .foregroundStyle(Color(hex: layer.color))
                            .tag("sym_\(index)")
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
