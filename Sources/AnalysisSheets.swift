//  AnalysisSheets.swift
//  SeqAlignMac — 分析工具弹窗
//
//  包含：序列 Logo（信息含量）、NJ 树（Newick + 树状图）、滑动窗口一致度、
//  GFF3 注释浏览器（跳转到比对列）。

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 序列 Logo（Schneider & Stephens 1990）

struct SequenceLogoView: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    @State private var logoColumns: [LogoColumn] = []
    @State private var logoGeneration = 0
    @State private var startCol = 0
    /// 因 maxColumns 截断而未参与计算的列数（界面上必须显示）
    @State private var logoOmittedColumns = 0

    private let colsPerPage = 120
    private var totalPages: Int {
        max(1, (logoColumns.count + colsPerPage - 1) / colsPerPage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.s.logoTitle).font(.system(size: Minimal.fontXL, weight: .semibold))
                Spacer()
                // 截断必须可见：仅计算前若干列时若不提示，用户会以为翻页覆盖了整条序列
                if logoOmittedColumns > 0 {
                    Text("\(L.s.logoTruncated) \(logoOmittedColumns)")
                        .font(.system(size: Minimal.fontXXS))
                        .foregroundColor(.orange)
                }
                if totalPages > 1 {
                    MinimalBarButton(title: "‹") { startCol = max(0, startCol - colsPerPage) }
                    Text("\(startCol / colsPerPage + 1) / \(totalPages)")
                        .font(.system(size: Minimal.fontXS)).monospacedDigit()
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    MinimalBarButton(title: "›") {
                        startCol = min(max(0, logoColumns.count - colsPerPage), startCol + colsPerPage)
                    }
                }
                MinimalSecondaryButton(title: L.s.close) { dismiss() }
                    .keyboardShortcut(.escape)
            }

            Text(L.s.logoHint)
                .font(.system(size: Minimal.fontXS))
                .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))

            logoCanvas
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .background(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                    .fill(Color(Minimal.card(dark: isDarkAppearance))))
                .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                    .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
        }
        .padding(Minimal.space5)
        .frame(width: 720, height: 400)
        .minimalSheetContainer()
        .onAppear { recompute() }
        .onChange(of: workspace.currentAlignment?.revision) { _, _ in recompute() }
    }

    private func recompute() {
        guard let align = workspace.currentAlignment else { return }
        logoGeneration += 1
        let generation = logoGeneration
        let snapshot = align.snapshot()
        DispatchQueue.global(qos: .userInitiated).async {
            // LogoCalculator 默认只算前 4000 列（逐列成本 O(列×行)，截断本身是对的），
            // 但截断必须显式告知：否则 12 kb 比对显示"34 页"，用户会以为自己翻完了整条序列。
            let computed = LogoCalculator.compute(snapshot)
            DispatchQueue.main.async {
                // 代次守卫：修订快速变化时丢弃过期结果
                guard generation == logoGeneration else { return }
                logoColumns = computed.columns
                logoOmittedColumns = computed.omittedColumns
                startCol = 0
            }
        }
    }

    private var logoCanvas: some View {
        Canvas { context, size in
            let maxBits: Double = workspace.currentAlignment?.datatype == .nucleicAcid ? 2.0 : 4.3
            let plotH = size.height - 26
            let plotW = size.width - 8
            guard !logoColumns.isEmpty else { return }
            let n = min(colsPerPage, logoColumns.count - startCol)
            let colW = plotW / CGFloat(n)

            // 纵轴刻度（bits）
            let axisFont = Font.system(size: 8)
            for b in stride(from: 0.0, through: maxBits, by: maxBits / 4) {
                let y = plotH - CGFloat(b / maxBits) * plotH
                let text = Text(String(format: "%.1f", b)).font(axisFont)
                    .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                context.draw(context.resolve(text), at: CGPoint(x: 12, y: y))
                var path = Path()
                path.move(to: CGPoint(x: 24, y: y))
                path.addLine(to: CGPoint(x: size.width - 8, y: y))
                context.stroke(path, with: .color(Color(Minimal.border(dark: isDarkAppearance)).opacity(0.4)),
                               lineWidth: 0.5)
            }

            for i in 0..<n {
                let col = logoColumns[startCol + i]
                let x = 24 + CGFloat(i) * colW
                var yBase = plotH
                for stack in col.stacks {
                    let h = CGFloat(stack.fraction * col.totalBits / maxBits) * plotH
                    guard h > 0.4 else { continue }
                    let color = Color(ColorResolver.logoColor(stack.residue,
                                                              scheme: workspace.currentScheme,
                                                              dark: isDarkAppearance))
                    let rect = CGRect(x: x + 1, y: yBase - h, width: max(1, colW - 2), height: h)
                    context.fill(Path(rect), with: .color(color))
                    // 字母
                    let ch = String(UnicodeScalar(stack.residue))
                    let text = Text(ch).font(.system(size: min(9, max(5, colW - 2)), design: .monospaced).weight(.bold))
                        .foregroundColor(Color(Minimal.surface(dark: isDarkAppearance)))
                    context.draw(context.resolve(text), at: CGPoint(x: rect.midX, y: rect.midY))
                    yBase -= h
                }
                // 列号
                if (col.position + 1) % 10 == 0 {
                    let t = Text("\(col.position + 1)").font(.system(size: 8))
                        .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                    context.draw(context.resolve(t), at: CGPoint(x: x + colW / 2, y: size.height - 8))
                }
            }
        }
    }
}

// MARK: - NJ 树

struct TreeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    @State private var newick = ""
    @State private var computing = false
    // dirty 标记：计算期间到来的 revision 变化由它记录而不是被 !computing 守卫丢弃，
    // 完成后按需补算，避免树停留在旧版本
    @State private var pendingRecompute = false
    @State private var treeSamplingNote = ""
    @State private var treeClampedBranches = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.s.treeTitle).font(.system(size: Minimal.fontXL, weight: .semibold))
                Spacer()
                if computing { ProgressView().controlSize(.small) }
                MinimalSecondaryButton(title: L.s.treeCopyNewick) { copyNewick() }
                MinimalSecondaryButton(title: L.s.close) { dismiss() }
                    .keyboardShortcut(.escape)
            }
            Text(L.s.treeHint)
                .font(.system(size: Minimal.fontXS))
                .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))

            // 抽样、负分支钳制、未校正距离模型都必须显式出现在界面上
            if !treeSamplingNote.isEmpty {
                Label(treeSamplingNote, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: Minimal.fontXS))
                    .foregroundColor(.orange)
            }
            if treeClampedBranches > 0 {
                Text("\(L.s.treeClampedBranches) \(treeClampedBranches)")
                    .font(.system(size: Minimal.fontXXS))
                    .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
            }
            Text(L.s.treeModelUncorrected)
                .font(.system(size: Minimal.fontXXS))
                .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))

            ScrollView([.horizontal, .vertical]) {
                Text(newick.isEmpty ? L.s.statsComputing : newick)
                    .font(.system(size: Minimal.fontXS, design: .monospaced))
                    .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Minimal.space3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                .fill(Color(Minimal.card(dark: isDarkAppearance))))
            .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
        }
        .padding(Minimal.space5)
        .frame(width: 640, height: 380)
        .minimalSheetContainer()
        .onAppear { recompute() }
        .onChange(of: workspace.currentAlignment?.revision) { _, _ in recompute() }
    }

    private func recompute() {
        guard let align = workspace.currentAlignment else { return }
        if computing {
            pendingRecompute = true
            return
        }
        computing = true
        let snapshot = align.snapshot()
        DispatchQueue.global(qos: .userInitiated).async {
            // 建树默认等距抽样到 200 条，避免固定截取前 200 条引入偏差；
            // 但抽样事实必须声明——未声明的抽样比抽样本身危害大得多：
            // 1200 条序列的提交会得到一棵只有 200 个 tip 的树，
            // 用户复制走、贴进手稿，以为全类群都在。
            let result = PhyloBuilder.njTree(snapshot)
            DispatchQueue.main.async {
                // 界面用本地化前缀 + 数字，避免把英文诊断串直接贴进中文界面
                treeSamplingNote = result.wasSampled
                    ? "\(L.s.treeSampledNote) \(result.sequencesUsed) / \((result.sequencesTotal))"
                    : ""
                treeClampedBranches = result.clampedBranchLengths
                newick = result.newick
                computing = false
                if pendingRecompute {
                    pendingRecompute = false
                    recompute()
                }
            }
        }
    }

    private func copyNewick() {
        NSPasteboard.general.clearContents()
        // Newick 串本身带 [&sampled=...] 注释，复制走也带着抽样事实
        NSPasteboard.general.setString(newick, forType: .string)
        workspace.showToast(L.s.toastCopied)
    }
}

// MARK: - 滑动窗口一致度

struct WindowChartSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    @State private var windowSize: Double = 50
    @State private var points: [(center: Int, identity: Double)] = []
    @State private var computing = false
    @State private var windowGeneration = 0
    // 每列一致度与窗口大小无关，按 (对象, revision) 缓存——拖动 Slider
    // 只做 O(n) 的窗口平均，不必每次触发全表重算
    @State private var identitiesCache: (align: Alignment, revision: UInt64, identities: [Double])?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.s.windowTitle).font(.system(size: Minimal.fontXL, weight: .semibold))
                Spacer()
                if computing { ProgressView().controlSize(.small) }
                MinimalSecondaryButton(title: L.s.close) { dismiss() }
                    .keyboardShortcut(.escape)
            }

            HStack(spacing: 8) {
                Text("\(L.s.windowSize): \(Int(windowSize))")
                    .font(.system(size: Minimal.fontSM))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    .frame(width: 120, alignment: .leading)
                Slider(value: $windowSize, in: 5...500, step: 5) { EmptyView() }
                    .frame(width: 280)
                    .tint(Color(Minimal.primary(dark: isDarkAppearance)))
                    .accessibilityLabel(L.s.windowSize)
                    .onChange(of: windowSize) { _, _ in recompute() }
            }

            chart
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .background(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                    .fill(Color(Minimal.card(dark: isDarkAppearance))))
                .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                    .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
        }
        .padding(Minimal.space5)
        .frame(width: 640, height: 380)
        .minimalSheetContainer()
        .onAppear { recompute() }
    }

    private func recompute() {
        guard let align = workspace.currentAlignment else { return }
        // 防重入 + 代次守卫：拖动 Slider 会触发多次 onChange，
        // 完成顺序不定时慢的旧窗口结果会覆盖新结果
        windowGeneration += 1
        let generation = windowGeneration
        let w = Int(windowSize)

        // identities 缓存命中时只做窗口平均（同步、O(n)，无需后台）
        if let cached = identitiesCache,
           cached.align === align, cached.revision == align.revision {
            points = PhyloBuilder.windowAverages(from: cached.identities, window: w)
            computing = false
            return
        }

        computing = true
        let snapshot = align.snapshot()
        let snapshotRevision = align.revision   // 以快照时刻为准，不用回调时刻的 revision
        DispatchQueue.global(qos: .userInitiated).async {
            let identities = AlignmentStatsCalculator.columnIdentities(snapshot)
            let result = PhyloBuilder.windowAverages(from: identities, window: w)
            DispatchQueue.main.async {
                guard generation == windowGeneration else { return }
                // 缓存键必须用快照时刻的 revision：若记回调执行时刻的 align.revision，
                // 快照之后发生的编辑会让缓存被标成"新版本的结果"，编辑后拖动窗口滑块
                // 命中陈旧缓存，曲线底层仍是编辑前那份比对的每列一致度。
                identitiesCache = (align, snapshotRevision, identities)
                points = result
                computing = false
            }
        }
    }

    private var chart: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            let plot = CGRect(x: 30, y: 8, width: size.width - 40, height: size.height - 30)

            // 网格与纵轴
            for frac in stride(from: 0.0, through: 1.0, by: 0.25) {
                let y = plot.maxY - CGFloat(frac) * plot.height
                var path = Path()
                path.move(to: CGPoint(x: plot.minX, y: y))
                path.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(path, with: .color(Color(Minimal.border(dark: isDarkAppearance)).opacity(0.4)),
                               lineWidth: 0.5)
                let label = Text("\(Int(frac * 100))%").font(.system(size: 8))
                    .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                context.draw(context.resolve(label), at: CGPoint(x: 14, y: y))
            }

            let x0 = Double(points[0].center), x1 = Double(points[points.count - 1].center)
            guard x1 > x0 else { return }
            var line = Path()
            for (i, p) in points.enumerated() {
                let x = plot.minX + CGFloat((Double(p.center) - x0) / (x1 - x0)) * plot.width
                let y = plot.maxY - CGFloat(p.identity) * plot.height
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(line, with: .color(Color(Minimal.primary(dark: isDarkAppearance))), lineWidth: 1.5)

            // 横轴端点标注
            // 横轴两端一律用真实中心列：数据点归一化在 points[0].center…points[last].center
            // 上，窗口 50 时左端真实对应第 25 列；若左端写死 "1"，同一根轴左端会
            // 标错 window/2 列、右端标真值，读图者定位高分歧区段会整体左偏。
            let l0 = Text("\(Int(x0 + 1))").font(.system(size: 8)).foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
            context.draw(context.resolve(l0), at: CGPoint(x: plot.minX, y: size.height - 8))
            let l1 = Text("\(Int(x1))").font(.system(size: 8)).foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
            context.draw(context.resolve(l1), at: CGPoint(x: plot.maxX, y: size.height - 8))
        }
    }
}

// MARK: - GFF3 注释浏览器

struct AnnotationSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    @State private var features: [GffFeature] = []
    @State private var fileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.s.annotTitle).font(.system(size: Minimal.fontXL, weight: .semibold))
                Spacer()
                MinimalSecondaryButton(title: L.s.annotLoad) { loadGff() }
                MinimalSecondaryButton(title: L.s.close) { dismiss() }
                    .keyboardShortcut(.escape)
            }

            if features.isEmpty {
                Text(L.s.annotNone)
                    .font(.system(size: Minimal.fontSM))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        headerCell(L.s.annotSeq, width: 150)
                        headerCell(L.s.annotType, width: 90)
                        headerCell(L.s.annotRange, width: 130)
                        headerCell(L.s.annotName)
                        Spacer().frame(width: 60)
                    }
                    Divider()
                    List {
                        ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                            HStack(spacing: 0) {
                                cell(f.seqid, width: 150)
                                cell(f.type, width: 90)
                                cell("\(f.start)–\(f.end)", width: 130)
                                cell(f.name)
                                Spacer().frame(width: Minimal.space1)
                                MinimalBarButton(title: L.s.annotJump) { jump(to: f) }
                            }
                            .listRowInsets(EdgeInsets())
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                    .fill(Color(Minimal.card(dark: isDarkAppearance))))
                .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                    .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Minimal.radiusSM))

                if !fileName.isEmpty {
                    Text("\(fileName) · \(features.count)")
                        .font(.system(size: Minimal.fontXXS))
                        .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                }
            }
        }
        .padding(Minimal.space5)
        .frame(width: 720, height: 440)
        .minimalSheetContainer()
    }

    private func headerCell(_ t: String, width: CGFloat? = nil) -> some View {
        Text(t)
            .font(.system(size: Minimal.fontXS, weight: .semibold))
            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            .frame(width: width, alignment: .leading)
    }

    private func cell(_ t: String, width: CGFloat? = nil) -> some View {
        Text(t)
            .font(.system(size: Minimal.fontXS))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
            .frame(width: width, alignment: .leading)
    }

    /// GFF 的 1-based 未比对坐标 → 比对列号（gap-aware）。
    /// 沿该行累计非空位计数找到第 sequenceStart 个残基所在的列，sequenceEnd 同理；
    /// 长度也按"该区间内的非空位列数"给出，而不是 end-start+1。
    static func sequenceToColumn(_ residues: [UInt8], sequenceStart: Int, sequenceEnd: Int)
        -> (startCol: Int?, width: Int) {
        var seen = 0
        var startCol: Int? = nil
        var endCol: Int? = nil
        for (i, b) in residues.enumerated() {
            if ResidueAlphabet.isGap(b) { continue }
            seen += 1
            if seen == sequenceStart { startCol = i }
            if seen == sequenceEnd { endCol = i; break }
        }
        guard let s = startCol else { return (nil, 0) }
        let e = endCol ?? (residues.count - 1)
        // 区间宽度按列数计（含区间内的插入列），保证高亮覆盖整个特征
        return (s, max(1, e - s + 1))
    }

    /// seqid 名称匹配优先精确命中：若用 `contains` 兜底，`ref` 会命中第一条
    /// 名字里含 ref 的序列而不一定是目标序列。
    static func featureRow(forSeqid seqid: String, names: [String]) -> Int? {
        if let exact = names.firstIndex(of: seqid) { return exact }
        let trimmed = seqid.split(separator: ":").last.map(String.init) ?? seqid
        if let bySuffix = names.firstIndex(where: { $0 == trimmed }) { return bySuffix }
        return names.firstIndex(where: { $0.hasPrefix(seqid) || seqid.hasPrefix($0) })
    }

    private func loadGff() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gff") ?? .plainText,
                                     UTType(filenameExtension: "gff3") ?? .plainText,
                                     .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            // try? 全静默会让文件不可读 / 格式错误 / 解析 0 条无法区分，故分档提示
            guard let data = try? Data(contentsOf: url) else {
                workspace.showToast(L.s.annotLoadFailRead)
                return
            }
            let parsed = GffParser.parse(data)
            features = parsed
            fileName = url.lastPathComponent
            if parsed.isEmpty {
                workspace.showToast(L.s.annotLoadEmpty)
            } else {
                    // 成功载入的提示带条数与文件名（避免与导出语义混淆）
                    workspace.showToast("\(L.s.annotLoaded) \(parsed.count) \(url.lastPathComponent)")
            }
        }
    }

    /// 跳转：定位到注释起始列（借用搜索命中滚动机制）
    private func jump(to f: GffFeature) {
        guard let align = workspace.currentAlignment else { return }
        // seqid 匹配失败时提示，不能静默落到第 0 行并覆盖搜索结果。
        // 匹配精确优先：用 `contains` 兜底时 seqid="ref" 会命中第一条名字里
        // 含 ref 的序列而不一定是目标序列、跳到错误行；精确未命中再退化为前缀/后缀匹配。
        guard let idx = Self.featureRow(forSeqid: f.seqid, names: align.sequences.map { $0.name }) else {
            workspace.showToast("\(L.s.annotSeqidNotFound) \(f.seqid)")
            return
        }
        let row = min(idx, max(0, align.seqCount - 1))
        // GFF 的 start/end 是该序列自身的 1-based 未比对坐标，
        // 而 SearchHit.position 在画布侧按比对列号消费，两者不可混用：
        // 只要有上游 indel，把坐标当列号用就会让跳转落点偏移"上游空位数"列，
        // 高亮长度也错。因此沿该行累计非空位计数做 gap-aware 映射。
        let mapped = Self.sequenceToColumn(align.sequences[row].residues,
                                           sequenceStart: f.start, sequenceEnd: f.end)
        guard let startCol = mapped.startCol else {
            workspace.showToast(L.s.gffFeatureNotInAlignment)
            return
        }
        let len = max(1, mapped.width)
        workspace.searchHits = [SearchHit(seqIndex: row, position: startCol, matchLen: len)]
        workspace.currentHitIndex = 0
        dismiss()
    }
}
