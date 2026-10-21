import Cocoa

// MARK: - 应用图标（几何定义的唯一来源）
//
// 一份「¥」路径用于两处，避免图标与运行期标记各画一套而对不上：
//   ① 应用图标 .icns —— Finder / 可执行文件 / 关于面板 / Dock
//   ② 面板头部标题左侧的小标记
// （菜单栏状态项**不**挂标记：那里只显示金额文字，见 App.swift 的 updateTitle）
//
// 重新生成 .icns：`bash make-icon.sh`（内部调 `BalanceBar --export-icon <dir>` + iconutil）

enum BalanceIcon {
    /// Apple 图标栅格里底板占画布的比例（824 / 1024）
    static let bodyRatio: CGFloat = 824.0 / 1024.0

    // MARK: 几何

    /// 「¥」标记路径：铺满传入的方形 rect（含描边后墨迹正好内接）。
    /// 坐标以 rect 边长为单位、原点居中，取值范围见下方常量；
    /// 两横笔之间、以及 V 底与第一横之间都留出 ≈0.7 个笔画宽的空白，
    /// 否则粗笔画会把两横糊成一块（第一版就踩了：间距 0.23 − 笔画 0.21 ≈ 贴死）。
    static func markPath(in rect: NSRect) -> NSBezierPath {
        let s = min(rect.width, rect.height)
        let w = 0.135 * s              // 笔画宽度（相对边长）
        let cx = rect.midX, cy = rect.midY
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: cx + x * s, y: cy + y * s)
        }
        let path = NSBezierPath()
        path.lineWidth = w
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        // 左右两斜笔（汇于中点上方）
        path.move(to: p(-0.43, 0.4325)); path.line(to: p(0, 0.185))
        path.move(to: p(0.43, 0.4325));  path.line(to: p(0, 0.185))
        // 竖笔
        path.move(to: p(0, 0.185)); path.line(to: p(0, -0.4325))
        // 两横笔
        path.move(to: p(-0.42, -0.03)); path.line(to: p(0.42, -0.03))
        path.move(to: p(-0.42, -0.285)); path.line(to: p(0.42, -0.285))
        return path
    }

    /// macOS 图标用的连续圆角方形（超椭圆）。n 越大越接近直角，5 接近 Apple 的 squircle。
    static func squircle(in rect: NSRect, n: CGFloat = 5) -> NSBezierPath {
        let a = rect.width / 2, b = rect.height / 2
        let steps = 720
        let e = 2 / n
        let path = NSBezierPath()
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let ct = cos(t), st = sin(t)
            let x = a * (ct < 0 ? -1 : 1) * pow(abs(ct), e)
            let y = b * (st < 0 ? -1 : 1) * pow(abs(st), e)
            let pt = NSPoint(x: rect.midX + x, y: rect.midY + y)
            if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
        }
        path.close()
        return path
    }

    // MARK: 绘制

    /// 位图出口：所有渲染都走这里，保证 @1x / @2x 与导出 PNG 完全同源
    static func raster(size: Int, _ draw: (CGFloat) -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(CGFloat(size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 应用图标成图（S = 画布边长，像素）。
    /// 深色底板 + 白色「¥」：与面板里唯一的实心元素（黑底白字的「保存并刷新」）同一套语言。
    static func drawAppIcon(_ S: CGFloat) {
        let bodySide = S * bodyRatio
        let body = NSRect(x: (S - bodySide) / 2, y: (S - bodySide) / 2,
                          width: bodySide, height: bodySide)

        // ① 底板：极轻微的纵向渐变，避免纯色在大尺寸下发闷（色相仍是黑白灰）
        let top = NSColor(srgbRed: 0.145, green: 0.145, blue: 0.161, alpha: 1)   // #252529
        let bottom = NSColor(srgbRed: 0.043, green: 0.043, blue: 0.051, alpha: 1) // #0B0B0D
        if let g = NSGradient(colors: [top, bottom]) {
            g.draw(in: squircle(in: body), angle: -90)
        } else {
            top.setFill()
            squircle(in: body).fill()
        }

        // ② 「¥」标记：白色。小尺寸做光学补偿 —— 16/32px 下标记占比调大，
        // 否则在这个尺寸上笔画糊成一团看不出是 ¥
        let ratio: CGFloat = S <= 32 ? 0.56 : (S <= 64 ? 0.50 : 0.45)
        let m = bodySide * ratio
        NSColor.white.setStroke()
        markPath(in: NSRect(x: body.midX - m / 2, y: body.midY - m / 2, width: m, height: m)).stroke()
    }

    /// 单色小标记（面板头部用）。返回模板图交给 AppKit 自动反色。
    /// pt 传 14（面板头部）；菜单栏不再使用。
    static func glyphImage(pt: CGFloat, scale: CGFloat = 2) -> NSImage {
        let px = max(2, Int((pt * scale).rounded()))
        let rep = raster(size: px) { S in
            NSColor.black.setStroke()
            markPath(in: NSRect(x: 0, y: 0, width: S, height: S)).stroke()
        }
        let img = NSImage(size: NSSize(width: pt, height: pt))
        img.addRepresentation(rep)
        img.isTemplate = true
        return img
    }

    // MARK: 与系统解析结果比对（验证 Finder 真的用上了这张图）

    /// 把任意 NSImage 归一化成 size×size 的 RGBA 字节
    static func normalizedPixels(_ image: NSImage, size: Int) -> [UInt8] {
        let rep = raster(size: size) { S in
            image.draw(in: NSRect(x: 0, y: 0, width: S, height: S),
                       from: .zero, operation: .sourceOver, fraction: 1)
        }
        guard let data = rep.bitmapData else { return [] }
        let bytes = rep.bytesPerRow * rep.pixelsHigh
        return Array(UnsafeBufferPointer(start: data, count: bytes))
    }

    /// 两张图在 64×64 下的平均像素差（0～255）
    static func meanPixelDiff(_ a: NSImage, _ b: NSImage, size: Int = 64) -> Double {
        let pa = normalizedPixels(a, size: size), pb = normalizedPixels(b, size: size)
        guard pa.count == pb.count, !pa.isEmpty else { return 255 }
        var sum = 0
        for i in 0..<pa.count { sum += abs(Int(pa[i]) - Int(pb[i])) }
        return Double(sum) / Double(pa.count)
    }

    // MARK: .icns 导出
    /// 生成 AppIcon.iconset 所需的 10 个尺寸文件，返回写入的文件名
    @discardableResult
    static func exportIconSet(to dir: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // (文件名, 像素边长) —— 每个基础尺寸都给足 @1x/@2x，小尺寸单独渲染才不会糊
        let files: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
        ]
        var written: [String] = []
        for (name, px) in files {
            let rep = raster(size: px) { S in drawAppIcon(S) }
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "BalanceIcon", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "PNG 编码失败：\(name)"])
            }
            try png.write(to: dir.appendingPathComponent(name))
            written.append(name)
        }
        return written
    }
}
