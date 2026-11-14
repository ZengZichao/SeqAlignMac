//  StatsPanel.swift
//  SeqAlignMac — 右侧统计面板
//
//  组织方式：概览 → 一致度 → 保守度 → 位点 → 共识 → 测序质量 → 光标。
//  分区之间用一条 0.5pt 分隔线，不再给每一组套圆角卡片；数值使用等宽字体，
//  标签与数值基线对齐，纵向可逐行扫读。所有统计在后台线程计算，
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
        // 去重键必须包含共识模式：只比对 (对象, revision) 会漏掉共识策略变化
        let key = (ObjectIdentifier(align), align.revision, AppSettings.consensusMode)
        if let last = lastKey, last == key { return }
        lastKey = key
        generation += 1
        let gen = generation
        computing = true

        DispatchQueue.global(qos: .userInitiated).async {
            // 快照移入后台；两遍全表扫描合并为一次融合单遍扫描
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
    // 共识序列横向查看：隐藏系统滚动条，改为拖拽平移
    @State private var consensusOffset: CGFloat = 0
    @State private var consensusDragStart: CGFloat?
    @State private var consensusTextWidth: CGFloat = 0

    private static let bucketLabels = ["0–20", "20–40", "40–60", "60–80", "80–100"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color(Minimal.border(dark: isDarkAppearance)))
                .frame(height: Minimal.hairline)
            if workspace.currentAlignment == nil {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        overviewSection
                        sectionDivider
                        qualitySection
                        sectionDivider
                        conservationSection
                        sectionDivider
                        phyloInfoSection
                        sectionDivider
                        consensusSection
                        if qualitySummary?.hasData == true {
                            sectionDivider
                            fastqQualitySection
                        }
                        sectionDivider
                        cursorSection
                    }
                    .padding(.horizontal, Minimal.space3)
                    .padding(.bottom, Minimal.space3)
                }
            }
        }
        .frame(width: max(220, min(460, width)))
        .background(Color(Minimal.surface(dark: isDarkAppearance)))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(Minimal.border(dark: isDarkAppearance)))
                .frame(width: Minimal.hairline)
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
            let snapshot = align.snapshot()
            let summary = AlignmentStatsCalculator.computeQualitySummary(snapshot)
            DispatchQueue.main.async {
                guard self.qualityGeneration == gen else { return }
                self.qualitySummary = summary
            }
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: Minimal.space2) {
            Text(L.s.statsTitle)
                .font(.system(size: Minimal.fontSM, weight: .semibold))
                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
            Spacer()
            if model.computing {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, Minimal.space3)
        .frame(height: 40)
        .background(Color(Minimal.panel(dark: isDarkAppearance)))
    }

    // MARK: 分区

    private var overviewSection: some View {
        section(L.s.statsOverview) {
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
        section(L.s.statsQuality) {
            if workspace.currentAlignment?.provenance == .notAligned {
                // 未比对输入下，列同源性不成立，统计值必须带警示而不是看起来正常
                HStack(alignment: .top, spacing: Minimal.space1 + 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: Minimal.fontXXS))
                        .foregroundColor(Color(Minimal.warning(dark: isDarkAppearance)))
                    Text(L.s.statsUnalignedBanner)
                        .font(.system(size: Minimal.fontXXS))
                        .foregroundColor(Color(Minimal.warning(dark: isDarkAppearance)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, Minimal.space1)
            }
            if let q = model.quality {
                statRow(L.s.statsMeanPairwise, pct(q.pooledPairwiseIdentity))
                statRow(L.s.statsMeanColIdentity, pct(model.meanColumnIdentity))
                statRow(L.s.statsMinColIdentity, pct(q.minColumnIdentity))
                statRow(L.s.statsMaxColIdentity, pct(q.maxColumnIdentity))
                statRow(L.s.statsGapCols, "\(q.gapColumns)")
            } else if model.computing {
                progressRow
            }
        }
    }

    private var conservationSection: some View {
        section(L.s.statsConservation) {
            let maxCount = max(1, model.histogram.max() ?? 1)
            HStack(alignment: .bottom, spacing: Minimal.space1) {
                ForEach(0..<5, id: \.self) { i in
                    VStack(spacing: Minimal.space1) {
                        Rectangle()
                            .fill(Color(Minimal.chartGradient(dark: isDarkAppearance, index: i)))
                            .frame(height: 3 + CGFloat(model.histogram[i]) / CGFloat(maxCount) * 34)
                        Text(Self.bucketLabels[i])
                            .font(.system(size: Minimal.fontXXS))
                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 34 + 12 + Minimal.space1 + 4, alignment: .bottom)
            .padding(.bottom, Minimal.space2)

            statRow(L.s.statsHighConserved, "\(Int((model.highConservedRatio * 100).rounded()))%")
        }
    }

    private var phyloInfoSection: some View {
        section(L.s.statsPhyloInfo) {
            if let q = model.quality {
                statRow(L.s.statsVariableSites, "\(q.variableSites)")
                statRow(L.s.statsParsimonySites, "\(q.parsimonySites)")
                statRow(L.s.statsSingletonSites, "\(q.singletonSites)")
            } else if model.computing {
                progressRow
            }
        }
    }

    private var consensusSection: some View {
        VStack(alignment: .leading, spacing: Minimal.space2) {
            HStack(spacing: Minimal.space2) {
                sectionTitle(L.s.statsConsensus)
                Spacer()
                MinimalIconButton(systemImage: "doc.on.doc", help: L.s.statsConsensusCopy, size: 22) {
                    copyConsensusToClipboard()
                }
            }

            // 共识序列完整显示：隐藏粗滚动条，鼠标/触控板直接拖拽平移
            GeometryReader { geo in
                let maxOffset = min(0, geo.size.width - consensusTextWidth)
                Text(model.consensusText)
                    .font(.system(size: Minimal.fontXS, design: .monospaced))
                    .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                    .textSelection(.disabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
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
            .frame(height: 18)
        }
        .padding(.vertical, Minimal.space3 - 2)
    }

    private var fastqQualitySection: some View {
        section(L.s.fastqQuality) {
            if let q = qualitySummary, q.hasData {
                statRow(L.s.fastqMeanPhred, String(format: "%.1f", q.meanPhred))
                statRow(L.s.fastqMinPhred, "\(q.minPhred)")
                statRow(L.s.fastqQ20, pct(q.q20Ratio))
                statRow(L.s.fastqQ30, pct(q.q30Ratio))
            }
        }
    }

    private var cursorSection: some View {
        section(L.s.statsCursor) {
            if let align = workspace.currentAlignment, align.seqCount > 0, align.length > 0 {
                let r = min(max(0, cursorRow), align.seqCount - 1)
                let c = min(max(0, cursorCol), align.length - 1)
                statRow(L.s.statsCursor, "\(r + 1):\(c + 1)")
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
        VStack(spacing: Minimal.space2) {
            Spacer()
            Text(L.s.statsEmptyTitle)
                .font(.system(size: Minimal.fontSM, weight: .medium))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 通用小组件

    /// 一个分区：标题 + 内容 + 统一的纵向节奏
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Minimal.space1 + 2) {
            sectionTitle(title)
            content()
        }
        .padding(.vertical, Minimal.space3 - 2)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color(Minimal.border(dark: isDarkAppearance)))
            .frame(height: Minimal.hairline)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: Minimal.fontXXS, weight: .semibold))
            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            .padding(.bottom, 2)
    }

    private var progressRow: some View {
        HStack(spacing: Minimal.space2) {
            ProgressView().controlSize(.mini)
            Text(L.s.statsComputing)
                .font(.system(size: Minimal.fontXS))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Minimal.space2) {
            Text(label)
                .font(.system(size: Minimal.fontXXS))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .lineLimit(1)
            Spacer(minLength: Minimal.space2)
            Text(value)
                .font(.system(size: Minimal.fontXXS, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 18)
    }

    private func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }

    private func residueString(at row: Int, col: Int, in align: Alignment) -> String {
        let b = align.residue(row: row, col: col)
        return b == 0x2D ? "-" : String(UnicodeScalar(b))
    }

    /// 直接取融合扫描的每列一致度（单一事实来源）
    private func columnIdentityText(col: Int) -> String {
        guard col >= 0, col < model.columnIdentities.count else { return "-" }
        return pct(model.columnIdentities[col])
    }

    private func copyConsensusToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(model.consensusText, forType: .string)
        workspace.showToast(L.s.statsConsensusCopied)
    }
}
