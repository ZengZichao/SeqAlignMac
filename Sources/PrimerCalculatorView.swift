//  PrimerCalculatorView.swift
//  SeqAlignMac — 引物计算
//
//  一次「计算」给出 Tm、GC 含量与二聚体检查：这四类结果由同一组输入决定，
//  拆成四个按钮只会让用户逐个判断该按哪个。参数与结果左右分栏，
//  输入区固定宽度、结果区占满剩余空间，扫读时不需要在纵向堆叠里找。

import AppKit
import SwiftUI

// MARK: - 引物计算结果模型

private struct PrimerResultRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct PrimerResultSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [PrimerResultRow]
}

private enum PrimerResultStatus {
    case safe(String)
    case warning(String)
    var text: String {
        switch self {
        case .safe(let t): return t
        case .warning(let t): return t
        }
    }
}

private struct PrimerResult {
    var sections: [PrimerResultSection]
    var status: PrimerResultStatus?
}

// MARK: - 引物计算视图

struct PrimerCalculatorView: View {
    @Binding var isPresented: Bool
    var prefill: String = ""
    @State private var seqA = ""
    @State private var seqB = ""
    @State private var result: PrimerResult? = nil
    // 盐/寡链浓度可配置（单位 mM / µM），持久化；传入 TmOptions 参与计算
    @AppStorage("SeqAlignMac.primerNa_mM") private var na_mM: Double = 50
    @AppStorage("SeqAlignMac.primerMg_mM") private var mg_mM: Double = 0
    @AppStorage("SeqAlignMac.primerOligo_uM") private var oligo_uM: Double = 0.25

    private var tmOptions: TmOptions {
        TmOptions(naMolar: na_mM / 1000.0,
                  mgMolar: mg_mM / 1000.0,
                  oligoMolar: oligo_uM / 1_000_000.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(text: L.s.primerTitle)
                .padding(.bottom, Minimal.space4)

            HStack(alignment: .top, spacing: Minimal.space5) {
                inputColumn
                    .frame(width: 280)

                Rectangle()
                    .fill(Color(Minimal.border(dark: isDarkAppearance)))
                    .frame(width: Minimal.hairline)

                resultColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            SheetHairline()
                .padding(.top, Minimal.space3)

            HStack {
                Spacer()
                MinimalSecondaryButton(title: L.s.close) { isPresented = false }
                    .keyboardShortcut(.escape)
            }
            .padding(.top, Minimal.space3)
        }
        .padding(Minimal.space5)
        .frame(width: 720, height: 460)
        .minimalSheetContainer()
        .onAppear {
            if seqA.isEmpty && !prefill.isEmpty {
                seqA = prefill
            }
        }
    }

    // MARK: 输入

    private var inputColumn: some View {
        VStack(alignment: .leading, spacing: Minimal.space3) {
            labeledField(L.s.primerSeqA) {
                HStack(spacing: Minimal.space1) {
                    MinimalTextField(placeholder: L.s.primerPlaceholderA, text: $seqA)
                    // 从当前选区取序列，避免手工转录
                    MinimalIconButton(systemImage: "textcursor", help: L.s.primerFromSel, size: 26) {
                        fillFromSelection()
                    }
                    .disabled(WindowRegistry.shared.activeForAction?.currentSelection == nil)
                }
            }

            labeledField(L.s.primerSeqB) {
                MinimalTextField(placeholder: L.s.primerPlaceholderB, text: $seqB)
            }

            SheetHairline()
                .padding(.vertical, Minimal.space1)

            SheetSectionTitle(text: L.s.primerParams)

            HStack(alignment: .bottom, spacing: Minimal.space2) {
                parameterField(label: L.s.primerNa, suffix: "mM", value: $na_mM)
                parameterField(label: L.s.primerMg, suffix: "mM", value: $mg_mM)
                parameterField(label: L.s.primerOligo, suffix: "µM", value: $oligo_uM)
            }

            MinimalPrimaryButton(title: L.s.primerCalcTm, height: Minimal.controlLG) {
                result = computeAll()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, Minimal.space1)

            Text(L.s.primerTmLabel)
                .font(.system(size: Minimal.fontXXS))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Minimal.space1) {
            Text(label)
                .font(.system(size: Minimal.fontXXS))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            content()
        }
    }

    // MARK: 结果

    private var resultColumn: some View {
        ZStack(alignment: .topLeading) {
            Color(Minimal.card(dark: isDarkAppearance))
            if let result = result {
                ScrollView {
                    VStack(alignment: .leading, spacing: Minimal.space4) {
                        ForEach(result.sections) { section in
                            VStack(alignment: .leading, spacing: Minimal.space1) {
                                Text(section.title)
                                    .font(.system(size: Minimal.fontXXS, weight: .semibold))
                                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                                ForEach(section.rows) { row in
                                    HStack(alignment: .firstTextBaseline, spacing: Minimal.space2) {
                                        Text(row.label)
                                            .font(.system(size: Minimal.fontXXS))
                                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                                            .frame(width: 72, alignment: .leading)
                                        Text(row.value)
                                            .font(.system(size: Minimal.fontXS, design: .monospaced))
                                            .textSelection(.enabled)
                                            .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        if let status = result.status {
                            HStack(spacing: Minimal.space1 + 2) {
                                Image(systemName: isWarning(status)
                                      ? "exclamationmark.triangle.fill"
                                      : "checkmark.circle.fill")
                                    .font(.system(size: Minimal.fontXXS))
                                    .foregroundColor(statusColor(status))
                                Text(status.text)
                                    .font(.system(size: Minimal.fontSM, weight: .medium))
                                    .foregroundColor(statusColor(status))
                            }
                        }
                    }
                    .padding(Minimal.space3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(L.s.primerResultPlaceholder)
                    .font(.system(size: Minimal.fontXS))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    .padding(Minimal.space3)
            }
        }
        .overlay(
            Rectangle()
                .stroke(Color(Minimal.border(dark: isDarkAppearance)),
                        lineWidth: Minimal.hairline)
        )
    }

    /// 参数输入：数值框 + 单位标签。单位不进输入框，避免用户把 mM 一起删掉
    private func parameterField(label: String, suffix: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: Minimal.space1) {
            Text("\(label) \(suffix)")
                .font(.system(size: Minimal.fontXXS))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .lineLimit(1)
            MinimalTextField(placeholder: "0", text: Binding(
                get: { value.wrappedValue == 0 ? "" : String(format: "%g", value.wrappedValue) },
                set: { raw in
                    // 输入校验：负值会让 sqrt/log 产出 NaN 的「伪科学结果」；
                    // 解析失败（过渡态如 "-"、"1e"）保持原值不闪跳
                    guard let v = Double(raw) else { return }
                    value.wrappedValue = max(0, v.isFinite ? v : 0)
                }
            ))
        }
    }

    private func fillFromSelection() {
        guard let ws = WindowRegistry.shared.activeForAction,
              let sel = ws.currentSelection,
              let align = ws.currentAlignment,
              sel.rowStart < align.seqCount else { return }
        let row = min(sel.rowStart, align.seqCount - 1)
        let seq = align.sequences[row]
        var letters = ""
        let colEnd = min(sel.colEnd, seq.residues.count - 1)
        guard colEnd >= sel.colStart else { return }
        for col in sel.colStart...colEnd {
            let b = seq.residues[col]
            if b != 0x2D { letters.append(Character(UnicodeScalar(b))) }
        }
        seqA = letters
    }

    private func statusColor(_ status: PrimerResultStatus) -> Color {
        switch status {
        case .safe:    return Color(Minimal.success(dark: isDarkAppearance))
        // 二聚体倾向是可继续使用的警示，不是错误：用 amber 而非 red
        case .warning: return Color(Minimal.warning(dark: isDarkAppearance))
        }
    }

    private func isWarning(_ status: PrimerResultStatus) -> Bool {
        if case .warning = status { return true }
        return false
    }

    private func errorResult(_ message: String) -> PrimerResult {
        PrimerResult(sections: [
            PrimerResultSection(title: L.s.primerCalcFail, rows: [
                PrimerResultRow(label: L.s.primerError, value: message)
            ])
        ])
    }

    /// 一次计算全部指标：Tm、GC、自身二聚体、异源二聚体（B 非空时）
    private func computeAll() -> PrimerResult {
        guard !seqA.isEmpty else { return errorResult(L.s.primerNeedSeqA) }

        var sections: [PrimerResultSection] = []
        var warnings = false

        do {
            let (tmMin, tmMax) = try PrimerCalculator.tm(seqA, options: tmOptions)
            sections.append(PrimerResultSection(title: "Tm", rows: [
                PrimerResultRow(label: L.s.primerSeq, value: seqA.uppercased()),
                PrimerResultRow(label: L.s.primerTmRange,
                                value: "\(String(format: "%.1f", tmMin))–\(String(format: "%.1f", tmMax)) °C"),
            ]))
        } catch {
            sections.append(PrimerResultSection(title: "Tm", rows: [
                PrimerResultRow(label: L.s.primerError, value: error.localizedDescription)
            ]))
        }

        let gc = PrimerCalculator.gcContent(seqA)
        sections.append(PrimerResultSection(title: L.s.primerGC, rows: [
            PrimerResultRow(label: "GC", value: String(format: "%.2f%%", gc * 100))
        ]))

        let selfDg = PrimerCalculator.dimer(seqA, mode: .selfDimer)
        if selfDg < -5 { warnings = true }
        sections.append(PrimerResultSection(title: L.s.primerSelfDimerTitle, rows: [
            PrimerResultRow(label: L.s.primerDG, value: "\(String(format: "%.2f", selfDg)) kcal/mol")
        ]))

        if !seqB.isEmpty {
            let heteroDg = PrimerCalculator.dimer(seqA, b: seqB, mode: .hetero)
            if heteroDg < -5 { warnings = true }
            sections.append(PrimerResultSection(title: L.s.primerHeteroTitle, rows: [
                PrimerResultRow(label: L.s.primerSeqBLbl, value: seqB.uppercased()),
                PrimerResultRow(label: L.s.primerDG, value: "\(String(format: "%.2f", heteroDg)) kcal/mol")
            ]))
        }

        let status: PrimerResultStatus = warnings
            ? .warning(L.s.primerWarnDimer)
            : .safe(L.s.primerSafeDimer)
        return PrimerResult(sections: sections, status: status)
    }
}
