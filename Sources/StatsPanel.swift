//  StatsPanel.swift
//  SeqAlignMac — 右侧统计面板（中英文国际化）
//
//  设计：中性灰极简。只消费 Minimal 令牌，
//  图表用 chart-1..5 单色灰阶。所有统计在后台线程计算，
//  经代际编号（generation）丢弃过期结果，大比对不卡 UI。

import AppKit
import SwiftUI

// MARK: - 共识序列文本宽度测量 Key

struct ConsensusTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 统计计算模型

final class StatsPanelModel: ObservableObject {
    @Published var quality: AlignmentQuality?
    @Published var histogram: [Int] = [0, 0, 0, 0, 0]
    @Published var meanColumnIdentity: Double = 0
    @Published var highConservedRatio: Double = 0
    @Published var consensusText: String = ""
    /// 融合扫描已算好的每列一致度，面板直接取用。
    /// 本面板过去还有第三份列一致度实现（columnIdentityText 自己数频次），
    /// 而 ColumnStats 的注释正是为消灭这种重复才写"单一事实来源"。删掉它。
    @Published var columnIdentities: [Double] = []
    @Published var computing = false

    private var lastKey: (ObjectIdentifier, UInt64, ConsensusMode)?
    private var generation = 0

    func update(alignment: Alignment?) {
        guard let align = alignment else {
            generation += 1
            quality = nil
            histogram = [0, 0, 0, 0, 0]
            meanColumnIdentity = 0
            highConservedRatio = 0
            columnIdentities = []
            consensusText = ""
            computing = false
            lastKey = nil
            return
        }
        // 去重键必须包含**共识模式**：只比对 (对象, revision) 会漏掉共识策略变化，
        // 但同一函数下方用的是当前 `AppSettings.consensusMode` —— 用户在设置面板把共识
        // 策略从"多数规则"改成 IUPAC 简并码后，只要没有再编辑比对就整个 update 直接 return，
        // 面板共识行与"复制到剪贴板"拿到的仍是旧模式的结果，而画布已经重算
        // （AlignmentCanvasView 的 modeChanged 会判缓存过期）→ 屏幕上下两处自相矛盾。
        let key = (ObjectIdentifier(align), align.revision, AppSettings.consensusMode)
        if let last = lastKey, last == key { return }
        lastKey = key
        generation += 1
        let gen = generation
        computing = true

        DispatchQueue.global(qos: .userInitiated).async {
            // 快照移入后台；
            // computeColumnStats + computeQuality 两遍全表扫描合并为一次融合单遍扫描
            let snapshot = align.snapshot()
            let fused = AlignmentStatsCalculator.fusedScan(snapshot, mode: AppSettings.consensusMode)

            var buckets = [0, 0, 0, 0, 0]
            var sum = 0.0
            var highConserved = 0
            for v in fused.identities {
                sum += v
                buckets[min(4, Int(v * 5))] += 1
                if v >= 0.8 { highConserved += 1 }
            }
            let n = max(1, fused.identities.count)
            let consensus = fused.consensus
                .map { $0 == 0x2D ? "-" : String(UnicodeScalar($0)) }
                .joined()

            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == gen else { return }
                self.quality = fused.quality
                self.columnIdentities = fused.identities
                self.histogram = buckets
                self.meanColumnIdentity = sum / Double(n)
                self.highConservedRatio = Double(highConserved) / Double(n)
                self.consensusText = consensus
                self.computing = false
            }
        }
    }
}

// MARK: - 统计面板视图

struct StatsPanelView: View {
    @ObservedObject var workspace: Workspace
    let cursorRow: Int
    let cursorCol: Int
    var width: CGFloat = 264
    @StateObject private var model = StatsPanelModel()
    @State private var qualitySummary: FastqQualitySummary?
    @State private var lastQualityKey: (ObjectIdentifier, UInt64)?
    @State private var qualityGeneration = 0
    @ObservedObject private var lang = LanguageManager.shared
    // 共识序列横向查看：隐藏系统滚动条（过粗且与文字重叠），改为拖拽平移
    @State private var consensusOffset: CGFloat = 0
    @State private var consensusDragStart: CGFloat?
    @State private var consensusTextWidth: CGFloat = 0

    private static var bucketLabels: [String] {
        ["0-20%", "20-40%", "40-60%", "60-80%", "80-100%"]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color(Minimal.border(dark: isDarkAppearance)))
                .frame(height: 1)
            if workspace.currentAlignment == nil {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Minimal.space3 - Minimal.space1) {
                        statCard { overviewSection }
                        statCard { qualitySection }
                        statCard { phyloInfoSection }
                        statCard { conservationSection }
                        statCard { consensusSection }
                        if qualitySummary?.hasData == true {
                            statCard { fastqQualitySection }
                        }
                        statCard { cursorSection }
                    }
                    .padding(Minimal.space3 - Minimal.space1)
                }
                Text(L.s.statsMethodNote)
                    .font(.system(size: Minimal.fontXXS))
                    .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                    .padding(.horizontal, Minimal.space3 - Minimal.space1)
                    .padding(.bottom, Minimal.space2)
                    .lineLimit(6)
            }
        }
        .frame(width: max(220, min(460, width)))
        .background(Color(Minimal.surface(dark: isDarkAppearance)))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(Minimal.border(dark: isDarkAppearance)))
                .frame(width: 1)
        }
        .onAppear {
            model.update(alignment: workspace.currentAlignment)
            refreshQuality()
        }
        .onReceive(workspace.objectWillChange) { _ in
            model.update(alignment: workspace.currentAlignment)
            refreshQuality()
        }
    }

    private func refreshQuality() {
        guard let align = workspace.currentAlignment else { return }
        // 去重：与 update 同一 (对象, revision) 键。workspace 的任意 @Published
        // （如拖选时的 currentSelection）都会触发 objectWillChange，
        // 因此不能每次都在主线程做一次全量深拷贝 snapshot()。
        let key = (ObjectIdentifier(align), align.revision)
        if let last = lastQualityKey, last == key { return }
        lastQualityKey = key
        qualityGeneration += 1
        let gen = qualityGeneration
        DispatchQueue.global(qos: .utility).async {
            // 快照同样移入后台，主线程零拷贝
            let snapshot = align.snapshot()
            let summary = AlignmentStatsCalculator.computeQualitySummary(snapshot)
            DispatchQueue.main.async {
                // 代际守卫：切换文件后较慢的旧任务不得覆盖新汇总（StatsPanelView 为
                // 值类型视图，无需 weak；过期结果靠代次号丢弃）
                guard self.qualityGeneration == gen else { return }
                self.qualitySummary = summary
            }
        }
    }

    /// FASTQ 质量卡片（仅当数据含质量值时显示）
    private var fastqQualitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L.s.fastqQuality)
            if let q = qualitySummary, q.hasData {
                statRow(L.s.fastqMeanPhred, String(format: "%.1f", q.meanPhred))
                statRow(L.s.fastqMinPhred, "\(q.minPhred)")
                statRow(L.s.fastqQ20, pct(q.q20Ratio))
                statRow(L.s.fastqQ30, pct(q.q30Ratio))
            }
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: Minimal.fontSM, weight: .medium))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))   // accent → textMuted
            Text(L.s.statsTitle)
                .font(.system(size: Minimal.fontBase, weight: .semibold))
                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
            Spacer()
            if model.computing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, Minimal.space3)
        .padding(.vertical, Minimal.space3 - Minimal.space1)
        .background(Color(Minimal.controlSurface(dark: isDarkAppearance)))
    }

    // MARK: 各区块

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L.s.statsOverview)
            if let align = workspace.currentAlignment {
                statRow(L.s.statsFile, workspace.currentFileName.isEmpty ? L.s.unnamed : workspace.currentFileName)
                statRow(L.s.statsFormat, AppStrings.formatName(workspace.currentFormat, zh: lang.language == .zh))
                statRow(L.s.statsSeqCount, "\(align.seqCount)")
                statRow(L.s.statsColCount, "\(align.length)")
                statRow(L.s.statsType, align.datatype == .nucleicAcid ? L.s.statusNucleic : L.s.statusAmino)
            }
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L.s.statsQuality)
            // 未比对输入必须在统计面板上可见，而不是让用户在列同源性不成立的
            // 坐标上读到一堆看起来正常的数字。
            if workspace.currentAlignment?.provenance == .notAligned {
                Label(L.s.statsUnalignedBanner, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: Minimal.fontXXS))
                    .foregroundColor(.orange)
            }
            if let q = model.quality {
                statRow(L.s.statsMeanPairwise, pct(q.pooledPairwiseIdentity))
                statRow(L.s.statsMeanColIdentity, pct(model.meanColumnIdentity))
                statRow(L.s.statsMinColIdentity, pct(q.minColumnIdentity))
                statRow(L.s.statsMaxColIdentity, pct(q.maxColumnIdentity))
                statRow(L.s.statsGapCols, "\(q.gapColumns)")
                statRow(L.s.statsTotalCols, "\(q.totalColumns)")
            } else if model.computing {
                Text(L.s.statsComputing)
                    .font(.system(size: Minimal.fontXS))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            }
        }
    }

    // MARK: 系统发育信息

    private var phyloInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L.s.statsPhyloInfo)
            if let q = model.quality {
                statRow(L.s.statsVariableSites, "\(q.variableSites)")
                statRow(L.s.statsParsimonySites, "\(q.parsimonySites)")
                statRow(L.s.statsSingletonSites, "\(q.singletonSites)")
                // 原"采样提示"分支依赖恒为 false 的 quality.sampled（B15 改列频次法后
                // 不再采样），是永不显示的僵尸 UI，字段与本分支一并删除。
            } else if model.computing {
                Text(L.s.statsComputing)
                    .font(.system(size: Minimal.fontXS))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            }
        }
    }

    private var conservationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L.s.statsConservation)
            let maxCount = max(1, model.histogram.max() ?? 1)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<5, id: \.self) { i in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(Minimal.chartGradient(dark: isDarkAppearance, index: i)))
                            .frame(width: 28,
                                   height: 4 + CGFloat(model.histogram[i]) / CGFloat(maxCount) * 38)
                        Text(Self.bucketLabels[i])
                            .font(.system(size: Minimal.fontXXS))
                            .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            statRow(L.s.statsHighConserved, "\(Int((model.highConservedRatio * 100).rounded()))%")
            Text(L.s.statsConservationHint)
                .font(.system(size: Minimal.fontXXS))
                .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
        }
    }

    private var consensusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle(L.s.statsConsensus)
                Spacer()
                // 提供「复制完整共识到剪贴板」按钮
                Button(action: { copyConsensusToClipboard() }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: Minimal.fontXS2))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                }
                .buttonStyle(.plain)
                .help(L.s.statsConsensusCopy)
                .accessibilityLabel(L.s.statsConsensusCopy)
            }
            // 共识序列完整显示：隐藏粗滚动条，鼠标/触控板直接拖拽平移查看
            GeometryReader { geo in
                let maxOffset = min(0, geo.size.width - consensusTextWidth)
                Text(model.consensusText)
                    .font(.system(size: Minimal.fontXS, design: .monospaced))
                    .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                    .textSelection(.disabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        // 测量文本实际宽度，用于 clamp 拖拽范围
                        GeometryReader { tgeo in
                            Color.clear.preference(key: ConsensusTextWidthKey.self,
                                                   value: tgeo.size.width)
                        }
                    )
                    .offset(x: consensusOffset)
                    .clipped()
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { g in
                                let base = consensusDragStart ?? consensusOffset
                                consensusDragStart = base
                                consensusOffset = min(0, max(maxOffset, base + g.translation.width))
                            }
                            .onEnded { _ in consensusDragStart = nil }
                    )
            }
            .onPreferenceChange(ConsensusTextWidthKey.self) { consensusTextWidth = $0 }
            .onChange(of: model.consensusText) { _, _ in consensusOffset = 0 }
            .frame(height: 20)
            if let align = workspace.currentAlignment {
                let zh = lang.language == .zh
                let colsWord = zh ? "列" : "cols"
                Text("\(align.length) \(colsWord)")
                    .font(.system(size: Minimal.fontXXS))
                    .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
            }
        }
    }

    private func copyConsensusToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(model.consensusText, forType: .string)
        workspace.showToast(L.s.statsConsensusCopied)
    }

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L.s.statsCursor)
            if let align = workspace.currentAlignment, align.seqCount > 0, align.length > 0 {
                let r = min(max(0, cursorRow), align.seqCount - 1)
                let c = min(max(0, cursorCol), align.length - 1)
                statRow(L.s.statsCursor, "\(r + 1), \(c + 1)")
                statRow(L.s.statusResidue, residueString(at: r, col: c, in: align))
                statRow(L.s.statusIdentity, columnIdentityText(col: c))
            } else {
                Text(L.s.statsNoData)
                    .font(.system(size: Minimal.fontXS))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 26))
                .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
            Text(L.s.statsEmptyTitle)
                .font(.system(size: Minimal.fontBase, weight: .medium))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            Text(L.s.statsEmptyDesc)
                .font(.system(size: Minimal.fontXS2))
                .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Minimal.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 通用小组件

    private func statCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Minimal.space3 - Minimal.space1)
            .background(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)   // 8 → radiusSM
                    .fill(Color(Minimal.card(dark: isDarkAppearance)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1)   // 0.5 → 1
            )
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color(Minimal.border(dark: isDarkAppearance)))
            .frame(height: 1)
            .opacity(Minimal.dividerOpacity)   // opacity 令牌化
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: Minimal.fontSM, weight: .semibold))
            .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
            .padding(.bottom, Minimal.space1 / 2)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: Minimal.space2) {
            Text(label)
                .font(.system(size: Minimal.fontXS2))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.system(size: Minimal.fontSM, design: .monospaced))
                .monospacedDigit()
                .fontWeight(.medium)
                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }

    private func residueString(at row: Int, col: Int, in align: Alignment) -> String {
        let b = align.residue(row: row, col: col)
        return b == 0x2D ? "-" : String(UnicodeScalar(b))
    }

    /// 直接取融合扫描的每列一致度（单一事实来源），
    /// 不在面板里自己数频次——那是列一致度的第三份实现，且会在每次光标移动时
    /// 于主线程走一遍 columnResidues 的加锁全表遍历。
    /// 精度与面板其余一致度行统一为 %.1f%%（取整到个位会让同一指标两卡片读数不同）。
    private func columnIdentityText(col: Int) -> String {
        guard col >= 0, col < model.columnIdentities.count else { return "-" }
        return pct(model.columnIdentities[col])
    }
}
