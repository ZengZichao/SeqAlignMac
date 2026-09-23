//  AlignmentRenderer.swift
//  SeqAlignMac — 共享渲染层（画布与导出共用）
//
//  抽取 AlignmentRenderer 为纯绘制几何/颜色解析层。
//  画布（AlignmentCanvasView）和导出器（ExportManager）共同调用本结构体，
//  消除两处独立实现导致的几何参数漂移（如导出硬编码 cellWidth=14 而画布动态计算）。
//
//  本结构体只负责「几何计算 + 颜色解析」的单一事实来源；
//  画布保留交互逻辑（鼠标、键盘、选区），导出器保留文件封装。

import AppKit
import Foundation

// MARK: - 渲染几何（画布与导出共享）

/// 对齐渲染的几何参数。画布和导出器使用同一公式计算 cellWidth/cellHeight，
/// 杜绝「导出比例与画布显示不同」的漂移问题。
struct AlignmentRenderGeometry {
    let fontSize: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let nameColWidth: CGFloat
    let railHeight: CGFloat      // 保守度轨道高度
    let rulerHeight: CGFloat     // 标尺高度
    let showConsensus: Bool
    // 字体改为存储属性：计算属性每次访问都新建 NSFont，
    // 导出绘制循环内会反复触发 PostScript 名查找 / 字体创建
    let monoFont: NSFont
    let labelFont: NSFont
    let nameFont: NSFont
    let consensusFont: NSFont
    let rowNumFont: NSFont

    /// 共识行高度
    var consensusHeight: CGFloat { showConsensus ? cellHeight + 4 : 0 }
    /// 顶部带高度（轨道 + 标尺）
    var topBarHeight: CGFloat { railHeight + rulerHeight }
    /// 数据区起始 Y
    var dataY: CGFloat { topBarHeight + consensusHeight }

    /// 从字号 + 名称列宽创建几何参数（与画布 recomputeMetrics 同一公式）
    static func make(fontSize: CGFloat, nameColWidth: CGFloat, showConsensus: Bool = true) -> AlignmentRenderGeometry {
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let cellWidth = max(4, ("A" as NSString).size(withAttributes: [.font: mono]).width)
        let cellHeight = fontSize * 1.4
        let nameW = nameColWidth > 0 ? nameColWidth : 150
        let label = NSFont.systemFont(ofSize: fontSize - 1, weight: .regular)
        return AlignmentRenderGeometry(
            fontSize: fontSize,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            nameColWidth: nameW,
            railHeight: 12,
            rulerHeight: 24,
            showConsensus: showConsensus,
            monoFont: mono,
            labelFont: label,
            nameFont: NSFont(name: "PingFangSC-Regular", size: fontSize - 1) ?? label,
            consensusFont: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .medium),
            rowNumFont: NSFont.monospacedSystemFont(ofSize: fontSize - 2, weight: .regular)
        )
    }

    /// 计算布局尺寸
    func layoutSize(rows: ClosedRange<Int>, cols: ClosedRange<Int>) -> (width: CGFloat, height: CGFloat) {
        let width = nameColWidth + CGFloat(cols.count) * cellWidth
        let height = dataY + CGFloat(rows.count) * cellHeight
        return (width, height)
    }
}

// MARK: - 渲染颜色解析（画布与导出共享）

/// 对齐渲染的颜色解析。封装「残基 → 配色索引 → NSColor」的完整链路，
/// 确保画布和导出器使用同一套颜色映射，不再各自调用 ColorResolver/Minimal。
enum AlignmentRenderColors {
    /// 残基单元格的背景色
    static func cellBackground(residue: UInt8, row: Int, col: Int,
                               colorMatrix: [UInt8], colCount: Int,
                               scheme: ColorScheme, dark: Bool) -> NSColor {
        if residue == 0x2D {
            return Minimal.gapTint(dark: dark)
        }
        let colorIdx = colorMatrix[row * colCount + col]
        return ColorResolver.palette(scheme, index: Int(colorIdx), dark: dark).bg
    }

    /// 残基单元格的前景色
    static func cellForeground(residue: UInt8, row: Int, col: Int,
                               colorMatrix: [UInt8], colCount: Int,
                               scheme: ColorScheme, dark: Bool) -> NSColor {
        if residue == 0x2D {
            return Minimal.textMuted(dark: dark)
        }
        let colorIdx = colorMatrix[row * colCount + col]
        return ColorResolver.palette(scheme, index: Int(colorIdx), dark: dark).fg
    }

    /// 共识色（极简 = 灰阶一致度；其他 = 共识残基配色）
    static func consensusColor(consensus: UInt8, identity: Double,
                               scheme: ColorScheme, dark: Bool) -> NSColor {
        if scheme == .minimal {
            return Minimal.chartColor(identity: identity, dark: dark)
        }
        if consensus == 0x2D { return Minimal.gapTint(dark: dark) }
        let idx = ColorComputer.colorIndex(for: consensus, scheme: scheme)
        return ColorResolver.palette(scheme, index: Int(idx), dark: dark).bg
    }

    /// 语义颜色集合（一次性获取，避免重复调用）
    struct SemanticColors {
        let text: NSColor
        let textMuted: NSColor
        let textFaint: NSColor
        let card: NSColor
        let border: NSColor
        let background: NSColor

        init(dark: Bool) {
            self.text = Minimal.text(dark: dark)
            self.textMuted = Minimal.textMuted(dark: dark)
            self.textFaint = Minimal.textFaint(dark: dark)
            self.card = Minimal.card(dark: dark)
            self.border = Minimal.border(dark: dark)
            self.background = Minimal.exportBackground(dark: dark)
        }
    }
}
