import AppKit

// 生成 SAP GUI Tabs 图标:蓝色梯形主体(原创几何形,顶宽底窄、底边两端内收的四边形,
// 非任何注册商标),顶部叠一条浅色横条 + 三个小方块(页签),寓意"窗口顶部浮一条页签栏"。
func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }

    let s = size

    // 梯形主体:顶边宽、底边窄,底边两端向内收
    let left = s * 0.10
    let right = s * 0.90
    let top = s * 0.74
    let bottom = s * 0.26
    let slant = s * 0.16
    let radius = s * 0.05

    let trapezoid = CGMutablePath()
    let pts = [
        CGPoint(x: left, y: top),                 // 左上
        CGPoint(x: right, y: top),                // 右上
        CGPoint(x: right - slant, y: bottom),     // 右下(内收)
        CGPoint(x: left + slant, y: bottom)       // 左下(内收)
    ]
    trapezoid.addRoundedPolygon(points: pts, radius: radius)

    ctx.saveGState()
    ctx.addPath(trapezoid)
    ctx.clip()
    let colors = [
        NSColor(red: 0.05, green: 0.55, blue: 0.86, alpha: 1).cgColor, // 顶部亮蓝
        NSColor(red: 0.01, green: 0.28, blue: 0.56, alpha: 1).cgColor  // 底部深蓝
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
    ctx.restoreGState()

    // 顶部横条(页签栏):横跨梯形上部
    let barHeight = (top - bottom) * 0.30
    let barInset = s * 0.08
    let barRect = CGRect(x: left + barInset,
                         y: top - barHeight - (top - bottom) * 0.10,
                         width: (right - left) - barInset * 2,
                         height: barHeight)
    let barCorner = barHeight * 0.35
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.addPath(CGPath(roundedRect: barRect, cornerWidth: barCorner, cornerHeight: barCorner, transform: nil))
    ctx.fillPath()

    // 横条上三个小方块(页签),中间高亮
    let tabCount = 3
    let tabGap = barRect.width * 0.06
    let tabW = (barRect.width - tabGap * CGFloat(tabCount + 1)) / CGFloat(tabCount)
    let tabH = barRect.height * 0.5
    let tabY = barRect.midY - tabH / 2
    for i in 0..<tabCount {
        let x = barRect.minX + tabGap + (tabW + tabGap) * CGFloat(i)
        let r = CGRect(x: x, y: tabY, width: tabW, height: tabH)
        let c = (i == 1)
            ? NSColor(red: 0.05, green: 0.55, blue: 0.86, alpha: 1)
            : NSColor(red: 0.62, green: 0.74, blue: 0.86, alpha: 1)
        ctx.setFillColor(c.cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: tabH * 0.25, cornerHeight: tabH * 0.25, transform: nil))
        ctx.fillPath()
    }

    img.unlockFocus()
    return img
}

extension CGMutablePath {
    /// 画一个带圆角的多边形(各顶点处用 arc 倒角)
    func addRoundedPolygon(points: [CGPoint], radius: CGFloat) {
        guard points.count >= 3 else { return }
        let n = points.count
        for i in 0..<n {
            let prev = points[(i + n - 1) % n]
            let curr = points[i]
            let next = points[(i + 1) % n]
            if i == 0 {
                move(to: CGPoint(x: (curr.x + prev.x) / 2, y: (curr.y + prev.y) / 2))
            }
            addArc(tangent1End: curr, tangent2End: next, radius: radius)
        }
        closeSubpath()
    }
}

func pngData(_ image: NSImage, px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// iconset 各尺寸
let iconset = "/tmp/SAPGUITabs.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let specs: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for spec in specs {
    let data = pngData(NSImage(), px: spec.px)
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(spec.name).png"))
}
print("iconset written to \(iconset)")
