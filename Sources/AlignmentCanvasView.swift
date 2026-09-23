//  AlignmentCanvasView.swift
//  SeqAlignMac — 自定义 NSView 高性能对齐画布（虚拟滚动）
//
//  设计要点：
//  - 共识统计缓存（2.3）
//  - 暗色模式语义化背景（3.3）
//  - 序列名截断省略号（3.4）
//  - 标尺数字右对齐 + 缩放 + 垂直网格线（3.5）
//  - 真实等宽字宽 / 字体度量基线（4.5）
//  - 空位非颜色线索 + 高对比模式（4.4）
//  - 方向键键盘导航（4.3）
//  - 名称区拖拽光标提示（4.6）
//  - 列块选区统一强调色（4.8）
//  渲染回归修复（2026-08-09）：
//  - draw(at:) 在 flipped 视图中以点作为行片段原点而非基线；
//    原 baseline 公式导致文字下沉并被下一行背景覆盖。
//    改用 draw(in:) 让 Core Text 在单元格内自动居中绘制。

import AppKit
import CoreText

// MARK: - 选区范围（用于「复制选中区域」）

/// Equatable：选区上报去重需要值比较
struct SelectionRange: Equatable {
    var rowStart: Int
    var rowEnd: Int   // 含
    var colStart: Int
    var colEnd: Int   // 含
}

// MARK: - 对齐画布视图

final class AlignmentCanvasView: NSView {
    // 数据
    var alignment: Alignment? {
        didSet {
            needsDisplay = true
            updateContentSize()
            // 仅当 alignment 对象引用变化时才重置共识缓存：
            // updateNSView 每次设置 canvas.alignment = alignment（同一对象）
            // 若都触发 didSet 重置缓存，共识会被反复重算。对于频次并列的列
            // （如示例数据最后一列 G=2, A=2），Dictionary.max(by:) 在不同字典实例
            // 间迭代顺序可能不同，从而返回不同的共识残基。
            // 就地编辑（原地改同一 Alignment 实例）时不走 didSet，而是由 revision
            // 变化在 ensureStats 中自动失效缓存，因此这里不漏判。
            if oldValue !== alignment {
                cachedStats = nil
                cachedStatsAlign = nil
                cachedStatsRevision = .max
            }
        }
    }
    var colorScheme: ColorScheme = .defaultNucleotide {
        didSet { needsDisplay = true }
    }
    var showConsensus: Bool = true {
        didSet { needsDisplay = true; updateContentSize() }
    }
    var highContrast: Bool = false {
        didSet { needsDisplay = true }
    }
    var fontSize: CGFloat = 13 {
        didSet {
            recomputeMetrics()
            needsDisplay = true
            updateContentSize()
        }
    }

    // 选区
    var selectedRow: Int? = nil
    var selectedCol: Int? = nil
    /// 独立选区锚点——扩展选区时不随光标更新而漂移
    private var selectionAnchor: (row: Int, col: Int)? = nil
    var selectionRect: NSRect? = nil
    /// 选区的行列范围（事实来源）：selectionRect 存的是绝对像素，
    /// 缩放/改名称列宽后会错位；行列范围稳定，绘制时再换算像素。
    private var selectionCellRange: (rows: ClosedRange<Int>, cols: ClosedRange<Int>)? = nil
    var isColumnBlockSelection: Bool = false  // Option+拖拽列块选择
    var columnBlockStart: Int = 0
    var columnBlockEnd: Int = 0
    var searchHits: [SearchHit] = []
    var currentHitIndex: Int = -1

    // 回调
    var onPositionChanged: ((Int, Int) -> Void)? = nil
    var onFontSizeChanged: ((CGFloat) -> Void)? = nil
    var onRenameRequest: ((Int) -> Void)? = nil
    var onDeleteRequest: ((Int) -> Void)? = nil
    var onMoveRequest: ((Int, Int) -> Void)? = nil
    var onContextAction: ((ContextAction) -> Void)? = nil
    /// 复制完成反馈（Cmd+C 后 Toast 提示复制了多少行 × 列，携带语义 kind）
    var onCopied: ((String, ToastKind) -> Void)? = nil
    /// 选区变化上报（导出「仅选区」/ 引物「从选区填入」用）
    var onSelectionChanged: ((SelectionRange?) -> Void)? = nil

    // 拖拽排序
    private var isDraggingSequence: Bool = false
    private var dragSourceRow: Int? = nil
    private var dragIndicatorRow: Int? = nil

    // 共识统计缓存（2.3：避免每次滚动全量重算）
    // 失效判定同时比较对象引用与 revision：就地编辑（原地改同一个 Alignment 实例）
    // 不会触发 alignment 的 didSet，但 revision 会自增，据此可正确失效。
    private var cachedStats: ColumnStats? = nil
    private var cachedStatsAlign: Alignment? = nil
    private var cachedStatsRevision: UInt64 = .max
    private var cachedStatsMode: ConsensusMode = .majority
    /// 编辑命令上报的脏列集合（经 updateNSView 从 Workspace 取走），ensureStats 消费
    var pendingDirtyColumns: Set<Int>? = nil

    // 单元格尺寸 — 行距 1.4
    // 单元格宽度取真实等宽字宽，避免魔法系数导致的稀疏/重叠（4.5）
    // 缓存：fontSize 变化时随字体一起重建，避免 draw 热路径每格重复测量文本尺寸（性能瓶颈）。
    private var cachedCellWidth: CGFloat = 0
    private var cellWidth: CGFloat { cachedCellWidth }
    private var cellHeight: CGFloat { fontSize * 1.4 }
    /// 名称列宽度：可在画布内拖动分隔线调整，宽度持久化到 UserDefaults（修复「序列名截断、无法完整显示」）
    var nameColWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "SeqAlignMac.nameColWidth")
        return saved > 0 ? CGFloat(saved) : 150
    }()
    /// 分隔线可拖拽判定区半宽（px）—— 仅在名称列一侧发起改宽
    private let resizeZoneWidth: CGFloat = 5
    /// 数据侧改宽热区收窄到 2px，避免侵入首列单元格选择区
    private let dataSideResizeWidth: CGFloat = 2
    private let minNameColWidth: CGFloat = 80
    /// 名称列最大宽度：增大到 2000 以适应超长序列名（如基因组注释型 FASTA 标题行）
    private let maxNameColWidth: CGFloat = 2000

    // MARK: - 名称列固定（冻结列）
    // 视口水平滚动越过名称带后，名称列以「固定带」形式钉在视口左缘继续显示：
    // 绘制时在固定带位置覆写名称内容，命中判定（重命名/排序/改宽/菜单）重映射过去。
    // 固定带在文档坐标系中随滚动原点移动，因此同一套文档坐标命中逻辑无需换算行列。

    /// 固定带在视图（文档）坐标系中的 x 区间；nil = 视口左缘尚未滚过名称带（原始布局）
    private var pinnedNamesRange: ClosedRange<CGFloat>? {
        guard alignment != nil, let clip = enclosingScrollView?.contentView else { return nil }
        let visMinX = clip.bounds.origin.x
        guard visMinX >= nameColWidth else { return nil }
        return visMinX...(visMinX + nameColWidth)
    }

    /// 名称列当前实际占据的 x 区间（未滚过 = 原始带 [0, nameColWidth]；滚过 = 固定带）
    private var activeNamesRange: ClosedRange<CGFloat> {
        pinnedNamesRange ?? ((0 as CGFloat)...nameColWidth)
    }

    /// 名称列右边界（文档坐标）：分隔线 / 改宽热区 / 轨道起点的锚点
    private var namesBoundaryX: CGFloat {
        pinnedNamesRange?.upperBound ?? nameColWidth
    }

    // 固定带滚动重绘状态：AppKit 滚动只失效新暴露区域，固定带像素必须自行失效
    private var scrollObserverInstalled = false
    private var lastPinnedStrip: NSRect? = nil
    private var lastHadPinnedStrip = false

    // MARK: - 渲染性能（P1 批量字形 / P2 密度模式 / P4 后台列统计 / P5 快照缓存）

    /// 密度阈值——列宽低于该值时字形已不可读，跳过全部文字绘制只画色块
    private static let glyphDensityThreshold: CGFloat = 6.0

    /// CoreText 字形缓存（按当前残基字体构建）。滚动帧的残基文字按色组
    /// drawGlyphs 批量绘制，而非每格一次 NSString.draw（满帧 ~8800 次文本调用）
    private var glyphCacheFontName: String? = nil
    private var glyphCacheFontSize: CGFloat = 0
    private var glyphCTFont: CTFont? = nil
    private var glyphCGFont: CGFont? = nil
    private var glyphIds: [CGGlyph] = []
    private var glyphAdvances: [CGFloat] = []
    private var glyphAscent: CGFloat = 0
    private var glyphDescent: CGFloat = 0

    /// 差异模式参考行快照缓存（行号 + revision），不再每帧深拷贝整行
    private var cachedDiffRefRow: (row: Int, revision: UInt64, bytes: [UInt8]?)? = nil

    /// 全量列统计后台队列（同一时刻只允许一个计算在飞）。
    /// 全表扫描不在首帧主线程同步执行——O(行×列) 会冻结界面数秒
    private let statsQueue = DispatchQueue(label: "seqalign.canvas.stats", qos: .userInitiated)
    private var statsComputing = false
    private var isResizingNameCol: Bool = false
    private var rulerHeight: CGFloat { 24 }
    private var consensusHeight: CGFloat { showConsensus ? (cellHeight + 4) : 0 }

    /// 保守度概览轨道（记忆点）：常驻热力条，每列编码一致度，可点击跳转 + 悬停 peek
    private let conservationRailHeight: CGFloat = 12
    /// 顶部总高度 = 轨道 + 标尺
    private var topBarHeight: CGFloat { conservationRailHeight + rulerHeight }
    /// 聚焦变暗模式：存在选区时淡化非选中区域（设置可开关）
    var focusDimMode: Bool = false
    /// 差异模式参考行（nil = 关闭）：非参考行中与参考相同的残基淡化显示
    var differenceReferenceRow: Int? = nil {
        didSet { needsDisplay = true }
    }
    /// 轨道悬停列（用于 peek tooltip），nil 表示不在轨道悬停
    private var hoverColumn: Int? = nil
    /// 轨道拖动中（点击/拖动轨道跳转列）
    private var isScrubbingRail: Bool = false
    /// 鼠标是否靠近名称列分隔线（hover 时手柄加宽，强化可抓握语义）
    private var isNearNameResize: Bool = false
    /// 当前是否拥有焦点（用于绘制细焦点环，让用户知道方向键可用）
    private var hasFocus: Bool = false

    // 字体 —  等宽优先 SF Mono / Menlo / Source Code Pro；中文标签用苹方
    private var monoFont: NSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private var labelFont: NSFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    private var boldFont: NSFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    /// 中文标签字体（苹方 PingFang SC）：recomputeMetrics 时缓存，
    /// 旧计算属性每次访问都做 PostScript 名查找，且被行绘制循环调用
    private var chineseLabelFontCached: NSFont = NSFont(name: "PingFangSC-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12)
    private var chineseLabelFont: NSFont { chineseLabelFontCached }

    override var isFlipped: Bool { true }

    /// 系统浅/深色切换后自动重绘（颜色在 draw 时按当前外观现取，需要触发时机）
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installScrollObserverIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 监听 clip view 的 bounds 变化：固定带钉在视口左缘，滚动时 AppKit 只重绘
    /// 新暴露区域，固定带自身（旧位置像素 + 新位置像素 + 随垂直滚动变化的行）
    /// 必须在这里显式失效
    private func installScrollObserverIfNeeded() {
        guard window != nil, !scrollObserverInstalled,
              let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: clip)
        scrollObserverInstalled = true
    }

    @objc private func clipBoundsChanged(_ note: Notification) {
        if let pin = pinnedNamesRange {
            let strip = NSRect(x: pin.lowerBound - 2, y: 0, width: nameColWidth + 4, height: bounds.height)
            if lastHadPinnedStrip, let old = lastPinnedStrip {
                setNeedsDisplay(old.union(strip))
            } else {
                // 刚越过名称带进入固定态：阈值附近被覆写过的新旧像素一并恢复
                needsDisplay = true
            }
            lastPinnedStrip = strip
            lastHadPinnedStrip = true
        } else if lastHadPinnedStrip {
            if let old = lastPinnedStrip {
                // 从固定态滚回原始态：旧固定带覆写的像素按残基内容恢复
                setNeedsDisplay(old.insetBy(dx: -2, dy: 0))
            }
            lastPinnedStrip = nil
            lastHadPinnedStrip = false
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { hasFocus = true; needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { hasFocus = false; needsDisplay = true; return true }

    /// 当前视图解析到的外观是否为深色（用于切换品牌强调色与数据色板）
    private var isDarkAppearance: Bool {
        effectiveAppearance.isDark()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = false
        recomputeMetrics()
        // 启用右键菜单
        menu = nil
        setupAccessibility()
    }

    // MARK: - 无障碍（VoiceOver）

    /// 将画布暴露为可访问分组，光标移动时播报位置/残基/一致度；
    /// 并将「复制选中区域」暴露为 AX 自定义动作（P14 / 研究员 P22）。
    private func setupAccessibility() {
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.group)
        self.setAccessibilityLabel("序列比对画布")
        self.setAccessibilityHelp("使用方向键移动光标，Option+方向键框选区域，点击顶部保守度轨道跳转列。Cmd+A 全选后 Cmd+C 复制选中区域。")
        let copyAction = NSAccessibilityCustomAction(name: "复制选中区域", target: self, selector: #selector(accessibilityCopy(_:)))
        self.setAccessibilityCustomActions([copyAction])
    }

    @objc private func accessibilityCopy(_ sender: Any?) -> Bool {
        copySelection(nil)
        return true
    }

    // MARK: - 复制 / 全选（Cmd+C / Cmd+A 键盘链路）

    /// 画布复制：把当前选区转 FASTA 写入剪贴板。
    /// 无显式选区时复制光标所在整行并提示。
    func copySelection(_ sender: Any?) {
        guard let align = alignment else { return }
        let hasExplicit = isColumnBlockSelection || selectionRect != nil || (selectedRow != nil && selectedCol != nil)
        var range = currentSelectionRange()
        if !hasExplicit {
            if let r = selectedRow, r < align.seqCount {
                range = SelectionRange(rowStart: r, rowEnd: r, colStart: 0, colEnd: max(0, align.length - 1))
            } else {
                onCopied?("请先在画布中选择区域", .warning)
                return
            }
        }
        let rEnd = min(range.rowEnd, align.seqCount - 1)
        let cEnd = min(range.colEnd, align.length - 1)
        guard rEnd >= range.rowStart, cEnd >= range.colStart else { return }

        // 字节缓冲聚合构造
        var lines: [UInt8] = []
        lines.reserveCapacity((rEnd - range.rowStart + 1) * (cEnd - range.colStart + 1 + 16))
        for row in range.rowStart...rEnd {
            let seq = align.sequences[row]
            lines.append(contentsOf: ">\(seq.name)\n".utf8)
            for col in range.colStart...cEnd {
                lines.append(col < seq.residues.count ? seq.residues[col] : 0x2D)
            }
            lines.append(0x0A) // \n
        }
        let text = String(decoding: lines, as: UTF8.self)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let rows = rEnd - range.rowStart + 1
        let cols = cEnd - range.colStart + 1
        if !hasExplicit {
            onCopied?("已复制光标所在行（\(cols) 列）", .success)
        } else {
            onCopied?("已复制 \(rows) 行 × \(cols) 列", .success)
        }
    }

    /// Cmd+A：全选当前比对整块（P4 建议 4），便于一键复制全部
    func selectAllSelection(_ sender: Any?) {
        guard let align = alignment, align.seqCount > 0, align.length > 0 else { return }
        isColumnBlockSelection = false
        setSelectionRect(NSRect(
            x: nameColWidth,
            y: topBarHeight + consensusHeight,
            width: CGFloat(align.length) * cellWidth,
            height: CGFloat(align.seqCount) * cellHeight
        ))
        selectedRow = 0
        selectedCol = 0
        onSelectionChanged?(SelectionRange(rowStart: 0, rowEnd: align.seqCount - 1, colStart: 0, colEnd: align.length - 1))
        needsDisplay = true
    }

    /// 光标变化后向 VoiceOver 播报当前单元格信息
    private func announceCursor() {
        guard let align = alignment else { return }
        let r = selectedRow ?? 0
        let c = selectedCol ?? 0
        guard r < align.seqCount, c < align.length else { return }
        let residues = align.sequences[r].residues
        let byte = (c < residues.count) ? residues[c] : 0
        let resChar = (byte == 0x2D) ? "空位" : String(UnicodeScalar(byte))
        var identityStr = ""
        if let stats = cachedStats, c < stats.columnCount {
            identityStr = "，一致度 \(Int(round(stats.identity[c] * 100)))%"
        }
        let value = "行 \(r + 1) 列 \(c + 1)，残基 \(resChar)\(identityStr)"
        self.setAccessibilityValue(value)
        // 光标变化后通知 VoiceOver 播报（焦点在画布时自动朗读 valueChanged）
        NSAccessibility.post(element: self, notification: .valueChanged, userInfo: nil)
    }

    /// 重建字体与单元格宽度缓存（fontSize 变化或初始化时调用）
    private func recomputeMetrics() {
        // 字号变化后按行列范围重建选区像素矩形，避免选区错位、导出「仅选区」取错数据
        if let cells = selectionCellRange {
            selectionRect = rect(for: cells)
        }
        monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        labelFont = NSFont.systemFont(ofSize: fontSize - 1, weight: .regular)
        boldFont = NSFont.systemFont(ofSize: fontSize - 1, weight: .semibold)
        cachedCellWidth = max(4, ("A" as NSString).size(withAttributes: [.font: monoFont]).width)
        glyphCacheFontName = nil   // 字体已变，字形缓存随下一帧重建
    }

    func updateContentSize() {
        guard let align = alignment else { return }
        let totalWidth = nameColWidth + CGFloat(align.length) * cellWidth
        let totalHeight = topBarHeight + consensusHeight + CGFloat(align.seqCount) * cellHeight
        setFrameSize(NSSize(width: totalWidth, height: totalHeight))
        // 名称列宽度变化后同步刷新滚动条（反射内容尺寸）
        if let sv = enclosingScrollView {
            sv.reflectScrolledClipView(sv.contentView)
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        installScrollObserverIfNeeded()   // viewDidMoveToWindow 时机早于挂入 scrollView 时的兜底
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 语义化背景：跟随浅色/深色外观（修复暗色模式白块，3.3）
        Minimal.surface(dark: self.isDarkAppearance).setFill()
        dirtyRect.fill()

        guard let align = alignment else {
            // 空状态交由 SwiftUI 覆盖层渲染（ContentView.EmptyStateView），
            // 此处仅绘制语义背景，避免与覆盖层双重绘制造成死灰文字残留。
            return
        }

        ctx.textMatrix = CGAffineTransform.identity
        let clipRect = dirtyRect

        // 计算可见范围
        // 防闪退：窗口缩小时 dirtyRect 可能不覆盖数据区，
        // 导致 maxCol/maxRow 为负数。Swift Range 要求 lowerBound <= upperBound，
        // 0..<(-1) 会 fatal error。用 max(minCol, ...) / max(minRow, ...) 钳制下界。
        let minCol = max(0, Int((clipRect.minX - nameColWidth) / cellWidth))
        let maxCol = max(minCol, min(align.length, Int((clipRect.maxX - nameColWidth) / cellWidth) + 1))
        let minRow = max(0, Int((clipRect.minY - topBarHeight - consensusHeight) / cellHeight))
        let maxRow = max(minRow, min(align.seqCount, Int((clipRect.maxY - topBarHeight - consensusHeight) / cellHeight) + 1))

        // 0.5 确保列统计可用（轨道与共识行共用，避免重复计算）
        ensureStats(align)
        // 0.6 保守度概览轨道（记忆点）
        drawConservationRail(ctx, align, minCol: minCol, maxCol: maxCol)
        // 0.6b 搜索命中概览（P15：轨道下沿叠加命中标记，可一眼看到命中分布；点击轨道可跳转）
        drawSearchOverview(ctx)
        // 0.6c 轨道悬停高亮下缘（#7：hover 时给轨道加一条高亮下缘，强化可交互暗示）
        if let col = hoverColumn {
            let x = nameColWidth + CGFloat(col) * cellWidth
            ctx.setStrokeColor(Minimal.primary(dark: self.isDarkAppearance).cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: x, y: conservationRailHeight))
            ctx.addLine(to: CGPoint(x: x + cellWidth, y: conservationRailHeight))
            ctx.strokePath()
        }

        // 1. 绘制位置标尺
        drawRuler(ctx, align, minCol: minCol, maxCol: maxCol)

        // 2. 绘制共识序列
        if showConsensus {
            drawConsensus(ctx, align, minCol: minCol, maxCol: maxCol)
        }

        // 3. 绘制序列名
        drawNames(ctx, align, minRow: minRow, maxRow: maxRow)

        // 4. 绘制残基
        drawResidues(ctx, align, minRow: minRow, maxRow: maxRow, minCol: minCol, maxCol: maxCol)

        // 5. 绘制选区
        drawSelection(ctx, align)

        // 6. 绘制列块选区（Option+拖拽）
        if isColumnBlockSelection {
            drawColumnBlockSelection(ctx, align)
        }

        // 7. 绘制搜索高亮（仅可视范围内的命中）
        drawSearchHighlights(ctx, align, minRow: minRow, maxRow: maxRow, minCol: minCol, maxCol: maxCol)

        // 8. 绘制拖拽指示线
        if isDraggingSequence, let dragRow = dragIndicatorRow {
            drawDragIndicator(ctx, row: dragRow)
        }

        // 9. 绘制名称列分隔线（issue 3：移除「可拖拽手柄」小药丸与两条横线，
        // 保留细分隔线 + hover/drag 调整宽度能力 —— 视觉更干净）
        ctx.setStrokeColor(Minimal.border(dark: self.isDarkAppearance).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: nameColWidth, y: 0))
        ctx.addLine(to: CGPoint(x: nameColWidth, y: bounds.height))
        ctx.strokePath()
        // hover 时把分隔线略加粗，作为「可拖动」的唯一视觉线索（替代原手柄）
        if isNearNameResize {
            ctx.setStrokeColor(Minimal.primary(dark: self.isDarkAppearance).cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: nameColWidth, y: 0))
            ctx.addLine(to: CGPoint(x: nameColWidth, y: bounds.height))
            ctx.strokePath()
        }

        // 10. 焦点环（Bug #3：画布为第一响应者时绘制细焦点环，让用户知道方向键可用）
        if hasFocus {
            ctx.setStrokeColor(Minimal.primary(dark: self.isDarkAppearance).withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: 0.5, y: 0.5))
            ctx.addLine(to: CGPoint(x: bounds.maxX - 0.5, y: 0.5))
            ctx.addLine(to: CGPoint(x: bounds.maxX - 0.5, y: bounds.maxY - 0.5))
            ctx.addLine(to: CGPoint(x: 0.5, y: bounds.maxY - 0.5))
            ctx.addLine(to: CGPoint(x: 0.5, y: 0.5))
            ctx.strokePath()
        }

        // 0.7 轨道悬停 peek tooltip（最上层）
        if let col = hoverColumn {
            drawColumnPeekTooltip(ctx, align, column: col)
        }

        // 11. 名称列固定带（最上层）：视口滚过名称带后钉在视口左缘重绘名称列
        if let pin = pinnedNamesRange {
            // 顶带（保守度轨道/标尺/共识行）是列对齐内容，固定带内以卡片底色覆盖，保持冻结列语义
            ctx.setFillColor(Minimal.card(dark: self.isDarkAppearance).cgColor)
            ctx.fill(CGRect(x: pin.lowerBound, y: 0, width: nameColWidth, height: topBarHeight + consensusHeight))
            drawNames(ctx, align, minRow: minRow, maxRow: maxRow, nameX: pin.lowerBound)
            // 右缘分隔线（hover 改宽时加粗提示，与原始带一致）
            ctx.setStrokeColor(Minimal.border(dark: self.isDarkAppearance).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: pin.upperBound, y: 0))
            ctx.addLine(to: CGPoint(x: pin.upperBound, y: bounds.height))
            ctx.strokePath()
            if isNearNameResize {
                ctx.setStrokeColor(Minimal.primary(dark: self.isDarkAppearance).cgColor)
                ctx.setLineWidth(2)
                ctx.move(to: CGPoint(x: pin.upperBound, y: 0))
                ctx.addLine(to: CGPoint(x: pin.upperBound, y: bounds.height))
                ctx.strokePath()
            }
        }
    }

    // MARK: - 绘制位置标尺

    private func drawRuler(_ ctx: CGContext, _ align: Alignment, minCol: Int, maxCol: Int) {
        let rulerY: CGFloat = conservationRailHeight
        let dark = self.isDarkAppearance
        // 标尺背景
        ctx.setFillColor(Minimal.card(dark: dark).cgColor)
        ctx.fill(CGRect(x: 0, y: rulerY, width: bounds.width, height: rulerHeight))

        let baseSize = labelFont.pointSize
        // 两档缩小字号 + 段落样式提升到循环外
        let smallFont = NSFont.systemFont(ofSize: max(7, baseSize - 3))
        let midFont = NSFont.systemFont(ofSize: max(8, baseSize - 1))
        let smallTextH = smallFont.ascender - smallFont.descender
        let midTextH = midFont.ascender - midFont.descender
        let baseTextH = labelFont.ascender - labelFont.descender
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let borderCG = Minimal.border(dark: dark).cgColor

        for col in minCol..<maxCol {
            if col % 10 == 0 || col == 0 {
                let x = nameColWidth + CGFloat(col) * cellWidth
                let label = "\(col + 1)"
                let digits = label.count
                // 大数字缩小字号，避免与相邻标号重叠（3.5）
                let font: NSFont = digits > 4 ? smallFont : (digits > 3 ? midFont : labelFont)
                let textH = digits > 4 ? smallTextH : (digits > 3 ? midTextH : baseTextH)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: Minimal.textMuted(dark: dark),
                    .paragraphStyle: paragraph
                ]
                // 在单元格内右对齐 + 垂直居中；避免 draw(at:) 基线语义在 flipped 视图中错位
                // issue 5：标尺列号也统一为「中部对齐」，与行号 / 名称 / 残基视觉同排
                (label as NSString).draw(in: CGRect(x: x,
                                     y: rulerY + max(0, (rulerHeight - textH) / 2),
                                     width: cellWidth,
                                     height: textH),
                         withAttributes: attrs)

                // 垂直网格线（贯穿数据区，辅助定位；每 10 列）
                ctx.setStrokeColor(borderCG)
                ctx.setLineWidth(0.5)
                ctx.move(to: CGPoint(x: x, y: rulerY))
                ctx.addLine(to: CGPoint(x: x, y: bounds.height))
                ctx.strokePath()
            }
        }
    }

    // MARK: - 保守度概览轨道（记忆点）

    /// 确保列统计已计算（轨道与共识行共用缓存，避免重复计算）
    /// 优先走增量路径——编辑命令上报的脏列集合非空且列数未变时只重算受影响列
    /// （单字符编辑将 O(n×m) 降为 O(n)）；空集 = 编辑不影响列统计（改名/排序），
    /// 直接复用现有统计；nil（范围未知）或首算 = 全量（单遍融合扫描）。
    private func ensureStats(_ align: Alignment) {
        let mode = AppSettings.consensusMode
        let modeChanged = cachedStatsMode != mode
        let stale = cachedStats == nil || cachedStatsAlign !== align || cachedStatsRevision != align.revision || modeChanged
        guard stale else { return }

        // 模式变化必须全量重算：增量路径只重算脏列，其余列会保留旧模式的共识字形。
        if !modeChanged, let dirty = pendingDirtyColumns, let current = cachedStats,
           cachedStatsAlign === align, current.columnCount == align.length {
            pendingDirtyColumns = nil
            if dirty.isEmpty {
                // 编辑只影响行序/名称等元数据，列统计保持有效
                cachedStatsRevision = align.revision
                cachedStatsMode = mode
                return
            }
            // 少量脏列走增量（单字符编辑 O(n)）；大范围粘贴的增量成本
            // O(脏列×行数)，超过阈值退回后台全量，避免主线程长任务
            if dirty.count <= Self.maxIncrementalDirtyColumns {
                cachedStats = AlignmentStatsCalculator.computeColumnStats(align, prevStats: current, dirtyColumns: dirty, mode: mode)
                cachedStatsRevision = align.revision
                cachedStatsMode = mode
                return
            }
        } else {
            pendingDirtyColumns = nil
        }

        // 全量统计移到后台；统计未就绪期间轨道/共识行/minimal 配色降级绘制
        scheduleStatsComputation(align, mode: mode)
    }

    /// 增量重算的脏列数上限：超过即视为大范围编辑，转后台全量
    private static let maxIncrementalDirtyColumns = 64

    /// 后台全量列统计。draw 只负责发现过期并调度（同一时刻至多一个在飞）；
    /// 完成后回主线程校验——文档/修订/模式仍一致才采用并整帧重绘，否则重新调度，
    /// 统计不至于停在过期状态。计算经 Alignment 内部锁与主线程编辑互斥。
    private func scheduleStatsComputation(_ align: Alignment, mode: ConsensusMode) {
        guard !statsComputing else { return }
        statsComputing = true
        statsQueue.async { [weak self] in
            let result = AlignmentStatsCalculator.computeColumnStats(align, mode: mode)
            // 计算结束后再取 revision：fusedScan 单次持锁，结果与该锁窗口内的修订一致
            let revision = align.revision
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.statsComputing = false
                guard self.alignment === align else { return }   // 期间已切换文档
                if align.revision == revision, AppSettings.consensusMode == mode {
                    self.cachedStats = result
                    self.cachedStatsAlign = align
                    self.cachedStatsRevision = revision
                    self.cachedStatsMode = mode
                    self.setNeedsDisplay(self.bounds)
                } else {
                    self.scheduleStatsComputation(align, mode: AppSettings.consensusMode)
                }
            }
        }
    }

    /// 搜索命中概览（P15）：在顶部保守度轨道下沿绘制命中列标记。
    /// 同一列多个命中合并为一根标记；点击/拖动轨道跳转列的逻辑已与命中位置复用。
    /// 名称类命中不投影到列标记（不表达具体列位置）。
    private func drawSearchOverview(_ ctx: CGContext) {
        guard !searchHits.isEmpty else { return }
        var hitCols = Set<Int>()
        for hit in searchHits where !hit.isNameHit { hitCols.insert(hit.position) }
        ctx.setFillColor(Minimal.primary(dark: self.isDarkAppearance).withAlphaComponent(0.85).cgColor)
        for col in hitCols {
            let x = nameColWidth + CGFloat(col) * cellWidth + cellWidth / 2 - 1
            ctx.fill(CGRect(x: x, y: conservationRailHeight - 3, width: 2, height: 3))
        }
    }

    private func drawConservationRail(_ ctx: CGContext, _ align: Alignment, minCol: Int, maxCol: Int) {
        let railY: CGFloat = 0
        let dark = self.isDarkAppearance
        // 轨道底
        ctx.setFillColor(Minimal.card(dark: dark).cgColor)
        ctx.fill(CGRect(x: 0, y: railY, width: bounds.width, height: conservationRailHeight))

        guard let stats = cachedStats else { return }
        // 每列 withAlphaComponent 新建颜色改为缓存——极简方案按灰阶档位缓存；
        // 其他方案按（色板索引 × α 量化档）缓存，一帧内每档只做一次 NSColor→CGColor
        var minimalCGCache: [Int: CGColor] = [:]
        var paletteCGCache: [Int: CGColor] = [:]
        func quantizedCG(_ color: NSColor, alpha: CGFloat, paletteKey: Int? = nil) -> CGColor {
            let key = Int((alpha * 100).rounded())
            if let paletteKey {
                let combined = paletteKey * 101 + key
                if let cached = paletteCGCache[combined] { return cached }
                let cg = color.withAlphaComponent(CGFloat(key) / 100.0).cgColor
                paletteCGCache[combined] = cg
                return cg
            }
            if let cached = minimalCGCache[key] { return cached }
            let cg = color.withAlphaComponent(CGFloat(key) / 100.0).cgColor
            minimalCGCache[key] = cg
            return cg
        }
        func baseCG(_ consensus: UInt8, identity: Double) -> CGColor {
            if colorScheme == .minimal {
                return quantizedCG(Minimal.chartColor(identity: identity, dark: dark), alpha: 1.0)
            }
            if consensus == 0x2D { return Minimal.gapTint(dark: dark).cgColor }
            let idx = Int(ColorComputer.colorIndex(for: consensus, scheme: colorScheme))
            return quantizedCG(ColorResolver.palette(colorScheme, index: idx, dark: dark).bg,
                               alpha: 0.35 + 0.65 * identity, paletteKey: idx)
        }

        // 钳制上界不低于 minCol，防止 Range 下界 > 上界闪退
        let colUpper = max(minCol, min(maxCol, stats.columnCount))
        for col in minCol..<colUpper {
            let identity = stats.identity[col]
            let consensus = stats.consensus[col]
            let x = nameColWidth + CGFloat(col) * cellWidth
            // 跟随所选配色（极简=灰阶；其他=共识残基配色色，透明度随一致度衰减，
            // 保留「一致度越高越实、越低越淡」的原始语义）
            ctx.setFillColor(baseCG(consensus, identity: identity))
            ctx.fill(CGRect(x: x, y: railY + 1, width: cellWidth, height: conservationRailHeight - 2))
            // 完全保守的列加一道亮顶线，强调"高保守区"
            if identity >= 1.0 {
                ctx.setFillColor(baseCG(consensus, identity: 1.0))
                ctx.fill(CGRect(x: x, y: railY, width: cellWidth, height: 2))
            }
        }

        // 轨道与标尺之间的细分隔线
        ctx.setStrokeColor(Minimal.border(dark: dark).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: 0, y: railY + conservationRailHeight))
        ctx.addLine(to: CGPoint(x: bounds.width, y: railY + conservationRailHeight))
        ctx.strokePath()
    }

    private func drawColumnPeekTooltip(_ ctx: CGContext, _ align: Alignment, column: Int) {
        guard let stats = cachedStats, column < stats.columnCount else { return }
        let cons = stats.consensus[column]
        let identity = stats.identity[column]
        let consChar = (cons == 0x2D) ? "—" : String(UnicodeScalar(cons))
        let text = "列 \(column + 1) · 共识 \(consChar) · 一致度 \(Int(identity * 100))%"
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Minimal.text(dark: self.isDarkAppearance)]
        let size = (text as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 8, padY: CGFloat = 5
        let tipW = size.width + padX * 2
        let tipH = size.height + padY * 2
        var tipX = nameColWidth + CGFloat(column) * cellWidth + cellWidth / 2 - tipW / 2
        tipX = max(4, min(tipX, bounds.width - tipW - 4))
        let tipY = conservationRailHeight + 2

        let tipRect = CGRect(x: tipX, y: tipY, width: tipW, height: tipH)
        Minimal.surface(dark: self.isDarkAppearance).setFill()
        let path = NSBezierPath(roundedRect: tipRect, xRadius: 6, yRadius: 6)
        path.fill()
        ctx.setStrokeColor(Minimal.borderStrong(dark: self.isDarkAppearance).cgColor)
        ctx.setLineWidth(1)
        path.stroke()

        (text as NSString).draw(in: CGRect(x: tipX + padX, y: tipY + padY, width: size.width, height: size.height),
                                withAttributes: attrs)
    }

    // MARK: - 绘制共识序列

    private func drawConsensus(_ ctx: CGContext, _ align: Alignment, minCol: Int, maxCol: Int) {
        // 复用 ensureStats 的判重逻辑，不在此内联重复
        ensureStats(align)
        guard let stats = cachedStats else { return }
        let dark = self.isDarkAppearance
        // 钳制上界不低于 minCol，防止 Range 下界 > 上界闪退
        let colUpper = max(minCol, min(maxCol, stats.columnCount))

        let consY = topBarHeight
        let consFont = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .medium)

        // 背景（与名称列同款 band，统一 controlSurface 体系的 card 灰阶）
        ctx.setFillColor(Minimal.card(dark: dark).cgColor)
        ctx.fill(CGRect(x: 0, y: consY, width: bounds.width, height: consensusHeight))

        let labelStr = "共识序列" as NSString
        // issue 4：标签改写为「共识序列」，让「每列共识残基」这层语义更直观；
        // 标签写「共识长度」，仅写「共识」表意不明。
        // issue 3：“共识序列”标签与序列名左对齐（序列名起点 x=28，右侧留 6pt
        // 边距），而不是与行号列（x:4..26）对齐。
        labelStr.draw(in: CGRect(x: 28, y: consY, width: nameColWidth - 28 - 6, height: consensusHeight),
                      withAttributes: [
                        .font: chineseLabelFont,
                        .foregroundColor: Minimal.text(dark: dark)
                      ])

        let attrs: [NSAttributedString.Key: Any] = [
            .font: consFont,
            .foregroundColor: Minimal.text(dark: dark)
        ]

        // 底色按 (方案, 色板索引/灰阶档) 预构造缓存，替代每列 withAlphaComponent
        let strongCG = Minimal.chartColor(identity: 1.0, dark: dark).withAlphaComponent(0.14).cgColor
        let midCG = Minimal.chartColor(identity: 0.5, dark: dark).withAlphaComponent(0.10).cgColor
        var schemeCGCache: [Int: CGColor] = [:]
        func consensusFillCG(_ res: UInt8, identity: Double) -> CGColor? {
            if colorScheme == .minimal {
                if identity >= 1.0 { return strongCG }
                if identity > 0.5 { return midCG }
                return nil
            }
            if res == 0x2D { return nil }
            let idx = Int(ColorComputer.colorIndex(for: res, scheme: colorScheme))
            if let cached = schemeCGCache[idx] { return cached }
            let cg = ColorResolver.palette(colorScheme, index: idx, dark: dark)
                .bg.withAlphaComponent(0.30).cgColor
            schemeCGCache[idx] = cg
            return cg
        }

        // issue 5：共识行残基垂直居中，与下方数据区残基基线一致
        let consTextH = consFont.ascender - consFont.descender

        for col in minCol..<colUpper {
            let res = stats.consensus[col]
            let identity = stats.identity[col]
            let x = nameColWidth + CGFloat(col) * cellWidth

            if let fill = consensusFillCG(res, identity: identity) {
                ctx.setFillColor(fill)
                ctx.fill(CGRect(x: x, y: consY, width: cellWidth, height: cellHeight))
            }

            // 密度模式——列宽过小时共识字形同样跳过，仅保留底色线索
            if cachedCellWidth >= Self.glyphDensityThreshold {
                let resChar = String(UnicodeScalar(res)) as NSString
                let consRect = CGRect(x: x, y: consY + max(0, (cellHeight - consTextH) / 2),
                                      width: cellWidth, height: consTextH)
                resChar.draw(in: consRect, withAttributes: attrs)
            }
        }
    }

    // MARK: - 绘制序列名

    /// 绘制序列名列。nameX = 名称带左缘（文档坐标）：原始布局传 0，
    /// 固定带绘制传固定带左缘（钉在视口左缘处的文档 x）。
    private func drawNames(_ ctx: CGContext, _ align: Alignment, minRow: Int, maxRow: Int,
                           nameX: CGFloat = 0) {
        let nameY = topBarHeight + consensusHeight
        let dark = self.isDarkAppearance
        let attrs: [NSAttributedString.Key: Any] = [
            .font: chineseLabelFont,
            .foregroundColor: Minimal.text(dark: dark)
        ]
        // 选中态苹方 Semibold 字体提升到 draw 开头（避免每行做一次
        // PostScript 名查找）；段落样式同样只建一次
        let selectedNameFont = NSFont(name: "PingFangSC-Semibold", size: fontSize - 1) ?? boldFont
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: selectedNameFont,
            .foregroundColor: Minimal.text(dark: dark)
        ]
        let rowNumFontCached = NSFont.monospacedSystemFont(ofSize: fontSize - 2, weight: .regular)
        let rowNumTextH = rowNumFontCached.ascender - rowNumFontCached.descender
        let rowNumPara = NSMutableParagraphStyle()
        rowNumPara.alignment = .right
        rowNumPara.lineBreakMode = .byClipping
        let rowNumAttrs: [NSAttributedString.Key: Any] = [
            .font: rowNumFontCached,
            .foregroundColor: Minimal.textFaint(dark: dark),
            .paragraphStyle: rowNumPara
        ]
        let namePara = NSMutableParagraphStyle()
        namePara.lineBreakMode = .byTruncatingTail
        let nameTextH = chineseLabelFont.ascender - chineseLabelFont.descender

        // 名称列背景
        ctx.setFillColor(Minimal.card(dark: dark).cgColor)
        ctx.fill(CGRect(x: nameX, y: nameY, width: nameColWidth, height: bounds.height - nameY))

        for row in minRow..<maxRow {
            guard row < align.sequences.count else { continue }
            let y = nameY + CGFloat(row) * cellHeight

            // 选中行高亮（Minimal.primary 低透明度，浅 0.06 / 深 0.12）
            if row == selectedRow {
                ctx.setFillColor(Minimal.primary(dark: dark)
                    .withAlphaComponent(dark ? 0.12 : 0.06).cgColor)
                ctx.fill(CGRect(x: nameX, y: y, width: nameColWidth, height: cellHeight))
            }

            // 行号（issue 5：与名称、残基同样「中部对齐」—— 行号此前贴顶，
            // 导致与已居中的名称 / 残基视觉错位）
            let rowNum = "\(row + 1)" as NSString
            let rowNumRect = NSRect(x: nameX + 4,
                                    y: y + max(0, (cellHeight - rowNumTextH) / 2),
                                    width: 22,
                                    height: rowNumTextH)
            rowNum.draw(in: rowNumRect, withAttributes: rowNumAttrs)

            // 名称（超长截断为省略号，3.4）
            let name = align.sequences[row].name as NSString
            let drawAttrs = row == selectedRow ? selectedAttrs : attrs
            let availWidth = nameColWidth - 28 - 6
            let nameRect = NSRect(x: nameX + 28,
                                  y: y + max(0, (cellHeight - nameTextH) / 2),
                                  width: max(10, availWidth),
                                  height: nameTextH)
            var nameAttrs = drawAttrs
            nameAttrs[.paragraphStyle] = namePara
            name.draw(with: nameRect, options: [.usesLineFragmentOrigin], attributes: nameAttrs)
        }
    }

    // MARK: - 绘制残基

    // MARK: - 绘制残基

    /// 1 字符 NSString 静态表（ASCII 128 项），滚动/悬停每帧数万格
    /// 不再逐格 String 分配
    private static let glyphTable: [NSString] = (0..<128).map { String(UnicodeScalar(UInt8($0))) as NSString }
    @inline(__always)
    private func glyph(_ byte: UInt8) -> NSString {
        byte < 128 ? Self.glyphTable[Int(byte)] : (String(UnicodeScalar(byte)) as NSString)
    }

    // MARK: P1 批量绘制辅助（CoreText 字形缓存 + 按色组 drawGlyphs）

    /// 取可批量绘制的字形；非 ASCII 或字形缺失返回 nil（调用方退回逐格绘制）
    @inline(__always)
    private func batchedGlyph(_ byte: UInt8) -> CGGlyph? {
        guard byte < 128, glyphIds.count == 128 else { return nil }
        let g = glyphIds[Int(byte)]
        return g != 0 ? g : nil
    }

    /// 按当前残基字体构建 CoreText 字形缓存；构建失败时调用方退回逐格绘制
    private func ensureGlyphCache(for font: NSFont) {
        if glyphCacheFontName == font.fontName, glyphCacheFontSize == font.pointSize, glyphCTFont != nil { return }
        let ct = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        var chars = [UniChar](repeating: 0, count: 128)
        for i in 0..<128 { chars[i] = UniChar(i) }
        var glyphs = [CGGlyph](repeating: 0, count: 128)
        guard CTFontGetGlyphsForCharacters(ct, chars, &glyphs, 128) else {
            glyphCTFont = nil
            return
        }
        var advances = [CGSize](repeating: .zero, count: 128)
        CTFontGetAdvancesForGlyphs(ct, .horizontal, glyphs, &advances, 128)
        glyphCTFont = ct
        glyphCGFont = CTFontCopyGraphicsFont(ct, nil)
        glyphIds = glyphs
        glyphAdvances = advances.map { $0.width }
        glyphAscent = CTFontGetAscent(ct)
        glyphDescent = CTFontGetDescent(ct)
        glyphCacheFontName = font.fontName
        glyphCacheFontSize = font.pointSize
    }

    /// 矩形合股为单条 path 一次填充（替代每格 setFillColor+fill）
    @inline(__always)
    private func fillBundled(_ ctx: CGContext, _ rects: [CGRect]) {
        guard !rects.isEmpty else { return }
        let path = CGMutablePath()
        for rect in rects { path.addRect(rect) }
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// 按色组分批绘制字形（每批 ≤512 个；要求 textMatrix 为 identity，
    /// 颜色取当前填充色，字体由 CTFont 携带）
    private func flushGlyphs(_ ctx: CGContext,
                             _ runs: [[(glyph: CGGlyph, x: CGFloat, y: CGFloat)]],
                             colors: [CGColor], ctFont: CTFont) {
        for (idx, items) in runs.enumerated() where !items.isEmpty {
            flushGlyphs(ctx, items, color: colors[idx], ctFont: ctFont)
        }
    }

    private func flushGlyphs(_ ctx: CGContext,
                             _ items: [(glyph: CGGlyph, x: CGFloat, y: CGFloat)],
                             color: CGColor, ctFont: CTFont) {
        guard !items.isEmpty else { return }
        ctx.setFillColor(color)
        var glyphs: [CGGlyph] = []
        var points: [CGPoint] = []
        glyphs.reserveCapacity(512)
        points.reserveCapacity(512)
        for item in items {
            glyphs.append(item.glyph)
            points.append(CGPoint(x: item.x, y: item.y))
            if glyphs.count == 512 {
                CTFontDrawGlyphs(ctFont, glyphs, points, glyphs.count, ctx)
                glyphs.removeAll(keepingCapacity: true)
                points.removeAll(keepingCapacity: true)
            }
        }
        if !glyphs.isEmpty { CTFontDrawGlyphs(ctFont, glyphs, points, glyphs.count, ctx) }
    }

    private func drawResidues(_ ctx: CGContext, _ align: Alignment,
                               minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) {
        let dataY = topBarHeight + consensusHeight
        let dark = self.isDarkAppearance
        // 复用 ensureStats 的缓存 identity（按 revision 失效），避免每帧全量重算。
        // 统计后台计算未就绪时传空数组降级（按最浅灰阶），绝不回退主线程全表扫描
        let colorMatrix = ColorComputer.computeViewport(
            align, scheme: colorScheme,
            rowStart: minRow, rowCount: maxRow - minRow,
            colStart: minCol, colCount: maxCol - minCol,
            identities: cachedStats?.identity ?? []
        )

        let resFont = highContrast ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium) : monoFont
        // 残基前景：极简/科研配色由调色板 fg 提供；高对比模式用近黑/近白纯文本
        let resFg: NSColor = highContrast ? (dark ? .white : .black) : .black
        ensureGlyphCache(for: resFont)
        // 密度模式——列宽过小时字形不可读，只画色块（空位底色/斜纹保留）
        let glyphsEnabled = cachedCellWidth >= Self.glyphDensityThreshold && glyphCTFont != nil

        // 每帧一次性的常量——颜色、属性字典、cgColor 全部提升到循环外
        let gapCG = Minimal.gapTint(dark: dark).cgColor
        let cardCG = Minimal.card(dark: dark).cgColor
        let borderCG = Minimal.border(dark: dark).cgColor
        let dimCG = Minimal.dimOverlay(dark: dark).cgColor
        let gapFG = Minimal.textMuted(dark: dark).cgColor
        let dimmedFG = Minimal.textFaint(dark: dark).cgColor
        let gapAttrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: Minimal.textMuted(dark: dark),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        let dimmedAttrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: Minimal.textFaint(dark: dark)
        ]
        // 调色板索引 → 颜色 8 项预构造（批量填充用 CGColor；回退路径用属性字典）
        var bgCGByIndex = [CGColor](repeating: .clear, count: 8)
        var fgCGByIndex = [CGColor](repeating: .clear, count: 8)
        var attrsByIndex = [[NSAttributedString.Key: Any]](repeating: [:], count: 8)
        for idx in 0..<8 {
            let palette = ColorResolver.palette(colorScheme, index: idx, dark: dark)
            bgCGByIndex[idx] = palette.bg.cgColor
            fgCGByIndex[idx] = highContrast ? resFg.cgColor : palette.fg.cgColor
            attrsByIndex[idx] = [.font: resFont, .foregroundColor: highContrast ? resFg : palette.fg]
        }

        // 差异模式参考行快照按 (行, revision) 缓存，避免每帧深拷贝整行
        var refRowBytes: [UInt8]? = nil
        if let refRow = differenceReferenceRow, refRow >= 0 {
            if let cached = cachedDiffRefRow, cached.row == refRow, cached.revision == align.revision {
                refRowBytes = cached.bytes
            } else {
                let bytes: [UInt8]? = align.lockedSequences { seqs in
                    refRow < seqs.count ? Array(seqs[refRow].residues) : nil
                }
                cachedDiffRefRow = (refRow, align.revision, bytes)
                refRowBytes = bytes
            }
        }
        let diffRefRow = differenceReferenceRow

        let viewportWidth = bounds.width - nameColWidth
        let resTextH = resFont.ascender - resFont.descender
        let gapTextH = monoFont.ascender - monoFont.descender
        // 批量的字形基线相对单元格顶部偏移
        let glyphBaseline = max(0, (cellHeight - (glyphAscent + glyphDescent)) / 2) + glyphAscent

        // 批量容器——背景按 8 色分桶一次填充；文字按色组分批 drawGlyphs，
        // 而非每格 setFillColor+fill+NSString.draw（满帧约 2.6 万次调用）
        var bgRects = [[CGRect]](repeating: [], count: 8)
        var textRuns = [[(glyph: CGGlyph, x: CGFloat, y: CGFloat)]](repeating: [], count: 8)
        var gapRects: [CGRect] = []
        var gapTexts: [(glyph: CGGlyph, x: CGFloat, y: CGFloat)] = []
        var gapUnderlines: [(x: CGFloat, y: CGFloat)] = []
        var gapDiagonals: [(x: CGFloat, y: CGFloat)] = []
        var dimmedTexts: [(glyph: CGGlyph, x: CGFloat, y: CGFloat)] = []
        var dimRects: [CGRect] = []
        // 非 ASCII/字形缺失的残基退回逐格绘制（稀有路径，像素与旧行为一致）
        var fallbackDraws: [(byte: UInt8, rect: NSRect, attrs: [NSAttributedString.Key: Any])] = []

        for r in 0..<(maxRow - minRow) {
            let row = minRow + r
            guard row < align.sequences.count else { continue }
            let y = dataY + CGFloat(row) * cellHeight
            let seq = align.sequences[row]

            // 行背景（交替，使用语义色，自适应暗色）
            if row % 2 == 0 {
                ctx.setFillColor(cardCG)
                ctx.fill(CGRect(x: nameColWidth, y: y, width: viewportWidth, height: cellHeight))
            }

            let baseY = y + glyphBaseline

            for c in 0..<(maxCol - minCol) {
                let col = minCol + c
                guard col < seq.residues.count else { continue }
                let res = seq.residues[col]
                let x = nameColWidth + CGFloat(col) * cellWidth
                let cellRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)

                // 名称固定带覆盖的列不绘制（随后被固定带覆写，省去无效绘制）
                if let pin = pinnedNamesRange, cellRect.minX < pin.upperBound, cellRect.maxX > pin.lowerBound {
                    continue
                }

                // 空位：非颜色线索（中性底色 + 下划线），高对比下再加斜纹（4.4）
                if res == 0x2D {
                    gapRects.append(cellRect)
                    if glyphsEnabled {
                        if let g = batchedGlyph(0x2D) {
                            gapTexts.append((g, x + (cellWidth - glyphAdvances[Int(0x2D)]) / 2, baseY))
                            gapUnderlines.append((x: x, y: baseY + 1.5))
                        } else {
                            fallbackDraws.append((res, NSRect(x: x, y: y + max(0, (cellHeight - gapTextH) / 2),
                                                              width: cellWidth, height: gapTextH), gapAttrs))
                        }
                    }
                    if highContrast {
                        gapDiagonals.append((x: x, y: y))
                    }
                    continue
                }

                // 差异模式：与参考行相同的残基 → 无色底 + 淡灰字（差异位点保持配色突出）
                var dimmed = false
                if let ref = refRowBytes, row != diffRefRow {
                    let refRes = col < ref.count ? ref[col] : UInt8(0x2D)
                    if refRes != 0x2D && refRes == res {
                        dimmed = true
                    }
                }

                let colorIdx = Int(colorMatrix[r * (maxCol - minCol) + c])
                if dimmed {
                    if glyphsEnabled, let g = batchedGlyph(res) {
                        dimmedTexts.append((g, x + (cellWidth - glyphAdvances[Int(res)]) / 2, baseY))
                    } else {
                        fallbackDraws.append((res, NSRect(x: x, y: y + max(0, (cellHeight - resTextH) / 2),
                                                          width: cellWidth, height: resTextH), dimmedAttrs))
                    }
                } else {
                    // 颜色背景 + 残基文字（垂直居中，与行号、名称基线对齐）
                    bgRects[colorIdx].append(cellRect)
                    if glyphsEnabled, let g = batchedGlyph(res) {
                        textRuns[colorIdx].append((g, x + (cellWidth - glyphAdvances[Int(res)]) / 2, baseY))
                    } else {
                        fallbackDraws.append((res, NSRect(x: x, y: y + max(0, (cellHeight - resTextH) / 2),
                                                          width: cellWidth, height: resTextH), attrsByIndex[colorIdx]))
                    }
                }

                // 聚焦变暗：存在选区时淡化非选中单元格，让注意力聚焦（设置可开关）
                if focusDimMode, hasActiveSelection, !isCellSelected(row: row, col: col) {
                    dimRects.append(cellRect)
                }
            }
        }

        // ---- 批量落笔（层次：底色 → 文字 → 聚焦变暗覆盖）----
        for idx in 0..<8 where !bgRects[idx].isEmpty {
            ctx.setFillColor(bgCGByIndex[idx])
            fillBundled(ctx, bgRects[idx])
        }
        if !gapRects.isEmpty {
            ctx.setFillColor(gapCG)
            fillBundled(ctx, gapRects)
        }
        if !gapDiagonals.isEmpty {
            let path = CGMutablePath()
            for d in gapDiagonals {
                path.move(to: CGPoint(x: d.x, y: d.y))
                path.addLine(to: CGPoint(x: d.x + cellWidth, y: d.y + cellHeight))
            }
            ctx.setStrokeColor(borderCG)
            ctx.setLineWidth(0.5)
            ctx.addPath(path)
            ctx.strokePath()
        }

        if glyphsEnabled, let ctFont = glyphCTFont {
            ctx.textMatrix = CGAffineTransform.identity   // 防御：先前 NSString.draw 可能改写矩阵
            flushGlyphs(ctx, textRuns, colors: fgCGByIndex, ctFont: ctFont)
            flushGlyphs(ctx, dimmedTexts, color: dimmedFG, ctFont: ctFont)
            flushGlyphs(ctx, gapTexts, color: gapFG, ctFont: ctFont)
            if !gapUnderlines.isEmpty {
                let path = CGMutablePath()
                for u in gapUnderlines {
                    path.move(to: CGPoint(x: u.x + 1, y: u.y))
                    path.addLine(to: CGPoint(x: u.x + cellWidth - 1, y: u.y))
                }
                ctx.setStrokeColor(gapFG)
                ctx.setLineWidth(1)
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        for f in fallbackDraws {
            glyph(f.byte).draw(in: f.rect, withAttributes: f.attrs)
        }
        if !dimRects.isEmpty {
            ctx.setFillColor(dimCG)
            fillBundled(ctx, dimRects)
        }
    }

    // MARK: - 绘制选区

    private func drawSelection(_ ctx: CGContext, _ align: Alignment) {
        // 当前光标位置高亮
        if let row = selectedRow, let col = selectedCol {
            let x = nameColWidth + CGFloat(col) * cellWidth
            let y = topBarHeight + consensusHeight + CGFloat(row) * cellHeight
            ctx.setStrokeColor(Minimal.primary(dark: self.isDarkAppearance).withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
        }

        // 选区矩形（非列块模式）
        if !isColumnBlockSelection, let rect = selectionRect {
            ctx.setFillColor(Minimal.primary(dark: self.isDarkAppearance)
                .withAlphaComponent(self.isDarkAppearance ? 0.16 : 0.10).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(Minimal.primary(dark: self.isDarkAppearance).withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(rect)
        }
    }

    // MARK: - 绘制列块选区（Option+拖拽）
    // 统一使用强调色，与正常选区一致（4.8）

    private func drawColumnBlockSelection(_ ctx: CGContext, _ align: Alignment) {
        let minC = min(columnBlockStart, columnBlockEnd)
        let maxC = max(columnBlockStart, columnBlockEnd)
        let x = nameColWidth + CGFloat(minC) * cellWidth
        let width = CGFloat(maxC - minC + 1) * cellWidth
        let y = topBarHeight + consensusHeight
        let height = CGFloat(align.seqCount) * cellHeight

        ctx.setFillColor(Minimal.primary(dark: self.isDarkAppearance)
            .withAlphaComponent(self.isDarkAppearance ? 0.16 : 0.10).cgColor)
        ctx.fill(CGRect(x: x, y: y, width: width, height: height))
        ctx.setStrokeColor(Minimal.primary(dark: self.isDarkAppearance).withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(CGRect(x: x, y: y, width: width, height: height))
    }

    // MARK: - 绘制搜索高亮

    private func drawSearchHighlights(_ ctx: CGContext, _ align: Alignment,
                                       minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) {
        for (i, hit) in searchHits.enumerated() {
            // 可视裁剪：宽泛搜索在万列比对上可达数万命中，
            // 视口外的命中不逐个 fill+stroke
            if hit.isNameHit {
                if hit.seqIndex < minRow - 1 || hit.seqIndex >= maxRow { continue }
            } else {
                if hit.seqIndex < minRow - 1 || hit.seqIndex >= maxRow { continue }
                if hit.position + hit.matchLen < minCol || hit.position > maxCol { continue }
            }
            let y = topBarHeight + consensusHeight + CGFloat(hit.seqIndex) * cellHeight
            let x: CGFloat
            let w: CGFloat
            if hit.isNameHit {
                // 名称命中：整行数据区高亮（无具体列位置）
                x = nameColWidth
                w = CGFloat(align.length) * cellWidth
            } else {
                x = nameColWidth + CGFloat(hit.position) * cellWidth
                w = CGFloat(hit.matchLen) * cellWidth
            }
            let isCurrent = i == currentHitIndex

            // 搜索高亮填充（唯一蓝色例外）
            ctx.setFillColor(Minimal.searchHighlight(dark: self.isDarkAppearance).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: max(1, w), height: cellHeight))

            if isCurrent {
                ctx.setStrokeColor(Minimal.primary(dark: self.isDarkAppearance).cgColor)
                ctx.setLineWidth(2.5)
            } else {
                ctx.setStrokeColor(Minimal.borderStrong(dark: self.isDarkAppearance).cgColor)
                ctx.setLineWidth(1.5)
            }
            ctx.stroke(CGRect(x: x, y: y, width: max(1, w), height: cellHeight))
        }
    }

    // MARK: - 绘制拖拽指示线

    private func drawDragIndicator(_ ctx: CGContext, row: Int) {
        let y = topBarHeight + consensusHeight + CGFloat(row) * cellHeight
        ctx.setStrokeColor(Minimal.primary(dark: self.isDarkAppearance).withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: bounds.width, y: y))
        ctx.strokePath()
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        // 成为第一响应者，启用方向键导航（4.3）
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        let (row, col) = pointToCell(point)

        // 改宽判定仅从名称列一侧发起。
        // 原判定 abs(point.x - nameColWidth) <= 5 在边界两侧对称 ±5px，
        // 导致首列残基最左侧约 5px 的点击被拦截为「改列宽」而非选中单元格。
        // 现改为：名称列侧 |point.x - nameColWidth| <= resizeZoneWidth（5px），
        // 数据侧收窄到 dataSideResizeWidth（2px），把数据格选择权还给用户。
        //
        // Bug #1 补充：轨道判定须前置——轨道区 y<12 且 x∈[nameColWidth, nameColWidth+5]
        // （即第 0 列头部）的点击原先被改宽分支抢先拦截。先判定轨道再判改宽。

        // 保守度轨道交互区（仅数据区上沿 12px）：点击 / 拖动跳转列 + 悬停 peek
        // （前置于改宽判定，避免轨道区点击被改宽拦截；
        //   名称固定带覆盖的 x 区间归名称列所有，不参与轨道交互）
        if point.y < conservationRailHeight, point.x >= nameColWidth,
           !activeNamesRange.contains(point.x),
           let align = alignment, align.length > 0 {
            isScrubbingRail = true
            // 保留当前行光标位置，仅跳转列（selectedRow=0 会丢失行光标）
            selectedCol = col
            hoverColumn = col
            onPositionChanged?(selectedRow ?? 0, col)
            announceCursor()
            reportSelection()
            scrollColumnToVisibleCentered(col)
            needsDisplay = true
            return
        }

        // 名称列分隔线可拖拽调整宽度（轨道判定之后，避免轨道区被拦截；
        // 固定态下边界随固定带移动）
        let distToBoundary = point.x - namesBoundaryX
        if distToBoundary <= resizeZoneWidth && distToBoundary >= -dataSideResizeWidth {
            isResizingNameCol = true
            NSCursor.resizeLeftRight.set()
            needsDisplay = true
            return
        }

        // 名称区 = 原始名称带，或滚过后的固定带（命中判定重映射到固定带）
        let inNameArea = activeNamesRange.contains(point.x)

        // 双击检测：名称区双击 = 重命名（#9：数据区双击 dead 分支已移除）
        if event.clickCount >= 2 {
            if inNameArea {
                onRenameRequest?(row)
            }
            return
        }

        // 检查是否在名称区开始拖拽排序
        if inNameArea {
            isDraggingSequence = true
            dragSourceRow = row
            dragIndicatorRow = row
        }

        // Option 键按下 → 列块选择模式（与名称区行拖拽互斥：
        // Option+拖拽列块但起点落在名称列时会意外移动序列）
        if !inNameArea && event.modifierFlags.contains(.option) {
            isColumnBlockSelection = true
            columnBlockStart = col
            columnBlockEnd = col
        } else {
            isColumnBlockSelection = false
            selectedRow = row
            selectedCol = col
            setSelectionRect(nil)
        }

        onPositionChanged?(row, col)
        announceCursor()
        reportSelection()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // 名称列宽度拖拽（固定态下从固定带左缘起算目标宽度）
        if isResizingNameCol {
            let stripBase = pinnedNamesRange?.lowerBound ?? 0
            let newWidth = max(minNameColWidth, min(maxNameColWidth, point.x - stripBase))
            if abs(newWidth - nameColWidth) > 0.25 {
                nameColWidth = newWidth
                if let cells = selectionCellRange {
                    selectionRect = rect(for: cells)
                }
                updateContentSize()
                needsDisplay = true
            }
            return
        }

        // 轨道拖动跳转列
        if isScrubbingRail {
            let (_, c) = pointToCell(point)
            selectedCol = c
            hoverColumn = c
            onPositionChanged?(selectedRow ?? 0, c)
            announceCursor()
            scrollColumnToVisibleCentered(c)
            invalidateTopBand()
            return
        }

        if isDraggingSequence {
            let (row, _) = pointToCell(point)
            if dragIndicatorRow != row {
                // 拖拽指示线只失效新旧两行的窄带，不再全视口重绘
                invalidateRowBand(dragIndicatorRow)
                dragIndicatorRow = row
                invalidateRowBand(dragIndicatorRow)
            }
            return
        }

        let (row, col) = pointToCell(point)

        if isColumnBlockSelection {
            if columnBlockEnd != col {
                columnBlockEnd = col
                needsDisplay = true
            }
        } else {
            guard let startRow = selectedRow, let startCol = selectedCol else { return }

            let minR = min(startRow, row)
            let maxR = max(startRow, row)
            let minC = min(startCol, col)
            let maxC = max(startCol, col)
            let newRect = NSRect(
                x: nameColWidth + CGFloat(minC) * cellWidth,
                y: topBarHeight + consensusHeight + CGFloat(minR) * cellHeight,
                width: CGFloat(maxC - minC + 1) * cellWidth,
                height: CGFloat(maxR - minR + 1) * cellHeight
            )
            if newRect != selectionRect {
                // 选区拖拽只失效新旧选区的并集（含 2px 描边余量）
                let old = selectionRect
                setSelectionRect(newRect)
                var dirty = newRect
                if let old { dirty = old.union(newRect).insetBy(dx: -2, dy: -2) }
                setNeedsDisplay(dirty)
            }
        }
        // 拖选期间不逐鼠标事件上报选区（120+ 事件/秒各触发一次
        // @Published 写入，会牵连 ContentView/状态栏/侧栏全 body 重算）；mouseUp 统一上报
        // needsDisplay 已按需局部失效
    }

    override func mouseUp(with event: NSEvent) {
        if isResizingNameCol {
            isResizingNameCol = false
            UserDefaults.standard.set(Double(nameColWidth), forKey: "SeqAlignMac.nameColWidth")
            needsDisplay = true
            return
        }
        if isScrubbingRail {
            isScrubbingRail = false
            needsDisplay = true
            return
        }
        if isDraggingSequence {
            if let sourceRow = dragSourceRow, let destRow = dragIndicatorRow, sourceRow != destRow {
                onMoveRequest?(sourceRow, destRow)
            }
            isDraggingSequence = false
            dragSourceRow = nil
            dragIndicatorRow = nil
        }
        // 保留选区，不清除
        reportSelection()
        needsDisplay = true
    }

    // MARK: - 键盘导航（4.3）

    override func keyDown(with event: NSEvent) {
        guard alignment != nil else { super.keyDown(with: event); return }
        let extend = event.modifierFlags.contains(.option)
        switch event.keyCode {
        case 123: moveCursor(dRow: 0, dCol: -1, extend: extend)   // 左
        case 124: moveCursor(dRow: 0, dCol: 1, extend: extend)    // 右
        case 125: moveCursor(dRow: 1, dCol: 0, extend: extend)    // 下
        case 126: moveCursor(dRow: -1, dCol: 0, extend: extend)   // 上
        case 53:  // Esc — #6：清除选区
            clearSelection()
        default: super.keyDown(with: event)
        }
    }

    // MARK: - 清除选区（#6：Esc 清除选区，让聚焦变暗有出口）

    func clearSelection() {
        selectedRow = nil
        selectedCol = nil
        selectionAnchor = nil   // 
        setSelectionRect(nil)
        isColumnBlockSelection = false
        columnBlockStart = 0
        columnBlockEnd = 0
        onSelectionChanged?(nil)
        needsDisplay = true
    }

    private func moveCursor(dRow: Int, dCol: Int, extend: Bool) {
        guard let align = alignment, align.seqCount > 0, align.length > 0 else { return }
        let nr = min(max(0, (selectedRow ?? 0) + dRow), align.seqCount - 1)
        let nc = min(max(0, (selectedCol ?? 0) + dCol), align.length - 1)

        if extend {
            // 独立保存锚点，扩展选区时以初始位置为基准，
            // 不再以 selectedRow/selectedCol（每次移动末尾已更新）为锚点
            if selectionAnchor == nil {
                selectionAnchor = (selectedRow ?? nr, selectedCol ?? nc)
            }
            let aR = selectionAnchor!.row
            let aC = selectionAnchor!.col
            let minR = min(aR, nr), maxR = max(aR, nr)
            let minC = min(aC, nc), maxC = max(aC, nc)
            setSelectionRect(NSRect(
                x: nameColWidth + CGFloat(minC) * cellWidth,
                y: topBarHeight + consensusHeight + CGFloat(minR) * cellHeight,
                width: CGFloat(maxC - minC + 1) * cellWidth,
                height: CGFloat(maxR - minR + 1) * cellHeight
            ))
        } else {
            selectionAnchor = nil   // 非扩展移动清除锚点
            setSelectionRect(nil)
        }

        selectedRow = nr
        selectedCol = nc
        onPositionChanged?(nr, nc)
        announceCursor()
        reportSelection()
        // 光标移出视口后跟随滚动（焦点框不得画在视口外）
        let cursorRect = NSRect(x: nameColWidth + CGFloat(nc) * cellWidth,
                                y: topBarHeight + consensusHeight + CGFloat(nr) * cellHeight,
                                width: cellWidth, height: cellHeight)
        enclosingScrollView?.scrollToVisible(cursorRect)
        needsDisplay = true
    }

    // MARK: - 名称区拖拽光标提示（4.6）

    override func resetCursorRects() {
        super.resetCursorRects()
        // 名称主体（原始带 + 固定态下的固定带）：拖拽重排光标
        // 分隔线判定区：左右调整宽度光标（固定态边界随带移动）
        var bandOrigins: [CGFloat] = [0]
        if let pin = pinnedNamesRange { bandOrigins.append(pin.lowerBound) }
        let nameBodyWidth = max(0, nameColWidth - resizeZoneWidth)
        for baseX in bandOrigins {
            addCursorRect(NSRect(x: baseX, y: 0, width: nameBodyWidth, height: bounds.height), cursor: .openHand)
            addCursorRect(NSRect(x: baseX + nameColWidth - resizeZoneWidth, y: 0,
                                 width: resizeZoneWidth * 2, height: bounds.height), cursor: .resizeLeftRight)
        }
        // 保守度轨道（数据区上沿 12px）：指向手型，提示可点击 / 拖动跳转
        // （固定态下轨道光标区从固定带右缘开始，避免与名称列光标重叠）
        let railStart = namesBoundaryX
        addCursorRect(NSRect(x: railStart, y: 0,
                             width: max(0, bounds.width - railStart), height: conservationRailHeight),
                      cursor: .pointingHand)
    }

    // MARK: - 轨道悬停 peek（鼠标移动追踪）

    private var railTrackingArea: NSTrackingArea?

    /// 悬停/轨道相关变化只失效顶部带（轨道 + 标尺 + peek tooltip 高度带），
    /// 避免整视图 needsDisplay 把每格开销乘到每次 hover 跨列
    private func invalidateTopBand() {
        setNeedsDisplay(CGRect(x: 0, y: 0, width: bounds.width,
                               height: conservationRailHeight + 56))
    }

    /// 拖拽指示线按行窄带局部失效
    private func invalidateRowBand(_ row: Int?) {
        guard let row else { return }
        let y = topBarHeight + consensusHeight + CGFloat(row) * cellHeight
        setNeedsDisplay(CGRect(x: 0, y: y - 2, width: bounds.width, height: cellHeight + 4))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = railTrackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        railTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // 名称列分隔线 hover：手柄加宽提示可拖拽
        let nearResize = abs(point.x - namesBoundaryX) <= resizeZoneWidth
        if isNearNameResize != nearResize {
            isNearNameResize = nearResize
            // 仅分隔线附近竖条带
            setNeedsDisplay(CGRect(x: namesBoundaryX - resizeZoneWidth - 2, y: 0,
                                   width: resizeZoneWidth + dataSideResizeWidth + 6,
                                   height: bounds.height))
        }
        if point.y < conservationRailHeight, point.x >= nameColWidth,
           !activeNamesRange.contains(point.x),
           let align = alignment, align.length > 0 {
            let col = max(0, min(align.length - 1, Int((point.x - nameColWidth) / cellWidth)))
            if hoverColumn != col {
                hoverColumn = col
                invalidateTopBand()
            }
        } else if hoverColumn != nil {
            hoverColumn = nil
            invalidateTopBand()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoverColumn != nil {
            hoverColumn = nil
            invalidateTopBand()
        }
        if isNearNameResize {
            isNearNameResize = false
            setNeedsDisplay(CGRect(x: namesBoundaryX - resizeZoneWidth - 2, y: 0,
                                   width: resizeZoneWidth + dataSideResizeWidth + 6,
                                   height: bounds.height))
        }
        super.mouseExited(with: event)
    }

    // MARK: - Cmd+滚轮缩放

    /// 捏合增量累计：手势以高频小增量事件推送，需过阈值才进一档
    private var pendingMagnification: CGFloat = 0
    /// Cmd+滚轮增量累计（对齐捏合手势的 0.06 阈值做法：
    /// 每事件直接换档会在惯性滚动期间连环跳档）
    private var pendingScrollDelta: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        // Cmd+滚轮缩放；触控板捏合缩放由 magnify(with:) 承载。
        // scrollWheel 事件的 magnification 恒为 0（仅 magnify 事件非零），
        // 在此判断 event.magnification 的分支不可达，捏合缩放不会生效。
        if event.modifierFlags.contains(.command) {
            pendingScrollDelta += event.deltaY
            if pendingScrollDelta > 0.5 {
                zoomIn()
                pendingScrollDelta = 0
            } else if pendingScrollDelta < -0.5 {
                zoomOut()
                pendingScrollDelta = 0
            }
        } else {
            super.scrollWheel(with: event)
        }
    }

    /// 触控板双指捏合缩放的真实入口。magnify 事件才携带非零 magnification，
    /// 沿用 0.06 阈值累积避免一次捏合连环跳档。
    override func magnify(with event: NSEvent) {
        pendingMagnification += event.magnification
        if pendingMagnification >= 0.06 {
            zoomIn()
            pendingMagnification = 0
        } else if pendingMagnification <= -0.06 {
            zoomOut()
            pendingMagnification = 0
        }
    }

    // MARK: - 右键上下文菜单

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let (row, col) = pointToCell(point)
        // 名称区 = 原始名称带或固定带（固定态下右键固定带同样弹出名称菜单）
        let inNameArea = activeNamesRange.contains(point.x)
        // 记录右键前的光标/选区，末尾改局部失效
        let oldSelectedRow = selectedRow
        let oldSelectedCol = selectedCol
        let oldSelectionRect = selectionRect
        let oldHadActiveSelection = hasActiveSelection
        // 真实数据区几何判定：pointToCell 对越界坐标钳制到 (0,0)，
        // 避免粗略判定下 inDataArea 恒真、else 分支不可达，且空数据态也显示拷贝菜单
        let dataTop = topBarHeight + consensusHeight
        let dataRight = nameColWidth + CGFloat(alignment?.length ?? 0) * cellWidth
        let inDataArea = !inNameArea && point.y >= dataTop && point.x <= dataRight && alignment != nil

        let menu = NSMenu()

        if inNameArea {
            menu.addItem(withTitle: L.s.ctxRenameSeq, action: #selector(contextRename(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L.s.ctxDeleteSeq, action: #selector(contextDelete(_:)), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: L.s.ctxMoveTop, action: #selector(contextMoveTop(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L.s.ctxMoveBottom, action: #selector(contextMoveBottom(_:)), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            // 排序子菜单
            let sortMenu = NSMenu()
            sortMenu.addItem(withTitle: L.s.ctxSortByName, action: #selector(contextSortByName(_:)), keyEquivalent: "")
            sortMenu.addItem(withTitle: L.s.ctxSortBySimilarity, action: #selector(contextSortBySimilarity(_:)), keyEquivalent: "")
            sortMenu.addItem(withTitle: L.s.ctxSortByGC, action: #selector(contextSortByGC(_:)), keyEquivalent: "")
            sortMenu.addItem(withTitle: L.s.ctxSortByLength, action: #selector(contextSortByLength(_:)), keyEquivalent: "")
            sortMenu.addItem(withTitle: L.s.ctxSortByLengthNoGaps, action: #selector(contextSortByLengthNoGaps(_:)), keyEquivalent: "")
            let sortItem = NSMenuItem(title: L.s.ctxSortBy, action: nil, keyEquivalent: "")
            sortItem.submenu = sortMenu
            menu.addItem(sortItem)
            // 空位精简子菜单
            let gapMenu = NSMenu()
            gapMenu.addItem(withTitle: L.s.ctxRemoveAllGapCols, action: #selector(contextRemoveAllGapCols(_:)), keyEquivalent: "")
            gapMenu.addItem(withTitle: L.s.ctxRemoveHighGapCols, action: #selector(contextRemoveHighGapCols(_:)), keyEquivalent: "")
            let gapItem = NSMenuItem(title: L.s.ctxGapTrimming, action: nil, keyEquivalent: "")
            gapItem.submenu = gapMenu
            menu.addItem(gapItem)
            selectedRow = row
            announceCursor()
        } else if inDataArea {
            menu.addItem(withTitle: L.s.ctxCopySelection, action: #selector(contextCopy(_:)), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            // 配色方案子菜单
            let colorMenu = NSMenu()
            colorMenu.addItem(withTitle: L.s.schemeMinimal, action: #selector(contextColorMinimal(_:)), keyEquivalent: "")
            colorMenu.addItem(withTitle: L.s.schemeDefault, action: #selector(contextColorDefault(_:)), keyEquivalent: "")
            colorMenu.addItem(withTitle: L.s.schemeClustalX, action: #selector(contextColorClustalX(_:)), keyEquivalent: "")
            colorMenu.addItem(withTitle: L.s.schemeZappo, action: #selector(contextColorZappo(_:)), keyEquivalent: "")
            colorMenu.addItem(withTitle: L.s.schemeSeaView, action: #selector(contextColorSeaView(_:)), keyEquivalent: "")
            colorMenu.addItem(withTitle: L.s.schemeTransitionTransversion, action: #selector(contextColorTiTv(_:)), keyEquivalent: "")
            colorMenu.addItem(withTitle: L.s.schemeOkabeIto, action: #selector(contextColorOkabeIto(_:)), keyEquivalent: "")
            let colorItem = NSMenuItem(title: L.s.ctxColorScheme, action: nil, keyEquivalent: "")
            colorItem.submenu = colorMenu
            menu.addItem(colorItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: L.s.ctxReverseComplement, action: #selector(contextReverseComplement(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L.s.ctxTranslate, action: #selector(contextTranslateRegion(_:)), keyEquivalent: "")
            // 空位精简子菜单（数据区也提供）
            let gapMenu = NSMenu()
            gapMenu.addItem(withTitle: L.s.ctxRemoveAllGapCols, action: #selector(contextRemoveAllGapCols(_:)), keyEquivalent: "")
            gapMenu.addItem(withTitle: L.s.ctxRemoveHighGapCols, action: #selector(contextRemoveHighGapCols(_:)), keyEquivalent: "")
            let gapItem = NSMenuItem(title: L.s.ctxGapTrimming, action: nil, keyEquivalent: "")
            gapItem.submenu = gapMenu
            menu.addItem(gapItem)
            selectedRow = row
            selectedCol = col
            announceCursor()
        } else {
            menu.addItem(withTitle: L.s.ctxInsertGap, action: #selector(contextInsertGap(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L.s.ctxPaste, action: #selector(contextPaste(_:)), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: L.s.ctxAddSeq, action: #selector(contextAddSeq(_:)), keyEquivalent: "")
        }
        // 与 mouseDown 一致：右键设置的光标同步上报（状态栏/导出「仅选区」随之更新）
        reportSelection()
        // 聚焦变暗会整视口改观，仍走全量重绘；否则只失效新旧光标/选区/名称行
        if focusDimMode && (oldHadActiveSelection || hasActiveSelection) {
            needsDisplay = true
        } else {
            invalidateSelectionArea(oldRow: oldSelectedRow, oldCol: oldSelectedCol, oldRect: oldSelectionRect)
        }
        return menu
    }

    /// 右键后局部失效——只重绘新旧光标格、新旧选区与名称行高亮（含固定带）
    private func invalidateSelectionArea(oldRow: Int?, oldCol: Int?, oldRect: NSRect?) {
        var rects: [NSRect] = []
        func cursorRect(_ row: Int, _ col: Int) -> NSRect {
            NSRect(x: nameColWidth + CGFloat(col) * cellWidth,
                   y: topBarHeight + consensusHeight + CGFloat(row) * cellHeight,
                   width: cellWidth, height: cellHeight)
        }
        func nameRowRect(_ row: Int) -> NSRect {
            NSRect(x: 0, y: topBarHeight + consensusHeight + CGFloat(row) * cellHeight,
                   width: nameColWidth, height: cellHeight)
        }
        if let r = selectedRow, let c = selectedCol { rects.append(cursorRect(r, c)) }
        if let r = oldRow, let c = oldCol, selectedRow != r || selectedCol != c { rects.append(cursorRect(r, c)) }
        if let rect = selectionRect { rects.append(rect.insetBy(dx: -3, dy: -3)) }
        if let rect = oldRect, rect != selectionRect { rects.append(rect.insetBy(dx: -3, dy: -3)) }
        if let r = selectedRow { rects.append(nameRowRect(r)) }
        if let r = oldRow, selectedRow != r { rects.append(nameRowRect(r)) }
        if let pin = pinnedNamesRange {
            // 固定带整列覆写：其内的名称/行高亮变化随带一起失效
            rects.append(NSRect(x: pin.lowerBound - 2, y: 0, width: nameColWidth + 4, height: bounds.height))
        }
        for rect in rects { setNeedsDisplay(rect) }
    }

    // 右键菜单动作
    @objc private func contextRename(_ sender: Any?) {
        if let row = selectedRow { onRenameRequest?(row) }
    }
    @objc private func contextDelete(_ sender: Any?) {
        if let row = selectedRow { onDeleteRequest?(row) }
    }
    @objc private func contextMoveTop(_ sender: Any?) {
        if let row = selectedRow { onMoveRequest?(row, 0) }
    }
    @objc private func contextMoveBottom(_ sender: Any?) {
        if let row = selectedRow, let align = alignment {
            onMoveRequest?(row, align.seqCount - 1)
        }
    }
    @objc private func contextSortByName(_ sender: Any?) {
        onContextAction?(.sortByName)
    }
    @objc private func contextSortBySimilarity(_ sender: Any?) {
        onContextAction?(.sortBySimilarity)
    }
    @objc private func contextSortByGC(_ sender: Any?) {
        onContextAction?(.sortByGC)
    }
    @objc private func contextSortByLength(_ sender: Any?) {
        onContextAction?(.sortByLength)
    }
    @objc private func contextSortByLengthNoGaps(_ sender: Any?) {
        onContextAction?(.sortByLengthNoGaps)
    }
    @objc private func contextReverseComplement(_ sender: Any?) {
        onContextAction?(.reverseComplement)
    }
    @objc private func contextRemoveAllGapCols(_ sender: Any?) {
        onContextAction?(.removeAllGapCols)
    }
    @objc private func contextRemoveHighGapCols(_ sender: Any?) {
        onContextAction?(.removeHighGapCols)
    }
    @objc private func contextCopy(_ sender: Any?) {
        // 复制真实选区范围（修复 2.2）
        onContextAction?(.copySelection(currentSelectionRange()))
    }
    @objc private func contextColorMinimal(_ sender: Any?) {
        ColorSchemeManager.shared.setScheme(.minimal)
    }
    @objc private func contextColorDefault(_ sender: Any?) {
        ColorSchemeManager.shared.setScheme(.defaultNucleotide)
    }
    @objc private func contextColorClustalX(_ sender: Any?) {
        ColorSchemeManager.shared.setScheme(.clustalX)
    }
    @objc private func contextColorZappo(_ sender: Any?) {
        ColorSchemeManager.shared.setScheme(.zappo)
    }
    @objc private func contextColorSeaView(_ sender: Any?) {
        ColorSchemeManager.shared.setScheme(.seaView)
    }
    @objc private func contextColorTiTv(_ sender: Any?) {
        ColorSchemeManager.shared.setScheme(.transitionTransversion)
    }
    @objc private func contextColorOkabeIto(_ sender: Any?) {
        ColorSchemeManager.shared.setScheme(.okabeIto)
    }
    @objc private func contextTranslateRegion(_ sender: Any?) {
        onContextAction?(.translateRegion)
    }
    @objc private func contextInsertGap(_ sender: Any?) {
        onContextAction?(.insertGap)
    }
    @objc private func contextPaste(_ sender: Any?) {
        onContextAction?(.paste)
    }
    @objc private func contextAddSeq(_ sender: Any?) {
        onContextAction?(.addSequence)
    }

    /// 根据当前选区状态推导复制范围（2.2）
    private func currentSelectionRange() -> SelectionRange {
        guard let align = alignment else {
            return SelectionRange(rowStart: 0, rowEnd: 0, colStart: 0, colEnd: 0)
        }
        let seqMax = max(0, align.seqCount - 1)
        let colMax = max(0, align.length - 1)

        if isColumnBlockSelection {
            let c0 = min(columnBlockStart, columnBlockEnd)
            let c1 = max(columnBlockStart, columnBlockEnd)
            return SelectionRange(rowStart: 0, rowEnd: seqMax, colStart: c0, colEnd: c1)
        } else if let cells = selectionCellRange {
            return SelectionRange(rowStart: cells.rows.lowerBound, rowEnd: cells.rows.upperBound,
                                  colStart: cells.cols.lowerBound, colEnd: cells.cols.upperBound)
        } else if let r = selectedRow, let c = selectedCol {
            return SelectionRange(rowStart: r, rowEnd: r, colStart: c, colEnd: c)
        } else {
            // 空选：退化为整段
            return SelectionRange(rowStart: 0, rowEnd: seqMax, colStart: 0, colEnd: colMax)
        }
    }

    /// 选区变化后向上上报（导出「仅选区」/ 引物「从选区填入」用）
    private func reportSelection() {
        guard let align = alignment else { onSelectionChanged?(nil); return }
        let seqMax = max(0, align.seqCount - 1)
        if isColumnBlockSelection {
            let c0 = min(columnBlockStart, columnBlockEnd)
            let c1 = max(columnBlockStart, columnBlockEnd)
            onSelectionChanged?(SelectionRange(rowStart: 0, rowEnd: seqMax, colStart: c0, colEnd: c1))
        } else if let cells = selectionCellRange {
            onSelectionChanged?(SelectionRange(rowStart: cells.rows.lowerBound, rowEnd: cells.rows.upperBound,
                                               colStart: cells.cols.lowerBound, colEnd: cells.cols.upperBound))
        } else if let r = selectedRow, let c = selectedCol {
            onSelectionChanged?(SelectionRange(rowStart: r, rowEnd: r, colStart: c, colEnd: c))
        } else {
            onSelectionChanged?(nil)
        }
    }

    // MARK: - 选区判定（聚焦变暗用）

    /// 是否存在有效选区（列块 / 矩形）—— #6：仅矩形或列块选区才算「有效」，
    /// 单个光标点选不再触发聚焦变暗（避免一次点击就整片灰掉）
    private var hasActiveSelection: Bool {
        if isColumnBlockSelection { return true }
        if selectionRect != nil { return true }
        return false
    }

    /// 单元格是否落在当前选区内
    private func isCellSelected(row: Int, col: Int) -> Bool {
        if isColumnBlockSelection {
            let c0 = min(columnBlockStart, columnBlockEnd)
            let c1 = max(columnBlockStart, columnBlockEnd)
            return col >= c0 && col <= c1
        }
        if let cells = selectionCellRange {
            return cells.rows.contains(row) && cells.cols.contains(col)
        }
        if let r = selectedRow, let c = selectedCol {
            return r == row && c == col
        }
        return false
    }

    /// selectionRect ↔ 行列范围换算（唯一实现，替代三处复制的像素反推）
    private func cellRange(for rect: NSRect) -> (rows: ClosedRange<Int>, cols: ClosedRange<Int>) {
        let maxRow = max(0, (alignment?.seqCount ?? 1) - 1)
        let maxCol = max(0, (alignment?.length ?? 1) - 1)
        let c0 = min(max(0, Int((rect.minX - nameColWidth) / cellWidth)), maxCol)
        let c1 = min(max(c0, Int((rect.maxX - nameColWidth) / cellWidth) - 1), maxCol)
        let r0 = min(max(0, Int((rect.minY - topBarHeight - consensusHeight) / cellHeight)), maxRow)
        let r1 = min(max(r0, Int((rect.maxY - topBarHeight - consensusHeight) / cellHeight) - 1), maxRow)
        return (r0...r1, c0...c1)
    }

    private func rect(for cells: (rows: ClosedRange<Int>, cols: ClosedRange<Int>)) -> NSRect {
        NSRect(x: nameColWidth + CGFloat(cells.cols.lowerBound) * cellWidth,
               y: topBarHeight + consensusHeight + CGFloat(cells.rows.lowerBound) * cellHeight,
               width: CGFloat(cells.cols.count) * cellWidth,
               height: CGFloat(cells.rows.count) * cellHeight)
    }

    /// 统一的选区写入入口：像素矩形与行列范围同步维护
    private func setSelectionRect(_ newRect: NSRect?) {
        selectionRect = newRect
        selectionCellRange = newRect.map { cellRange(for: $0) }
    }

    private func pointToCell(_ point: NSPoint) -> (Int, Int) {
        guard let align = alignment else { return (0, 0) }
        let col = max(0, min(align.length - 1, Int((point.x - nameColWidth) / cellWidth)))
        let row = max(0, min(align.seqCount - 1, Int((point.y - topBarHeight - consensusHeight) / cellHeight)))
        return (row, col)
    }

    // MARK: - 缩放

    func zoomIn() {
        let next = min(28, fontSize + 1)
        if next == fontSize { return }
        if let cb = onFontSizeChanged { cb(next) } else { fontSize = next }
    }

    func zoomOut() {
        let next = max(8, fontSize - 1)
        if next == fontSize { return }
        if let cb = onFontSizeChanged { cb(next) } else { fontSize = next }
    }

    // MARK: - 搜索结果滚动

    func scrollToHit(_ hit: SearchHit) {
        let x = hit.isNameHit ? nameColWidth : nameColWidth + CGFloat(hit.position) * cellWidth
        let y = topBarHeight + consensusHeight + CGFloat(hit.seqIndex) * cellHeight
        let w = hit.isNameHit ? CGFloat(alignment?.length ?? 1) * cellWidth : CGFloat(hit.matchLen) * cellWidth
        let rect = NSRect(x: x, y: y, width: max(1, w), height: cellHeight)
        enclosingScrollView?.scrollToVisible(rect)
    }

    /// 将指定列水平居中（点击 / 拖动保守度轨道跳转时调用）
    /// y:0 height:cellHeight 会让 scrollToVisible 沿两轴最小化滚动，
    /// 把视图垂直位置跳回第一行；因此只手动调整水平 origin，保留垂直滚动位置。
    private func scrollColumnToVisibleCentered(_ col: Int) {
        guard let sv = enclosingScrollView else { return }
        let colX = nameColWidth + CGFloat(col) * cellWidth
        let visibleWidth = sv.contentView.bounds.width
        let targetX = colX - visibleWidth / 2 + cellWidth / 2
        var origin = sv.contentView.bounds.origin
        // 钳制到内容范围内
        let contentWidth = sv.documentView?.bounds.width ?? visibleWidth
        let maxX = max(0, contentWidth - visibleWidth)
        origin.x = max(0, min(maxX, targetX))
        sv.contentView.bounds.origin = origin
        sv.reflectScrolledClipView(sv.contentView)
    }
}

// MARK: - 上下文菜单动作枚举

enum ContextAction {
    case copySelection(SelectionRange)
    case translateRegion
    case insertGap
    case paste
    case addSequence
    case sortByName
    case sortBySimilarity
    case sortByGC
    case sortByLength
    case sortByLengthNoGaps
    case reverseComplement
    case removeAllGapCols
    case removeHighGapCols
}
