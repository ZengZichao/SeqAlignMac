//  TranslationOptionsView.swift
//  SeqAlignMac — 翻译选项弹窗
//
//  四个选项都有实际后果（读框、显示方式、命名、是否保留原比对），因此按
//  「一次决定一组」的纵向表单排列：标签列定宽、控件左缘对齐、组间留白由
//  统一的 4pt 栅格决定。选项本身不附解释文本——名称已说明结果。

import AppKit
import SwiftUI

struct TranslationOptionsView: View {
    @Binding var isPresented: Bool
    let workspace: Workspace
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTable: GeneticCodeTable = .standard
    @State private var selectedFrame: Int = 0
    @State private var selectedMode: TranslationDisplayMode = .aminoAcidOnly
    @State private var openInNewWindow = true
    @State private var nameAddSuffix = false

    /// 把翻译过程的检出结果讲给用户，而不是静默产出可用性问题
    static func warningText(_ issues: [TranslationWarning]) -> String {
        var parts: [String] = []
        for issue in issues {
            switch issue {
            case .frameshift(let name, let column):
                parts.append("\(L.s.translationFrameshift): \(name) #\(column + 1)")
            case .lengthNotMultipleOfThree(let n):
                parts.append("\(L.s.translationLengthNotMultipleOfThree) (\(n))")
            case .mixedCodonTrack:
                parts.append(L.s.translationMixedTrack)
            case .raggedOutput:
                parts.append(L.s.translationRagged)
            case .notNucleotideInput:
                parts.append(L.s.translationNeedsNucleotide)
            }
        }
        let separator = LanguageManager.shared.language == .zh ? "、" : ", "
        return parts.joined(separator: separator)
    }

    private let labelWidth: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(text: L.s.translateTitle)
                .padding(.bottom, Minimal.space4)

            VStack(alignment: .leading, spacing: Minimal.space3) {
                settingRow(L.s.translateCodeTable) {
                    Picker("", selection: $selectedTable) {
                        Text("Standard (1)").tag(GeneticCodeTable.standard)
                        Text("Vertebrate Mito (2)").tag(GeneticCodeTable.vertebrateMito)
                        Text("Yeast (3)").tag(GeneticCodeTable.yeast)
                        Text("Mold/Protozoan Mito (4)").tag(GeneticCodeTable.moldProtozoanMito)
                        Text("Invertebrate Mito (5)").tag(GeneticCodeTable.invertebrateMito)
                        Text("Ciliate (6)").tag(GeneticCodeTable.ciliate)
                        Text("Echinoderm Mito (9)").tag(GeneticCodeTable.echinodermMito)
                        Text("Bacterial (11)").tag(GeneticCodeTable.bacterial)
                        Text("Alt Yeast (12)").tag(GeneticCodeTable.altYeast)
                        Text("Ascidian Mito (13)").tag(GeneticCodeTable.ascidianMito)
                        Text("Flatworm Mito (14)").tag(GeneticCodeTable.flatwormMito)
                        Text("Blepharisma (15)").tag(GeneticCodeTable.blepharismaMito)
                        Text("Euplotid Nuclear (10)").tag(GeneticCodeTable.euplotid)
                        Text("Chlorophycean (16)").tag(GeneticCodeTable.chlorophycean)
                        Text("Pterobranch Mito (24)").tag(GeneticCodeTable.pterobranchMito)
                        Text("SR1 (25)").tag(GeneticCodeTable.sr1)
                        Text("Peritrich Nuclear (30)").tag(GeneticCodeTable.peritrichNuclear)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 280, alignment: .leading)
                    .accessibilityLabel(L.s.translateCodeTable)
                }

                settingRow(L.s.translateFrame) {
                    MinimalSegmentedControl(
                        options: [
                            .init(title: "-3", value: -3),
                            .init(title: "-2", value: -2),
                            .init(title: "-1", value: -1),
                            .init(title: "+1", value: 0),
                            .init(title: "+2", value: 1),
                            .init(title: "+3", value: 2),
                        ],
                        selection: $selectedFrame,
                        width: 280
                    )
                }

                settingRow(L.s.translateMode) {
                    MinimalSegmentedControl(
                        options: [
                            .init(title: L.s.translateModeCodon, value: TranslationDisplayMode.codonOnly),
                            .init(title: L.s.translateModeAA, value: TranslationDisplayMode.aminoAcidOnly),
                            .init(title: L.s.translateModeBoth, value: TranslationDisplayMode.both),
                            .init(title: L.s.translateModeIgnoreGaps, value: TranslationDisplayMode.ignoreGaps),
                        ],
                        selection: $selectedMode,
                        width: 340
                    )
                }

                settingRow(L.s.translateNameOption) {
                    MinimalSegmentedControl(
                        options: [
                            .init(title: L.s.translateKeepOriginal, value: false),
                            .init(title: L.s.translateAddSuffix, value: true),
                        ],
                        selection: $nameAddSuffix,
                        width: 280
                    )
                }

                SheetHairline()
                    .padding(.vertical, Minimal.space1)

                Toggle(isOn: $openInNewWindow) {
                    Text(L.s.translateNewWindow)
                        .font(.system(size: Minimal.fontSM))
                }
                .toggleStyle(.checkbox)
            }

            Spacer(minLength: Minimal.space4)

            SheetHairline()

            HStack(spacing: Minimal.space2) {
                Spacer()
                MinimalSecondaryButton(title: L.s.cancel) { isPresented = false }
                MinimalPrimaryButton(title: L.s.translateBtn) {
                    guard let align = workspace.currentAlignment else { isPresented = false; return }
                    // 全表查表翻译移入后台（亿级 cell 在主线程同步执行会冻结数秒），
                    // 主线程只做窗口打开 / 替换命令入栈
                    let table = selectedTable
                    let frame = selectedFrame
                    let mode = selectedMode
                    let addSuffix = nameAddSuffix
                    let openNew = openInNewWindow
                    let ws = workspace
                    isPresented = false
                    // 数据类型闸门：蛋白比对点"翻译"会产出一条全 X、
                    // 宽度为原长 1/3 的"蛋白比对"，还被赋 datatype = .aminoAcid，
                    // 可正常保存/导出/NJ 建树；而含 '.'/'*' 的核酸比对
                    // 会被判型器误判为蛋白，用户可能在没点任何设置的情况下走进这条路径。
                    guard align.datatype == .nucleicAcid else {
                        DispatchQueue.main.async {
                            ws.showToast(L.s.translationNeedsNucleotide)
                        }
                        return
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        let snapshot = align.snapshot()
                        let translation = AlignmentTranslator.translateChecked(
                            snapshot, table: table,
                            frame: frame, displayMode: mode
                        )
                        let aaAlignment = translation.alignment
                        let issues = translation.warnings
                        if !issues.isEmpty {
                            let text = Self.warningText(issues)
                            DispatchQueue.main.async { ws.showToast(text) }
                        }
                        if addSuffix {
                            for i in aaAlignment.sequences.indices {
                                aaAlignment.sequences[i].name += "_AA"
                            }
                        }
                        DispatchQueue.main.async {
                            if openNew {
                                PendingWindowData.prepare(
                                    alignment: aaAlignment,
                                    fileName: ws.currentFileName.isEmpty ? "translation.fasta" : "\(ws.currentFileName) (translation)",
                                    format: .fasta
                                )
                                openWindow(id: "seqalign-main")
                            } else {
                                let cmd = ReplaceAlignmentCommand(old: align, new: aaAlignment)
                                UndoRedoCoordinator.shared.execute(cmd)
                                ws.showToast(L.s.toastReplaceTranslated)
                            }
                        }
                    }
                }
                .keyboardShortcut(.return)
            }
            .padding(.top, Minimal.space3)
        }
        .padding(Minimal.space5)
        .frame(width: 560, height: 400)
        .minimalSheetContainer()
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder _ control: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Minimal.space2) {
            Text(label)
                .font(.system(size: Minimal.fontXXS))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28)
    }
}
