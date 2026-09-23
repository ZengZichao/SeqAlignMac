//  ExportManager.swift
//  SeqAlignMac — 图像/矢量导出（PNG/PDF/SVG）
//
//  设计要点：
//  1. 导出比例与软件画布一致 —— 统一几何：cellWidth 取当前字号的等宽字宽（与画布
//     recomputeMetrics 同一公式）、cellHeight = fontSize×1.4、nameColWidth 取画布持久化值
//     （UserDefaults "SeqAlignMac.nameColWidth"），并完整复刻画布的头部带：
//     保守度轨道(12) + 标尺(24) + 共识行(cellHeight+4) + 名称列 + 数据区（斑马纹/空位下划线）。
//  2. SVG 写盘前先用 FileManager 创建空文件（FileHandle(forWritingTo:) 要求文件已存在）。
//  3. PDF 的 CGDataConsumer 数据流要等上下文 closePDF() 收尾（写入 trailer/xref）才完整，
//     endPage() 后须显式 closePDF() 再读取数据。

import AppKit
import Foundation

/// SVG 坐标格式化（保留亚像素精度，与 PDF/PNG 版式一致）
enum SvgNum {
    static func nf(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    static func nf(_ v: Int) -> String { String(v) }
    static func nf(_ v: Double) -> String { String(format: "%.2f", v) }
}
enum SvgHelper {}

struct ExportOptions {
    var format: ExportFormat = .png
    var dpi: Int = 300
    // 接口只暴露真实生效的开关：drawScene 与 exportSVG 恒画名称列与标尺，
    // 不提供没有读取点的字段（否则一旦接上 UI 就是"取消勾选无反应"）；
    // 界面唯一可关的是 showConsensus。
    var colorScheme: ColorScheme = .defaultNucleotide
    /// 仅导出选中区域：nil = 整份
    var rowRange: ClosedRange<Int>? = nil
    var colRange: ClosedRange<Int>? = nil
    // —— 与画布一致的几何参数（保证导出比例与软件显示相同）——
    /// 当前字号（Workspace.fontSize，默认 13，用户在工具栏/设置中缩放）
    var fontSize: CGFloat = 13
    /// 名称列宽度（画布持久化于 UserDefaults，默认 150，用户可拖拽调整）
    var nameColWidth: CGFloat = 150
    /// 是否绘制共识行（画布 showConsensus 默认 true，且无外部开关 → 始终包含）
    var showConsensus: Bool = true
    /// 是否使用深色模式导出：读取调用方外观偏好，保证导出图与画布视觉一致
    /// （避免深色画布配白底黑字的导出图）。
    var dark: Bool = false
    /// 预览限宽（像素）。nil = 不限制（正式导出）；预览路径传 1600
    /// 避免全尺寸 300 DPI 渲染数十秒无反馈。
    var maxPixelWidth: Int? = nil
}

enum ExportFormat {
    case png, pdf, svg
}

enum ExportManager {
    // 导出前景/背景走设计令牌，浅色下近黑字 + 白皮书 + 灰阶数据，深色可零成本扩展。
    // 背景/前景动态读取 options.dark，保证导出与画布外观一致。
    private static func exportBgColor(dark: Bool) -> NSColor { Minimal.exportBackground(dark: dark) }
    private static func exportFgColor(dark: Bool) -> NSColor { Minimal.exportForeground(dark: dark) }

    private static func hex(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.deviceRGB) ?? c
        return String(format: "#%02X%02X%02X",
                      Int((s.redComponent * 255).rounded()),
                      Int((s.greenComponent * 255).rounded()),
                      Int((s.blueComponent * 255).rounded()))
    }

    /// 将对齐导出为图像/矢量文件内容。
    /// 失败一律 throw（位图分配失败 / PDF 上下文创建失败 / SVG 写盘失败 / 尺寸超限），
    /// 绝不静默返回空 Data，避免上层写盘成功即提示「已导出」却产出 0 字节损坏文件。
    static func exportImage(_ alignment: Alignment, options: ExportOptions) throws -> Data {
        // '密码子 + 氨基酸'混排轨（.both 模式）里 75% 的字母是 A/C/G/T，
        // 任何基于它的定量结果都不具备生物学意义，因此不提供图像导出。
        guard !AlignmentTranslator.isMixedCodonTrack(alignment) else {
            throw CoreError.unsupported(L.s.translationMixedTrack)
        }
        switch options.format {
        case .png: return try exportPNG(alignment, options: options)
        case .pdf: return try exportPDF(alignment, options: options)
        case .svg: return try exportSVG(alignment, options: options)
        }
    }

    // MARK: - 几何（使用共享 AlignmentRenderGeometry，与画布同一公式）

    private typealias ExportGeometry = AlignmentRenderGeometry

    /// 与画布 recomputeMetrics 同一公式：cellWidth = 等宽 "A" 字宽；cellHeight = fontSize×1.4
    private static func makeGeometry(_ options: ExportOptions) -> ExportGeometry {
        AlignmentRenderGeometry.make(fontSize: options.fontSize,
                                      nameColWidth: options.nameColWidth,
                                      showConsensus: options.showConsensus)
    }

    private static func layoutSize(_ geo: ExportGeometry,
                                   rows: ClosedRange<Int>,
                                   cols: ClosedRange<Int>) -> (width: CGFloat, height: CGFloat) {
        let width = geo.nameColWidth + CGFloat(cols.count) * geo.cellWidth
        let height = geo.dataY + CGFloat(rows.count) * geo.cellHeight
        return (width, height)
    }

    // MARK: - 共享绘制（PNG / PDF 共用，逻辑坐标：原点左上、y 向下，与画布一致）

    /// 在给定图形上下文绘制整张对齐（逻辑坐标）。调用方负责：
    /// 1) 将上下文坐标系翻转为「左上原点、y 向下」并缩放（PNG 按 DPI、PDF 按 1:1）；
    /// 2) 用 NSGraphicsContext(cgContext:flipped:true) 包装，保证文字正立。
    private static func drawScene(ctx: NSGraphicsContext,
                                  align: Alignment,
                                  options: ExportOptions,
                                  geo: ExportGeometry,
                                  rows: ClosedRange<Int>,
                                  cols: ClosedRange<Int>) {
        let cg = ctx.cgContext
        let dark = options.dark  // 从 options 读取深色模式，与画布外观一致
        let (width, height) = layoutSize(geo, rows: rows, cols: cols)

        // 0. 背景
        exportBgColor(dark: dark).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        // 字体（与画布同款：消费几何结构缓存的字体，避免每次绘制新建）
        let monoFont = geo.monoFont
        let labelFont = geo.labelFont
        let nameFont = geo.nameFont
        let consFont = geo.consensusFont
        let rowNumFont = geo.rowNumFont

        let textFg = Minimal.text(dark: dark)
        let mutedFg = Minimal.textMuted(dark: dark)
        let faintFg = Minimal.textFaint(dark: dark)
        let cardBg = Minimal.card(dark: dark)
        let border = Minimal.border(dark: dark)

        // 列统计范围钳制到导出区间——只导出 100×100 选区不再对整份比对
        // 做全表 O(rows×cols) 统计（数组仍按全表长度索引，绘制端无需改动）
        let statsColRange = max(0, cols.lowerBound)...max(0, cols.upperBound)
        let stats = AlignmentStatsCalculator.computeColumnStats(align, columns: statsColRange, mode: AppSettings.consensusMode)
        // 视口颜色矩阵
        let colorMatrix = ColorComputer.computeViewport(align, scheme: options.colorScheme,
                                                        rowStart: rows.lowerBound,
                                                        rowCount: rows.count,
                                                        colStart: cols.lowerBound,
                                                        colCount: cols.count,
                                                        identities: stats.identity)

        let nameW = geo.nameColWidth
        let cellW = geo.cellWidth
        let cellH = geo.cellHeight
        let rowCount = rows.count
        let colCount = cols.count

        // 1. 保守度轨道（轨道底 + 每列色块）
        let railY: CGFloat = 0
        cardBg.setFill()
        NSRect(x: 0, y: railY, width: width, height: geo.railHeight).fill()
        for c in 0..<colCount {
            let col = cols.lowerBound + c
            guard col < stats.columnCount else { continue }
            let identity = stats.identity[col]
            let consensus = stats.consensus[col]
            let x = nameW + CGFloat(c) * cellW
            let base = consensusColorExport(consensus: consensus, identity: identity, scheme: options.colorScheme, dark: dark)
            let alpha: CGFloat = options.colorScheme == .minimal ? 1.0 : (0.35 + 0.65 * identity)
            base.withAlphaComponent(alpha).setFill()
            NSRect(x: x, y: railY + 1, width: cellW, height: geo.railHeight - 2).fill()
            if identity >= 1.0 {
                consensusColorExport(consensus: consensus, identity: 1.0, scheme: options.colorScheme, dark: dark).setFill()
                NSRect(x: x, y: railY, width: cellW, height: 2).fill()
            }
        }
        // 轨道 / 标尺分隔线
        border.setStroke()
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: 0, y: railY + geo.railHeight))
        cg.addLine(to: CGPoint(x: width, y: railY + geo.railHeight))
        cg.strokePath()

        // 2. 标尺
        let rulerY = geo.railHeight
        cardBg.setFill()
        NSRect(x: 0, y: rulerY, width: width, height: geo.rulerHeight).fill()
        for c in 0..<colCount {
            let col = cols.lowerBound + c
            if col % 10 == 0 {
                let x = nameW + CGFloat(c) * cellW
                let label = "\(col + 1)"
                let digits = label.count
                let font: NSFont = digits > 4 ? NSFont.systemFont(ofSize: max(7, labelFont.pointSize - 3))
                              : (digits > 3 ? NSFont.systemFont(ofSize: max(8, labelFont.pointSize - 1)) : labelFont)
                let rulerTextH = font.ascender - font.descender
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .right
                let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                            .foregroundColor: mutedFg,
                                                            .paragraphStyle: paragraph]
                (label as NSString).draw(in: NSRect(x: x,
                                                    y: rulerY + max(0, (geo.rulerHeight - rulerTextH) / 2),
                                                    width: cellW,
                                                    height: rulerTextH),
                                         withAttributes: attrs)
                // 垂直网格线（贯穿数据区）
                border.setStroke()
                cg.setLineWidth(0.5)
                cg.move(to: CGPoint(x: x, y: rulerY))
                cg.addLine(to: CGPoint(x: x, y: height))
                cg.strokePath()
            }
        }

        // 3. 共识行
        if geo.showConsensus {
            let consY = geo.topBarHeight
            cardBg.setFill()
            NSRect(x: 0, y: consY, width: width, height: geo.consensusHeight).fill()
            let labelStr = L.s.exportConsensusLabel as NSString   // 导出图标签随界面语言切换
            let labelPara = NSMutableParagraphStyle()
            labelPara.lineBreakMode = .byClipping
            labelStr.draw(in: NSRect(x: 8, y: consY, width: nameW - 16, height: geo.consensusHeight),
                          withAttributes: [.font: nameFont, .foregroundColor: textFg, .paragraphStyle: labelPara])
            for c in 0..<colCount {
                let col = cols.lowerBound + c
                guard col < stats.columnCount else { continue }
                let res = stats.consensus[col]
                let identity = stats.identity[col]
                let x = nameW + CGFloat(c) * cellW
                if options.colorScheme == .minimal {
                    if identity >= 1.0 {
                        Minimal.chartColor(identity: 1.0, dark: dark).withAlphaComponent(0.14).setFill()
                    } else if identity > 0.5 {
                        Minimal.chartColor(identity: 0.5, dark: dark).withAlphaComponent(0.10).setFill()
                    } else {
                        NSColor.clear.setFill()
                    }
                } else {
                    consensusColorExport(consensus: res, identity: identity, scheme: options.colorScheme, dark: dark)
                        .withAlphaComponent(0.30).setFill()
                }
                NSRect(x: x, y: consY, width: cellW, height: cellH).fill()
                let resChar = String(UnicodeScalar(res)) as NSString
                let consTextH = consFont.ascender - consFont.descender
                let rect = NSRect(x: x, y: consY + max(0, (cellH - consTextH) / 2),
                                  width: cellW, height: consTextH)
                resChar.draw(in: rect, withAttributes: [.font: consFont, .foregroundColor: textFg])
            }
        }

        // 4. 名称列
        let nameY = geo.dataY
        cardBg.setFill()
        NSRect(x: 0, y: nameY, width: nameW, height: height - nameY).fill()
        for r in 0..<rowCount {
            let row = rows.lowerBound + r
            guard row < align.seqCount else { continue }
            let y = nameY + CGFloat(r) * cellH
            // 行号（右对齐、弱化）
            let rowNum = "\(row + 1)" as NSString
            let rowNumTextH = rowNumFont.ascender - rowNumFont.descender
            let rowNumPara = NSMutableParagraphStyle()
            rowNumPara.alignment = .right
            rowNumPara.lineBreakMode = .byClipping
            rowNum.draw(in: NSRect(x: 4, y: y + max(0, (cellH - rowNumTextH) / 2), width: 22, height: rowNumTextH),
                        withAttributes: [.font: rowNumFont, .foregroundColor: faintFg, .paragraphStyle: rowNumPara])
            // 名称（超长截断）
            let name = align.sequences[row].name as NSString
            let textH = nameFont.ascender - nameFont.descender
            let availWidth = nameW - 28 - 6
            let namePara = NSMutableParagraphStyle()
            namePara.lineBreakMode = .byTruncatingTail
            name.draw(with: NSRect(x: 28, y: y + max(0, (cellH - textH) / 2), width: max(10, availWidth), height: textH),
                      options: [.usesLineFragmentOrigin],
                      attributes: [.font: nameFont, .foregroundColor: textFg, .paragraphStyle: namePara])
        }

        // 5. 残基（数据区）
        for r in 0..<rowCount {
            let row = rows.lowerBound + r
            guard row < align.seqCount else { continue }
            let y = nameY + CGFloat(r) * cellH
            let seq = align.sequences[row]
            // 斑马纹（偶数行浅灰底，与画布一致）
            if r % 2 == 0 {
                cardBg.setFill()
                NSRect(x: nameW, y: y, width: width - nameW, height: cellH).fill()
            }
            for c in 0..<colCount {
                let col = cols.lowerBound + c
                guard col < seq.residues.count else { continue }
                let res = seq.residues[col]
                let x = nameW + CGFloat(c) * cellW
                let cellRect = NSRect(x: x, y: y, width: cellW, height: cellH)
                if res == 0x2D {
                    // 空位：中性底色 + 下划线
                    Minimal.gapTint(dark: dark).setFill()
                    cellRect.fill()
                    let gapTextH = monoFont.ascender - monoFont.descender
                    let gapRect = NSRect(x: x, y: y + max(0, (cellH - gapTextH) / 2), width: cellW, height: gapTextH)
                    let gapAttrs: [NSAttributedString.Key: Any] = [.font: monoFont,
                                                                   .foregroundColor: mutedFg,
                                                                   .underlineStyle: NSUnderlineStyle.single.rawValue]
                    (String(UnicodeScalar(res)) as NSString).draw(in: gapRect, withAttributes: gapAttrs)
                    continue
                }
                let colorIdx = colorMatrix[r * colCount + c]
                let palette = ColorResolver.palette(options.colorScheme, index: Int(colorIdx), dark: dark)
                palette.bg.setFill()
                cellRect.fill()
                let resChar = String(UnicodeScalar(res)) as NSString
                let resTextH = monoFont.ascender - monoFont.descender
                let resRect = NSRect(x: x, y: y + max(0, (cellH - resTextH) / 2), width: cellW, height: resTextH)
                resChar.draw(in: resRect, withAttributes: [.font: monoFont, .foregroundColor: palette.fg])
            }
        }

        // 6. 名称列分隔线
        border.setStroke()
        cg.setLineWidth(1)
        cg.move(to: CGPoint(x: nameW, y: 0))
        cg.addLine(to: CGPoint(x: nameW, y: height))
        cg.strokePath()
    }

    // MARK: - PNG

    private static func exportPNG(_ alignment: Alignment, options: ExportOptions) throws -> Data {
        let geo = makeGeometry(options)
        let rows = effectiveRowRange(alignment, options)
        let cols = effectiveColRange(alignment, options)
        let (width, height) = layoutSize(geo, rows: rows, cols: cols)
        var scale = CGFloat(options.dpi) / 72.0
        // 预览限宽——缩略框用不到全尺寸位图，钳制到 maxPixelWidth
        if let maxW = options.maxPixelWidth, width * scale > CGFloat(maxW), width > 0 {
            scale = CGFloat(maxW) / width
        }
        let wpx = Int(width * scale)
        let hpx = Int(height * scale)
        guard wpx > 0, hpx > 0 else {
            throw CoreError.format("导出尺寸无效（\(wpx)×\(hpx) 像素）")
        }
        // 位图尺寸上限：超大比对 × 高 DPI 可请求 12GB 位图，CGContext 创建必然失败，
        // 提前给出可操作的错误（建议降 DPI / 缩小范围）
        let estimatedBytes = Double(wpx) * Double(hpx) * 4
        guard estimatedBytes <= 2_000_000_000 else {
            let gb = estimatedBytes / 1_000_000_000
            throw CoreError.format(String(format: "导出位图过大（约 %.1f GB），请降低 DPI 或缩小导出范围", gb))
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let cgContext = CGContext(data: nil, width: wpx, height: hpx,
                                        bitsPerComponent: 8, bytesPerRow: 0,
                                        space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw CoreError.format("无法创建 \(wpx)×\(hpx) 位图上下文，请降低 DPI 或缩小导出范围")
        }
        // 翻转 CTM：逻辑左上原点 → 像素（与画布 isFlipped 一致）
        cgContext.translateBy(x: 0, y: CGFloat(hpx))
        cgContext.scaleBy(x: scale, y: -scale)

        let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        drawScene(ctx: nsContext, align: alignment, options: options, geo: geo, rows: rows, cols: cols)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgContext.makeImage() else {
            throw CoreError.format("位图快照失败，请降低 DPI 或缩小导出范围")
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw CoreError.format("PNG 编码失败")
        }
        return png
    }

    // MARK: - PDF

    private static func exportPDF(_ alignment: Alignment, options: ExportOptions) throws -> Data {
        let geo = makeGeometry(options)
        let rows = effectiveRowRange(alignment, options)
        let cols = effectiveColRange(alignment, options)
        let (width, height) = layoutSize(geo, rows: rows, cols: cols)
        guard width > 0, height > 0 else {
            throw CoreError.format("导出尺寸无效")
        }

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: pdfData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CoreError.format("无法创建 PDF 上下文")
        }

        pdfContext.beginPage(mediaBox: &mediaBox)
        // 翻转 CTM（逻辑左上原点 → PDF 用户空间，1:1）
        pdfContext.translateBy(x: 0, y: height)
        pdfContext.scaleBy(x: 1.0, y: -1.0)

        let nsContext = NSGraphicsContext(cgContext: pdfContext, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        drawScene(ctx: nsContext, align: alignment, options: options, geo: geo, rows: rows, cols: cols)
        NSGraphicsContext.restoreGraphicsState()

        pdfContext.endPage()
        // CGDataConsumer 的 PDF 数据流（含 trailer/xref）要在上下文「关闭」时
        // 才完整写入。若仅 flush() 后立刻快照 pdfData，常得到 0 字节 / 无法打开的文件，
        // 因此显式 closePDF() 收尾后再读取，确保 Data 完整。
        pdfContext.closePDF()
        return pdfData as Data
    }

    // MARK: - SVG（内存缓冲聚合——SVG 本就是文本，直接构建缓冲后一次转换，
    // 避免逐残基多次系统调用与临时文件中转）

    private static func exportSVG(_ alignment: Alignment, options: ExportOptions) throws -> Data {
        let geo = makeGeometry(options)
        let rows = effectiveRowRange(alignment, options)
        let cols = effectiveColRange(alignment, options)
        let (width, height) = layoutSize(geo, rows: rows, cols: cols)
        let nameW = geo.nameColWidth
        let cellW = geo.cellWidth
        let cellH = geo.cellHeight
        let dark = options.dark  // SVG 导出同样读取深色模式偏好

        // String 缓冲聚合，按 chunk 定期落 Data 避免单串无限膨胀
        var buffer = ""
        buffer.reserveCapacity(1 << 20)
        var chunks: [Data] = []
        func flushBuffer() {
            if !buffer.isEmpty {
                chunks.append(Data(buffer.utf8))
                buffer = ""
            }
        }
        let write: (String) -> Void = { s in buffer += s }

        let svgColor: (NSColor, CGFloat) -> String = { c, a in
            if a >= 0.999 { return "fill=\"\(Self.hex(c))\"" }
            return "fill=\"\(Self.hex(c))\" fill-opacity=\"\(String(format: "%.3f", a))\""
        }

        // 列统计范围钳制到导出区间（与 drawScene 同理）
        let statsColRange = max(0, cols.lowerBound)...max(0, cols.upperBound)
        let stats = AlignmentStatsCalculator.computeColumnStats(alignment, columns: statsColRange, mode: AppSettings.consensusMode)
        let colorMatrix = ColorComputer.computeViewport(alignment, scheme: options.colorScheme,
                                                        rowStart: rows.lowerBound, rowCount: rows.count,
                                                        colStart: cols.lowerBound, colCount: cols.count,
                                                        identities: stats.identity)

        write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        write("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(SvgNum.nf(width))\" height=\"\(SvgNum.nf(height))\" viewBox=\"0 0 \(SvgNum.nf(width)) \(SvgNum.nf(height))\">\n")
        write("<rect x=\"0\" y=\"0\" width=\"\(SvgNum.nf(width))\" height=\"\(SvgNum.nf(height))\" fill=\"\(Self.hex(exportBgColor(dark: dark)))\"/>\n")

        // 名称列裁剪（避免长名称溢出到数据区）
        write("<defs><clipPath id=\"nameClip\"><rect x=\"0\" y=\"\(SvgNum.nf(geo.dataY))\" width=\"\(SvgNum.nf(nameW))\" height=\"\(SvgNum.nf(height - geo.dataY))\"/></clipPath></defs>\n")

        // 1. 保守度轨道
        write("<rect x=\"0\" y=\"0\" width=\"\(SvgNum.nf(width))\" height=\"\(SvgNum.nf(geo.railHeight))\" fill=\"\(Self.hex(Minimal.card(dark: dark)))\"/>\n")
        for c in 0..<cols.count {
            let col = cols.lowerBound + c
            guard col < stats.columnCount else { continue }
            let identity = stats.identity[col]
            let consensus = stats.consensus[col]
            let x = nameW + CGFloat(c) * cellW
            let base = consensusColorExport(consensus: consensus, identity: identity, scheme: options.colorScheme, dark: dark)
            let a: CGFloat = options.colorScheme == .minimal ? 1.0 : (0.35 + 0.65 * identity)
            write("<rect x=\"\(SvgNum.nf(x))\" y=\"1\" width=\"\(SvgNum.nf(cellW))\" height=\"\(SvgNum.nf(geo.railHeight - 2))\" \(svgColor(base, a))/>\n")
            if identity >= 1.0 {
                let top = consensusColorExport(consensus: consensus, identity: 1.0, scheme: options.colorScheme, dark: dark)
                write("<rect x=\"\(SvgNum.nf(x))\" y=\"0\" width=\"\(SvgNum.nf(cellW))\" height=\"2\" \(svgColor(top, 1.0))/>\n")
            }
        }
        write("<line x1=\"0\" y1=\"\(SvgNum.nf(geo.railHeight))\" x2=\"\(SvgNum.nf(width))\" y2=\"\(SvgNum.nf(geo.railHeight))\" stroke=\"\(Self.hex(Minimal.border(dark: dark)))\" stroke-width=\"0.5\"/>\n")
        flushBuffer()

        // 2. 标尺
        write("<rect x=\"0\" y=\"\(SvgNum.nf(geo.railHeight))\" width=\"\(SvgNum.nf(width))\" height=\"\(SvgNum.nf(geo.rulerHeight))\" fill=\"\(Self.hex(Minimal.card(dark: dark)))\"/>\n")
        for c in 0..<cols.count {
            let col = cols.lowerBound + c
            if col % 10 == 0 {
                let x = nameW + CGFloat(c) * cellW
                let label = "\(col + 1)"
                write("<text x=\"\(SvgNum.nf(x + cellW))\" y=\"\(SvgNum.nf(geo.railHeight + geo.rulerHeight - 5))\" font-family=\"sans-serif\" font-size=\"\(SvgNum.nf(geo.rulerHeight - 9))\" fill=\"\(Self.hex(Minimal.textMuted(dark: dark)))\" text-anchor=\"end\">\(escapeXML(label))</text>\n")
                write("<line x1=\"\(SvgNum.nf(x))\" y1=\"\(SvgNum.nf(geo.railHeight))\" x2=\"\(SvgNum.nf(x))\" y2=\"\(SvgNum.nf(height))\" stroke=\"\(Self.hex(Minimal.border(dark: dark)))\" stroke-width=\"0.5\"/>\n")
            }
        }
        flushBuffer()

        // 3. 共识行
        if geo.showConsensus {
            let consY = geo.topBarHeight
            write("<rect x=\"0\" y=\"\(SvgNum.nf(consY))\" width=\"\(SvgNum.nf(width))\" height=\"\(SvgNum.nf(geo.consensusHeight))\" fill=\"\(Self.hex(Minimal.card(dark: dark)))\"/>\n")
            write("<text x=\"8\" y=\"\(SvgNum.nf(consY + geo.consensusHeight - 4))\" font-family=\"sans-serif\" font-size=\"\(SvgNum.nf(geo.fontSize - 1))\" fill=\"\(Self.hex(Minimal.text(dark: dark)))\">\(L.s.exportConsensusLabel)</text>\n")
            for c in 0..<cols.count {
                let col = cols.lowerBound + c
                guard col < stats.columnCount else { continue }
                let res = stats.consensus[col]
                let identity = stats.identity[col]
                let x = nameW + CGFloat(c) * cellW
                if options.colorScheme == .minimal {
                    if identity >= 1.0 {
                        write("<rect x=\"\(SvgNum.nf(x))\" y=\"\(SvgNum.nf(consY))\" width=\"\(SvgNum.nf(cellW))\" height=\"\(SvgNum.nf(cellH))\" \(svgColor(Minimal.chartColor(identity: 1.0, dark: dark), 0.14))/>\n")
                    } else if identity > 0.5 {
                        write("<rect x=\"\(SvgNum.nf(x))\" y=\"\(SvgNum.nf(consY))\" width=\"\(SvgNum.nf(cellW))\" height=\"\(SvgNum.nf(cellH))\" \(svgColor(Minimal.chartColor(identity: 0.5, dark: dark), 0.10))/>\n")
                    }
                } else {
                    let base = consensusColorExport(consensus: res, identity: identity, scheme: options.colorScheme, dark: dark)
                    write("<rect x=\"\(SvgNum.nf(x))\" y=\"\(SvgNum.nf(consY))\" width=\"\(SvgNum.nf(cellW))\" height=\"\(SvgNum.nf(cellH))\" \(svgColor(base, 0.30))/>\n")
                }
                let resChar = escapeXML(String(UnicodeScalar(res)))
                write("<text x=\"\(SvgNum.nf(x + cellW/2))\" y=\"\(SvgNum.nf(consY + cellH - 4))\" font-family=\"monospace\" font-size=\"\(SvgNum.nf(geo.fontSize - 1))\" fill=\"\(Self.hex(Minimal.text(dark: dark)))\" text-anchor=\"middle\">\(resChar)</text>\n")
            }
        }
        flushBuffer()

        // 4. 名称列
        let nameY = geo.dataY
        write("<rect x=\"0\" y=\"\(SvgNum.nf(nameY))\" width=\"\(SvgNum.nf(nameW))\" height=\"\(SvgNum.nf(height - nameY))\" fill=\"\(Self.hex(Minimal.card(dark: dark)))\"/>\n")
        write("<g clip-path=\"url(#nameClip)\">\n")
        for r in 0..<rows.count {
            let row = rows.lowerBound + r
            guard row < alignment.seqCount else { continue }
            let y = nameY + CGFloat(r) * cellH
            let rowNum = "\(row + 1)"
            write("<text x=\"26\" y=\"\(SvgNum.nf(y + cellH - 4))\" font-family=\"monospace\" font-size=\"\(SvgNum.nf(geo.fontSize - 2))\" fill=\"\(Self.hex(Minimal.textFaint(dark: dark)))\" text-anchor=\"end\">\(escapeXML(rowNum))</text>\n")
            let name = escapeXML(alignment.sequences[row].name)
            write("<text x=\"28\" y=\"\(SvgNum.nf(y + cellH - 4))\" font-family=\"sans-serif\" font-size=\"\(SvgNum.nf(geo.fontSize - 1))\" fill=\"\(Self.hex(Minimal.text(dark: dark)))\">\(name)</text>\n")
        }
        write("</g>\n")
        flushBuffer()

        // 5. 残基
        for r in 0..<rows.count {
            let row = rows.lowerBound + r
            guard row < alignment.seqCount else { continue }
            let y = nameY + CGFloat(r) * cellH
            let seq = alignment.sequences[row]
            if r % 2 == 0 {
                write("<rect x=\"\(SvgNum.nf(nameW))\" y=\"\(SvgNum.nf(y))\" width=\"\(SvgNum.nf(width - nameW))\" height=\"\(SvgNum.nf(cellH))\" fill=\"\(Self.hex(Minimal.card(dark: dark)))\"/>\n")
            }
            for c in 0..<cols.count {
                let col = cols.lowerBound + c
                guard col < seq.residues.count else { continue }
                let res = seq.residues[col]
                let x = nameW + CGFloat(c) * cellW
                if res == 0x2D {
                    write("<rect x=\"\(SvgNum.nf(x))\" y=\"\(SvgNum.nf(y))\" width=\"\(SvgNum.nf(cellW))\" height=\"\(SvgNum.nf(cellH))\" \(svgColor(Minimal.gapTint(dark: dark), 0.16))/>\n")
                    let rc = escapeXML(String(UnicodeScalar(res)))
                    write("<text x=\"\(SvgNum.nf(x + cellW/2))\" y=\"\(SvgNum.nf(y + cellH - 4))\" font-family=\"monospace\" font-size=\"\(SvgNum.nf(geo.fontSize))\" fill=\"\(Self.hex(Minimal.textMuted(dark: dark)))\" text-anchor=\"middle\">\(rc)</text>\n")
                    continue
                }
                let colorIdx = colorMatrix[r * cols.count + c]
                let palette = ColorResolver.palette(options.colorScheme, index: Int(colorIdx), dark: dark)
                write("<rect x=\"\(SvgNum.nf(x))\" y=\"\(SvgNum.nf(y))\" width=\"\(SvgNum.nf(cellW))\" height=\"\(SvgNum.nf(cellH))\" \(svgColor(palette.bg, palette.bg.alphaComponent))/>\n")
                let rc = escapeXML(String(UnicodeScalar(res)))
                write("<text x=\"\(SvgNum.nf(x + cellW/2))\" y=\"\(SvgNum.nf(y + cellH - 4))\" font-family=\"monospace\" font-size=\"\(SvgNum.nf(geo.fontSize))\" fill=\"\(Self.hex(palette.fg))\" text-anchor=\"middle\">\(rc)</text>\n")
            }
            flushBuffer()
        }

        // 6. 名称列分隔线
        write("<line x1=\"\(SvgNum.nf(nameW))\" y1=\"0\" x2=\"\(SvgNum.nf(nameW))\" y2=\"\(SvgNum.nf(height))\" stroke=\"\(Self.hex(Minimal.border(dark: dark)))\" stroke-width=\"1\"/>\n")
        write("</svg>")
        flushBuffer()

        guard !chunks.isEmpty, !buffer.isEmpty || chunks.count > 1 else {
            throw CoreError.format("SVG 生成结果为空")
        }
        var data = Data()
        data.reserveCapacity(chunks.reduce(0) { $0 + $1.count })
        for chunk in chunks { data.append(chunk) }
        return data
    }

    // MARK: - 辅助

    /// 导出行/列范围（仅导出选中区域时生效）。
    /// 选区可能已过期（行/列被删除后仍持有旧索引）：直接构造
    /// `max(0, lo)...min(hi, maxRow)` 会得到上界小于下界的非法 ClosedRange
    /// 直接崩溃，这里统一钳制到有效区间。
    private static func effectiveRowRange(_ alignment: Alignment, _ options: ExportOptions) -> ClosedRange<Int> {
        guard alignment.seqCount > 0 else { return 0...0 }
        let maxRow = alignment.seqCount - 1
        guard let r = options.rowRange else { return 0...maxRow }
        let lo = min(max(0, r.lowerBound), maxRow)
        let hi = min(max(lo, r.upperBound), maxRow)
        return lo...hi
    }

    private static func effectiveColRange(_ alignment: Alignment, _ options: ExportOptions) -> ClosedRange<Int> {
        guard alignment.length > 0 else { return 0...0 }
        let maxCol = alignment.length - 1
        guard let c = options.colRange else { return 0...maxCol }
        let lo = min(max(0, c.lowerBound), maxCol)
        let hi = min(max(lo, c.upperBound), maxCol)
        return lo...hi
    }

    /// 共识色（与画布 consensusColor 一致）：极简 = 灰阶一致度；其他 = 共识残基配色色
    private static func consensusColorExport(consensus: UInt8, identity: Double, scheme: ColorScheme, dark: Bool = false) -> NSColor {
        if scheme == .minimal {
            return Minimal.chartColor(identity: identity, dark: dark)
        }
        if consensus == 0x2D { return Minimal.gapTint(dark: dark) }
        let idx = ColorComputer.colorIndex(for: consensus, scheme: scheme)
        return ColorResolver.palette(scheme, index: Int(idx), dark: dark).bg
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
