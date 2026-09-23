// gen_icon.swift — 生成应用图标 (icns)
// 新版设计：多序列比对列视图（黑白）——深中性底 #18181b，
// 三条序列行 × 九列残基圆角方块；中央列全行近白（保守列），
// 上下以垂直标线强调「对齐」。其余残基用中性灰阶表现差异。
// 与 logo.svg 保持同一设计。
import AppKit
import Foundation

// 以 1024 渲染基底，保证最大尺寸清晰
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: 2, y: 2) // 以下坐标沿用 512 设计空间

// 圆角矩形背景（深中性灰 #18181b）
let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 512, height: 512),
                          xRadius: 115, yRadius: 115)
NSColor(calibratedRed: 0.094, green: 0.094, blue: 0.105, alpha: 1).setFill()
bgPath.fill()

// 灰阶色板（与 SVG 一致）
let gray500 = NSColor(calibratedRed: 0.443, green: 0.443, blue: 0.459, alpha: 1)  // #71717a
let gray400 = NSColor(calibratedRed: 0.631, green: 0.631, blue: 0.651, alpha: 1)  // #a1a1aa
let gray600 = NSColor(calibratedRed: 0.322, green: 0.322, blue: 0.357, alpha: 1)  // #52525b
let nearWhite = NSColor(calibratedRed: 0.980, green: 0.980, blue: 0.980, alpha: 1) // #fafafa

// 每行残基灰阶（列 4 = 中央保守列，全行近白）
let rows: [[NSColor]] = [
    [gray600, gray500, gray400, gray600, nearWhite, gray500, gray600, gray400, gray500],
    [gray400, gray600, gray500, gray400, nearWhite, gray600, gray500, gray600, gray400],
    [gray500, gray400, gray600, gray500, nearWhite, gray400, gray500, gray600, gray400],
]
let rowY: [CGFloat] = [149, 245, 341]   // 系统坐标：NSBezierPath 原点在左下，与 SVG 的 y 翻转后一致
let cellSize: CGFloat = 22
let startX: CGFloat = 117
let step: CGFloat = 32

for (r, colors) in rows.enumerated() {
    for c in 0..<9 {
        let x = startX + CGFloat(c) * step
        let y = 512 - rowY[r] - cellSize   // SVG y → 翻转到 AppKit 坐标
        let cell = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: cellSize, height: cellSize),
                                xRadius: 6, yRadius: 6)
        colors[c].setFill()
        cell.fill()
    }
}

// 对齐标线（中央保守列上下延伸，近白）
let marker = NSColor(calibratedRed: 0.980, green: 0.980, blue: 0.980, alpha: 0.85)
marker.setStroke()
let line = NSBezierPath()
let cx: CGFloat = 256
// SVG y=96..122 → AppKit y = 512-122 .. 512-96
line.move(to: NSPoint(x: cx, y: 512 - 122)); line.line(to: NSPoint(x: cx, y: 512 - 96))
line.move(to: NSPoint(x: cx, y: 512 - 416)); line.line(to: NSPoint(x: cx, y: 512 - 390))
line.lineWidth = 5
line.lineCapStyle = .round
line.stroke()

image.unlockFocus()

// 生成各尺寸图标
// 输出目录从命令行参数取（build.sh 传入），未传参时回退脚本所在目录，
// 避免依赖调用时的 CWD（从其他目录执行时图标会写到错误位置）
let scriptDir = CommandLine.arguments.first.flatMap { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
    ?? FileManager.default.currentDirectoryPath
let iconsetDir = (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : scriptDir) + "/icon.iconset"
do {
    try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write("无法创建 iconset 目录 \(iconsetDir): \(error)\n".data(using: .utf8)!)
    exit(1)
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (s, name) in sizes {
    let small = NSImage(size: NSSize(width: s, height: s))
    small.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    small.unlockFocus()
    if let tiff = small.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let outPath = iconsetDir + "/" + name
        do {
            try png.write(to: URL(fileURLWithPath: outPath))
            print("生成: \(name) (\(s)x\(s))")
        } catch {
            FileHandle.standardError.write("写入 \(outPath) 失败: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}

print("图标生成完成")
