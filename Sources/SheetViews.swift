//  SheetViews.swift
//  SeqAlignMac — 弹窗/表单视图
//
//  弹窗只铺底色，边框与圆角由系统 sheet 窗口负责；内容用 0.5pt 水平线分区，
//  不再在弹窗里嵌套圆角卡片。字号只有 16（标题）/ 13（正文）/ 12（辅助）。

import AppKit
import SwiftUI

// MARK: - 弹窗通用构件

struct SheetTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: Minimal.fontXL, weight: .semibold))
            .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SheetSectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: Minimal.fontXXS, weight: .semibold))
            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SheetHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color(Minimal.border(dark: isDarkAppearance)))
            .frame(height: Minimal.hairline)
    }
}

/// 统一的「标签左、数值右」行：等宽数值 + 首基线对齐
struct SheetStatRow: View {
    let label: String
    let value: String
    var body: some View {
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
        .frame(minHeight: 20)
    }
}

// MARK: - 关于

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    static let bibtex = """
    @software{seqalignmac,
      title  = {SeqAlignMac: A native macOS application for viewing, editing, and analysing multiple sequence alignments},
      year   = {2026},
      url    = {https://github.com/ZengZichao/SeqAlignMac}
    }
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 应用名用衬线体：这是全应用唯一的品牌时刻
            Text(L.s.aboutTitle)
                .font(.system(size: Minimal.fontXL, weight: .semibold, design: .serif))
                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))

            Text(L.s.aboutVersion)
                .font(.system(size: Minimal.fontXXS))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .padding(.top, Minimal.space1)

            Text(L.s.aboutDesc)
                .font(.system(size: Minimal.fontSM))
                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                .padding(.top, Minimal.space3)

            SheetHairline()
                .padding(.vertical, Minimal.space4)

            SheetSectionTitle(text: L.s.aboutCitation)
                .padding(.bottom, Minimal.space2)

            HStack(alignment: .top, spacing: Minimal.space2) {
                Text(AboutView.bibtex)
                    .font(.system(size: Minimal.fontXXS, design: .monospaced))
                    .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Minimal.space3)
                    .background(Color(Minimal.card(dark: isDarkAppearance)))
                    .overlay(
                        Rectangle()
                            .stroke(Color(Minimal.border(dark: isDarkAppearance)),
                                    lineWidth: Minimal.hairline)
                    )

                MinimalIconButton(systemImage: "doc.on.doc", help: L.s.menuCopy) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AboutView.bibtex, forType: .string)
                }
            }

            Spacer(minLength: Minimal.space4)

            HStack(alignment: .firstTextBaseline) {
                Text(L.s.aboutLicense)
                    .font(.system(size: Minimal.fontXXS))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                Spacer()
                MinimalSecondaryButton(title: L.s.close) { dismiss() }
                    .keyboardShortcut(.escape)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 480, height: 400)
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
                "打开已比对文件：FASTA、NEXUS、PHYLIP、CLUSTAL、MSF、Stockholm、FASTQ；未比对序列用「运行比对」调用本机 MAFFT 或 MUSCLE",
                "⇧⌘1/2/3/4 切换配色；侧栏底部切换外观与语言",
                "⌘F 搜索残基或序列名称；残基检索支持 IUPAC 简并码与正则表达式",
                "⇧⌘T 翻译核酸序列，默认在新窗口打开，原比对保留",
                "「引物计算」自动预填光标行，也可从选区填入；Tm 采用最近邻法",
                "⌘C 复制选中区域，⌘A 全选，⌘Z 撤销，⇧⌘Z 重做",
                "⌘+ 与 ⌘- 调整字号；点击侧栏比例可重置",
                "方向键移动光标，Option 加方向键框选，⇧⌘P 打开命令面板",
            ]
        } else {
            return [
                "Open an aligned file: FASTA, NEXUS, PHYLIP, CLUSTAL, MSF, Stockholm or FASTQ. Use Run Alignment for unaligned sequences with a local MAFFT or MUSCLE install",
                "⇧⌘1/2/3/4 switch color schemes; the sidebar footer switches appearance and language",
                "⌘F searches residues or sequence names; residue search accepts IUPAC codes and regular expressions",
                "⇧⌘T translates nucleotide alignments in a new window, leaving the original intact",
                "Primer prefills from the cursor row, or from a selection; Tm uses the nearest-neighbor method",
                "⌘C copies a selection, ⌘A selects all, ⌘Z undoes, ⇧⌘Z redoes",
                "⌘+ and ⌘- change type size; click the sidebar percentage to reset",
                "Arrow keys move the cursor, Option plus arrows box-select, ⇧⌘P opens the command palette",
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Minimal.space4) {
            SheetTitle(text: L.s.guideTitle)

            ScrollView {
                VStack(alignment: .leading, spacing: Minimal.space3) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: Minimal.space2) {
                            Text("\(i + 1)")
                                .font(.system(size: Minimal.fontXXS, design: .monospaced))
                                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                                .frame(width: 16, alignment: .trailing)
                            Text(step)
                                .font(.system(size: Minimal.fontSM))
                                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, Minimal.space1)
            }

            SheetHairline()

            HStack {
                Spacer()
                MinimalSecondaryButton(title: L.s.guideStart) { dismiss() }
                    .keyboardShortcut(.return)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 520, height: 440)
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
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(text: L.s.qualityTitle)
                .padding(.bottom, Minimal.space4)

            if let align = align {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.computing && model.quality == nil {
                            HStack(spacing: Minimal.space2) {
                                ProgressView().controlSize(.small)
                                Text(L.s.statsComputing)
                                    .font(.system(size: Minimal.fontXS))
                                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                            }
                            .padding(.vertical, Minimal.space3)
                        } else if let quality = model.quality {
                            SheetSectionTitle(text: L.s.statsQuality)
                                .padding(.top, Minimal.space1)
                                .padding(.bottom, Minimal.space1)
                            SheetStatRow(label: L.s.statsMeanPairwise,
                                         value: pct(quality.pooledPairwiseIdentity))
                            SheetStatRow(label: L.s.statsMinColIdentity,
                                         value: pct(quality.minColumnIdentity))
                            SheetStatRow(label: L.s.statsMaxColIdentity,
                                         value: pct(quality.maxColumnIdentity))
                            SheetStatRow(label: L.s.statsGapCols,
                                         value: "\(quality.gapColumns)")
                            SheetStatRow(label: L.s.statsTotalCols,
                                         value: "\(quality.totalColumns)")
                        }

                        if let fastq = model.fastq, fastq.hasData {
                            SheetHairline().padding(.vertical, Minimal.space3)
                            SheetSectionTitle(text: L.s.fastqQuality)
                                .padding(.bottom, Minimal.space1)
                            SheetStatRow(label: L.s.fastqMeanPhred,
                                         value: String(format: "%.1f", fastq.meanPhred))
                            SheetStatRow(label: L.s.fastqQ20,
                                         value: pct(fastq.q20Ratio))
                            SheetStatRow(label: L.s.fastqQ30,
                                         value: pct(fastq.q30Ratio))
                        }

                        if !align.charsets.isEmpty {
                            SheetHairline().padding(.vertical, Minimal.space3)
                            SheetSectionTitle(text: L.s.qualityCharset)
                                .padding(.bottom, Minimal.space1)
                            ForEach(align.charsets, id: \.name) { cs in
                                let rangeStrs = cs.ranges.map { r in
                                    r.start == r.end ? "\(r.start)" : "\(r.start)–\(r.end)"
                                }
                                SheetStatRow(label: cs.name,
                                             value: rangeStrs.joined(separator: " "))
                            }
                        }
                    }
                    .padding(.trailing, Minimal.space2)
                }
            } else {
                Text(L.s.qualityNoFile)
                    .font(.system(size: Minimal.fontSM))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                Spacer()
            }

            SheetHairline()
                .padding(.top, Minimal.space3)

            HStack {
                Spacer()
                MinimalSecondaryButton(title: L.s.close) { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding(.top, Minimal.space3)
        }
        .padding(Minimal.space5)
        .frame(width: 460)
        .frame(minHeight: 400)
        .minimalSheetContainer()
        .onAppear { model.compute(alignment: workspace.currentAlignment) }
        .onChange(of: workspace.currentAlignment?.revision) { _, _ in
            model.compute(alignment: workspace.currentAlignment)
        }
    }

    private func pct(_ v: Double) -> String { String(format: "%.2f%%", v * 100) }
}

// MARK: - 配色图例弹窗

struct LegendPopover: View {
    let scheme: ColorScheme
    private var isDark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        VStack(alignment: .leading, spacing: Minimal.space2) {
            Text(L.s.legendTitle)
                .font(.system(size: Minimal.fontSM, weight: .semibold))
                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))

            let entries = ColorSchemeLegend.entries(for: scheme, dark: isDark)
            VStack(alignment: .leading, spacing: Minimal.space1) {
                ForEach(entries.indices, id: \.self) { i in
                    let e = entries[i]
                    HStack(spacing: Minimal.space2) {
                        RoundedRectangle(cornerRadius: Minimal.radiusXS, style: .continuous)
                            .fill(Color(e.color))
                            .frame(width: 14, height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: Minimal.radiusXS, style: .continuous)
                                    .stroke(Color(Minimal.border(dark: isDarkAppearance)),
                                            lineWidth: Minimal.hairline)
                            )
                        Text(e.symbol)
                            .font(.system(size: Minimal.fontXXS, design: .monospaced))
                            .frame(width: 80, alignment: .leading)
                        Text(e.note)
                            .font(.system(size: Minimal.fontXXS))
                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                            .lineLimit(1)
                    }
                    .frame(minHeight: 18)
                }
            }

            Rectangle()
                .fill(Color(Minimal.border(dark: isDarkAppearance)))
                .frame(height: Minimal.hairline)
                .padding(.vertical, Minimal.space2)

            Text(L.s.legendCanvasOps)
                .font(.system(size: Minimal.fontXXS, weight: .semibold))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))

            VStack(alignment: .leading, spacing: Minimal.space1) {
                Text(L.s.legendOp1)
                Text(L.s.legendOp2)
                Text(L.s.legendOp3)
                Text(L.s.legendOp4)
                Text(L.s.legendOp5)
                Text(L.s.legendOp6)
            }
            .font(.system(size: Minimal.fontXXS))
            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Minimal.space4)
        .frame(width: 340)
        .background(Color(Minimal.surface(dark: isDarkAppearance)))
    }
}

// MARK: - 重命名视图

struct RenameView: View {
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var row: Int
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: Minimal.space4) {
            SheetTitle(text: L.s.renameTitle)
            MinimalTextField(placeholder: L.s.renamePlaceholder, text: $name)
            HStack(spacing: Minimal.space2) {
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
        .frame(width: 380, height: 156)
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
        VStack(alignment: .leading, spacing: Minimal.space4) {
            VStack(alignment: .leading, spacing: Minimal.space1) {
                SheetTitle(text: L.s.moveTitle)
                if let align = workspace.currentAlignment {
                    Text("\(L.s.moveCount) \(align.seqCount)")
                        .font(.system(size: Minimal.fontXXS))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                }
            }

            if let align = workspace.currentAlignment {
                VStack(spacing: Minimal.space2) {
                    moveRow(L.s.moveFrom, value: $from, upper: align.seqCount - 1)
                    moveRow(L.s.moveTo, value: $to, upper: align.seqCount - 1)
                }
            }

            HStack(spacing: Minimal.space2) {
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
        .frame(width: 380, height: 196)
        .minimalSheetContainer()
    }

    private func moveRow(_ label: String, value: Binding<Int>, upper: Int) -> some View {
        HStack(spacing: Minimal.space2) {
            Text(label)
                .font(.system(size: Minimal.fontXXS))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .frame(width: 28, alignment: .leading)
            Stepper("\(value.wrappedValue + 1)",
                    value: value,
                    in: 0...max(0, upper))
                .font(.system(size: Minimal.fontSM, design: .monospaced))
        }
    }
}

// MARK: - 关闭守卫确认

struct UnsavedChangesView: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: Minimal.space4) {
            SheetTitle(text: L.s.unsavedTitle)
            Text("\"\(workspace.currentFileName.isEmpty ? L.s.unnamed : workspace.currentFileName)\" \(L.s.unsavedDesc)")
                .font(.system(size: Minimal.fontSM))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Minimal.space2) {
                Spacer()
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
        .frame(width: 420, height: 172)
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
