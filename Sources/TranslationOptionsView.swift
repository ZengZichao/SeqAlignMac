//  TranslationOptionsView.swift
//  SeqAlignMac — 翻译选项弹窗（从 ToolSheetViews.swift 拆分）
//
//  选择遗传密码表、阅读框、显示模式等，将核苷酸序列翻译为氨基酸序列。

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
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.s.translateTitle).font(.system(size: Minimal.fontXL, weight: .semibold))

            VStack(alignment: .leading, spacing: 14) {
                // 标签列固定宽度，控件列统一左对齐
                HStack(alignment: .center, spacing: 12) {
                    Text(L.s.translateCodeTable)
                        .font(.system(size: Minimal.fontSM))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                        .frame(width: 92, alignment: .leading)
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
                    .frame(width: 260, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .center, spacing: 12) {
                    Text(L.s.translateFrame)
                        .font(.system(size: Minimal.fontSM))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                        .frame(width: 92, alignment: .leading)
                    Picker("", selection: $selectedFrame) {
                        Text("-3").tag(-3)
                        Text("-2").tag(-2)
                        Text("-1").tag(-1)
                        Text("+1").tag(0)
                        Text("+2").tag(1)
                        Text("+3").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .tint(Color(Minimal.primary(dark: isDarkAppearance)))
                }

                HStack(alignment: .center, spacing: 12) {
                    Text(L.s.translateMode)
                        .font(.system(size: Minimal.fontSM))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                        .frame(width: 92, alignment: .leading)
                    Picker("", selection: $selectedMode) {
                        Text(L.s.translateModeCodon).tag(TranslationDisplayMode.codonOnly)
                        Text(L.s.translateModeAA).tag(TranslationDisplayMode.aminoAcidOnly)
                        Text(L.s.translateModeBoth).tag(TranslationDisplayMode.both)
                        Text(L.s.translateModeIgnoreGaps).tag(TranslationDisplayMode.ignoreGaps)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 350)
                    .tint(Color(Minimal.primary(dark: isDarkAppearance)))
                }

                HStack(alignment: .center, spacing: 12) {
                    Text(L.s.translateNameOption)
                        .font(.system(size: Minimal.fontSM))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                        .frame(width: 92, alignment: .leading)
                    Picker("", selection: $nameAddSuffix) {
                        Text(L.s.translateKeepOriginal).tag(false)
                        Text(L.s.translateAddSuffix).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .tint(Color(Minimal.primary(dark: isDarkAppearance)))
                }

                // 选项开关归入同一卡片，纵向排列对齐
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(L.s.translateNewWindow, isOn: $openInNewWindow)
                        .font(.system(size: Minimal.fontSM))
                }
                .padding(Minimal.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .fill(Color(Minimal.card(dark: isDarkAppearance))))
                .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
            }

            HStack {
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
        }
        .padding(Minimal.space5)
        .frame(width: 560, height: 400)
        .minimalSheetContainer()
    }
}
