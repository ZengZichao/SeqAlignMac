//  SheetViews.swift
//  SeqAlignMac — 弹窗/表单视图（从 ContentView.swift 拆分）
//
//  包含：关于、新手向导、质量报告、配色图例、重命名、移动序列、未保存确认。

import AppKit
import SwiftUI

// MARK: - 关于

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    static let bibtex = """
    @software{seqalignmac,
      title  = {SeqAlignMac: A native macOS application for viewing, editing, and analysing multiple sequence alignments},
      year   = {2026},
      url    = {https://github.com/zengzichao/SeqAlignMac}
    }
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.s.aboutTitle)
                .font(.system(size: Minimal.fontXL, weight: .semibold))
            Text(L.s.aboutVersion)
                .font(.system(size: Minimal.fontSM))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            Text(L.s.aboutDesc)
                .font(.system(size: Minimal.fontSM))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            Divider()
                .background(Color(Minimal.border(dark: isDarkAppearance)))
            Text(L.s.aboutFeatures)
                .font(.system(size: Minimal.fontSM))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            Text(L.s.aboutRefs)
                .font(.system(size: Minimal.fontSM))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            Text(L.s.aboutLicense)
                .font(.system(size: Minimal.fontSM))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            Text(L.s.aboutCitation)
                .font(.system(size: Minimal.fontXS2, weight: .semibold))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .padding(.top, 2)
            HStack(alignment: .top, spacing: 8) {
                Text(AboutView.bibtex)
                    .font(.system(size: Minimal.fontXS2, design: .monospaced))
                    .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Minimal.space2)
                    .background(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                        .fill(Color(Minimal.card(dark: isDarkAppearance))))
                    .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                        .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AboutView.bibtex, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: Minimal.fontXS2))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                }
                .buttonStyle(.plain)
                .help(L.s.menuCopy)   // tooltip 描述动作而非结果
            }
            Spacer()
            HStack {
                Spacer()
                MinimalPrimaryButton(title: L.s.close) { dismiss() }
                    .keyboardShortcut(.escape)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 460, height: 420)
        .minimalSheetContainer()
    }
}

// MARK: - 新手向导

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    private var steps: [String] {
        let zh = LanguageManager.shared.language == .zh
        if zh {
            return [
                "打开已比对的文件（FASTA/NEXUS/PHYLIP/CLUSTAL/MSF/Stockholm/FASTQ）；未比对序列用「工具 ▸ 运行比对」调用本地 muscle/mafft",
                "Cmd+Shift+1/2/3/4 切换配色；左侧栏底部切换浅/深/跟随系统外观与中英文语言",
                "Cmd+F 搜索序列内容或物种名称（支持正则表达式；序列内容搜索兼容 IUPAC 简并码）；0 命中会明确提示「无匹配」",
                "Cmd+Shift+T 翻译为氨基酸（六阅读框；结果默认在新窗口打开，原比对保留）",
                "工具菜单查看引物 Tm（自动预填光标行，可「从选区填入」）与比对质量",
                "Cmd+C 复制选中区域（画布内直接可用）；Cmd+A 全选；Cmd+Z / Cmd+Shift+Z 撤销/重做",
                "Cmd+'+'/'-' 缩放字号；左侧栏显示当前比例，点击可重置",
                "方向键移动光标，Option+方向键框选；拖动名称列分隔线调宽度；Cmd+Shift+P 命令面板",
            ]
        } else {
            return [
                "Open an aligned file (FASTA/NEXUS/PHYLIP/CLUSTAL/MSF/Stockholm/FASTQ); use Tools ▸ Run Alignment for unaligned sequences (local muscle/mafft)",
                "Cmd+Shift+1/2/3/4 switch color scheme; bottom of left sidebar toggles light/dark/system appearance and CN/EN language",
                "Cmd+F search sequence content or species names (regex supported; IUPAC degenerate codes for content search); 0 hits show 'No matches'",
                "Cmd+Shift+T translate to amino acid (six reading frames; results open in new window by default)",
                "Tools menu for primer Tm (auto-fills from cursor row, 'Fill from selection' available) and alignment quality",
                "Cmd+C copy selection (available in canvas); Cmd+A select all; Cmd+Z / Cmd+Shift+Z undo/redo",
                "Cmd+'+'/'-' zoom font size; left sidebar shows current ratio, click to reset",
                "Arrow keys move cursor, Option+arrows select block; drag name column divider to adjust width; Cmd+Shift+P command palette",
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.s.guideTitle)
                .font(.system(size: Minimal.fontXL, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).")
                                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                                .fontWeight(.medium)
                                .frame(width: 20, alignment: .leading)
                            Text(step)
                                .font(.system(size: Minimal.fontSM))
                                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(maxHeight: 300)
            .background(RoundedRectangle(cornerRadius: Minimal.radiusMD)
                .fill(Color(Minimal.card(dark: isDarkAppearance))))
            .overlay(RoundedRectangle(cornerRadius: Minimal.radiusMD)
                .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
            Spacer()
            HStack {
                Spacer()
                MinimalPrimaryButton(title: L.s.guideStart) { dismiss() }
                    .keyboardShortcut(.return)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 520, height: 460)
        .minimalSheetContainer()
    }
}

// MARK: - 质量报告

/// 质量报告计算模型。
/// 统计不放在 body 里求值：大比对的全表统计可达数秒，直接写在 body 会冻结
/// 主线程，且 body 多次求值会让统计重复执行。采用与 StatsPanelModel 相同的
/// 范式：@StateObject + onAppear 触发 + 后台融合扫描 + generation 代次守卫回写。
final class QualityReportModel: ObservableObject {
    @Published var quality: AlignmentQuality?
    @Published var columnCount: Int = 0
    @Published var fastq: FastqQualitySummary?
    @Published var computing = false

    private var generation = 0

    func compute(alignment: Alignment?) {
        guard let align = alignment else {
            generation += 1
            quality = nil
            fastq = nil
            columnCount = 0
            computing = false
            return
        }
        generation += 1
        let gen = generation
        computing = true
        DispatchQueue.global(qos: .userInitiated).async {
            // 后台操作持有快照；三次全表统计以融合单遍扫描一次完成
            let snapshot = align.snapshot()
            let fused = AlignmentStatsCalculator.fusedScan(snapshot)
            let fastq = AlignmentStatsCalculator.computeQualitySummary(snapshot)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == gen else { return }
                self.quality = fused.quality
                self.columnCount = fused.identities.count
                self.fastq = fastq
                self.computing = false
            }
        }
    }
}

struct QualityReportView: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    @StateObject private var model = QualityReportModel()
    private var align: Alignment? { workspace.currentAlignment }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.s.qualityTitle)
                .font(.system(size: Minimal.fontXL, weight: .semibold))

            if let align = align {
                if model.computing && model.quality == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L.s.statsComputing)
                            .font(.system(size: Minimal.fontSM))
                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Minimal.space3)
                } else if let quality = model.quality {
                    VStack(alignment: .leading, spacing: 8) {
                        qualityRow(L.s.statsMeanPairwise, String(format: "%.2f%%", quality.pooledPairwiseIdentity * 100))
                        qualityRow(L.s.statsMinColIdentity, String(format: "%.2f%%", quality.minColumnIdentity * 100))
                        qualityRow(L.s.statsMaxColIdentity, String(format: "%.2f%%", quality.maxColumnIdentity * 100))
                        qualityRow(L.s.statsGapCols, "\(quality.gapColumns)")
                        qualityRow(L.s.statsTotalCols, "\(quality.totalColumns)")
                        qualityRow(L.s.statsConsensus, "\(model.columnCount)")
                        // 该行显示的是共识列数，标签用「共识长度」语义
                        if let fastq = model.fastq, fastq.hasData {
                            qualityRow(L.s.fastqMeanPhred, String(format: "%.1f", fastq.meanPhred))
                            qualityRow(L.s.fastqQ20, String(format: "%.1f%%", fastq.q20Ratio * 100))
                            qualityRow(L.s.fastqQ30, String(format: "%.1f%%", fastq.q30Ratio * 100))
                        }
                    }
                    .padding(Minimal.space3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                        .fill(Color(Minimal.card(dark: isDarkAppearance))))
                    .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                        .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
                }

                if !align.charsets.isEmpty {
                    Divider()
                        .background(Color(Minimal.border(dark: isDarkAppearance)))
                    Text(L.s.qualityCharset)
                        .font(.system(size: Minimal.fontSM, weight: .semibold))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    ForEach(align.charsets, id: \.name) { cs in
                        let rangeStrs = cs.ranges.map { r in
                            r.start == r.end ? "\(r.start)" : "\(r.start)-\(r.end)"
                        }
                        Text("  \(cs.name): \(rangeStrs.joined(separator: ", "))")
                            .font(.system(size: Minimal.fontXS))
                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    }
                }
            } else {
                Text(L.s.qualityNoFile)
                    .font(.system(size: Minimal.fontSM))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            }

            Spacer()
            Text(L.s.statsMethodNote)
                .font(.system(size: Minimal.fontXXS))
                .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                MinimalPrimaryButton(title: L.s.close) { dismiss() }
                    .keyboardShortcut(.escape)
            }
        }
        .padding(Minimal.space5)
        // 固定高度无滚动时 charset 较多会导致内容溢出：
        // 宽度固定、高度取最小值，内容交给 ScrollView（与 SettingsView 一致）。
        .frame(width: 460)
        .frame(minHeight: 400)
        .minimalSheetContainer()
        .onAppear { model.compute(alignment: workspace.currentAlignment) }
        .onChange(of: workspace.currentAlignment?.revision) { _, _ in
            model.compute(alignment: workspace.currentAlignment)
        }
    }

    private func qualityRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .monospacedDigit()
                .fontWeight(.medium)
                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
        }
        .font(.system(size: Minimal.fontSM))
    }
}

// MARK: - 配色图例弹窗

struct LegendPopover: View {
    let scheme: ColorScheme
    private var isDark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.s.legendTitle)
                .font(.system(size: Minimal.fontXL, weight: .semibold))
            let entries = ColorSchemeLegend.entries(for: scheme, dark: isDark)
            ForEach(entries.indices, id: \.self) { i in
                let e = entries[i]
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(e.color))
                        .frame(width: 16, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
                    Text(e.symbol)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 84, alignment: .leading)
                    Text(e.note)
                        .font(.system(size: Minimal.fontXS))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                }
            }
            Text(L.s.legendDarkNote)
                .font(.system(size: Minimal.fontXS2))
                .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            Divider()
                .padding(.vertical, 4)
            Text(L.s.legendCanvasOps)
                .font(.system(size: Minimal.fontSM, weight: .semibold))
            VStack(alignment: .leading, spacing: Minimal.space1) {
                Text(L.s.legendOp1)
                Text(L.s.legendOp2)
                Text(L.s.legendOp3)
                Text(L.s.legendOp4)
                Text(L.s.legendOp5)
                Text(L.s.legendOp6)
            }
            .font(.system(size: Minimal.fontXS2))
            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Minimal.space4)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: Minimal.radiusMD)
            .fill(Color(Minimal.surface(dark: isDarkAppearance))))
        .overlay(RoundedRectangle(cornerRadius: Minimal.radiusMD)
            .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
    }
}

// MARK: - 重命名视图

struct RenameView: View {
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var row: Int
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 16) {
            Text(L.s.renameTitle).font(.system(size: Minimal.fontXL, weight: .semibold))
            MinimalTextField(placeholder: L.s.renamePlaceholder, text: $name)
            HStack {
                Spacer()
                MinimalSecondaryButton(title: L.s.cancel) { isPresented = false }
                MinimalPrimaryButton(title: L.s.renameConfirm) {
                    // 空串/纯空格名称会让画布与 NJ 树叶标签为空、GFF seqid 匹配失效
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty,
                          let align = workspace.currentAlignment,
                          row < align.seqCount else {
                        // 空名不执行重命名，保持弹窗打开让用户看到操作未生效
                        return
                    }
                    let oldName = align.sequences[row].name
                    // 未改名不入撤销栈、不置脏
                    guard trimmed != oldName else {
                        isPresented = false
                        return
                    }
                    let cmd = RenameCommand(index: row, oldName: oldName, newName: trimmed)
                    UndoRedoCoordinator.shared.execute(cmd)
                    isPresented = false
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 350, height: 150)
        .minimalSheetContainer()
    }
}

// MARK: - 移动序列视图

struct MoveSequenceView: View {
    @Binding var isPresented: Bool
    @Binding var from: Int
    @Binding var to: Int
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 16) {
            Text(L.s.moveTitle).font(.system(size: Minimal.fontXL, weight: .semibold))
            if let align = workspace.currentAlignment {
                Text("\(L.s.moveCount) \(align.seqCount)")
                HStack {
                    Text(L.s.moveFrom)
                    Stepper("\(from + 1)", value: $from, in: 0...max(0, align.seqCount - 1))
                    Text(L.s.moveTo)
                    Stepper("\(to + 1)", value: $to, in: 0...max(0, align.seqCount - 1))
                }
            }
            HStack {
                Spacer()
                MinimalSecondaryButton(title: L.s.cancel) { isPresented = false }
                MinimalPrimaryButton(title: L.s.moveConfirm) {
                    // from == to 是空操作：execute 前有守卫不会移动序列，
                    // 但仍会污染撤销栈并把文档置脏，这里直接禁用
                    let cmd = MoveSeqCommand(fromIndex: from, toIndex: to)
                    UndoRedoCoordinator.shared.execute(cmd)
                    isPresented = false
                }
                .disabled(from == to)
                .keyboardShortcut(.return)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 350, height: 180)
        .minimalSheetContainer()
    }
}

// MARK: - 关闭守卫确认

struct UnsavedChangesView: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 16) {
            Text(L.s.unsavedTitle)
                .font(.system(size: Minimal.fontXL, weight: .semibold))
            Text("\"\(workspace.currentFileName.isEmpty ? L.s.unnamed : workspace.currentFileName)\" \(L.s.unsavedDesc)")
                .font(.system(size: Minimal.fontBase))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                MinimalSecondaryButton(title: L.s.cancel) {
                    workspace.pendingCloseRequest = false
                    workspace.pendingCloseIsTab = false
                    if let ts = WindowRegistry.shared.tabState(containing: workspace) {
                        ts.pendingCloseTabID = nil
                    }
                }
                .keyboardShortcut(.cancelAction)
                MinimalSecondaryButton(title: L.s.unsavedDontSave) {
                    workspace.isDirty = false
                    workspace.pendingCloseRequest = false
                    DispatchQueue.main.async { completeClose() }
                }
                MinimalPrimaryButton(title: L.s.unsavedSave) {
                    // 保存已在后台执行，写盘完成后经回调继续关闭流程；
                    // 失败（success=false）时保留弹窗让用户看到错误
                    SaveManager.shared.saveCurrent(for: workspace) { success in
                        guard success else { return }
                        workspace.pendingCloseRequest = false
                        DispatchQueue.main.async { completeClose() }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 400, height: 170)
        .minimalSheetContainer()
    }

    private func completeClose() {
        let isTab = workspace.pendingCloseIsTab
        workspace.pendingCloseIsTab = false
        if isTab {
            if let ts = WindowRegistry.shared.tabState(containing: workspace) {
                let tabID = ts.pendingCloseTabID
                ts.pendingCloseTabID = nil
                if let id = tabID {
                    ts.closeTabNow(id)
                }
            }
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}
