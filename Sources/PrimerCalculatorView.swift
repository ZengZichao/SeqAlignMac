//  PrimerCalculatorView.swift
//  SeqAlignMac — 引物计算器弹窗（从 ToolSheetViews.swift 拆分）
//
//  提供 Tm、GC%、自二聚体、异源二聚体计算。

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
        VStack(alignment: .leading, spacing: 16) {
            Text(L.s.primerTitle).font(.system(size: Minimal.fontXL, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(L.s.primerSeqA)
                HStack(spacing: 8) {
                    MinimalTextField(placeholder: L.s.primerPlaceholderA, text: $seqA)
                    MinimalBarButton(title: L.s.primerFromSel) { fillFromSelection() }
                        .disabled(WindowRegistry.shared.activeForAction?.currentSelection == nil)
                }

                Text(L.s.primerSeqB)
                MinimalTextField(placeholder: L.s.primerPlaceholderB, text: $seqB)

                // 盐浓度 / 寡链浓度（参与 Tm 与盐校正，持久化）
                HStack(spacing: 8) {
                    parameterField(label: L.s.primerNa, value: $na_mM, suffix: "mM")
                    parameterField(label: L.s.primerMg, value: $mg_mM, suffix: "mM")
                    parameterField(label: L.s.primerOligo, value: $oligo_uM, suffix: "µM")
                }
            }

            HStack(spacing: Minimal.space2) {
                MinimalPrimaryButton(title: L.s.primerCalcTm) { result = computeTm() }
                MinimalSecondaryButton(title: L.s.primerCalcGC) { result = computeGC() }
                MinimalSecondaryButton(title: L.s.primerSelfDimer) { result = computeSelfDimer() }
                MinimalSecondaryButton(title: L.s.primerHeteroDimer) { result = computeHeteroDimer() }
            }

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    if let result = result {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(result.sections) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.title)
                                        .font(.system(size: Minimal.fontSM, weight: .semibold))
                                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                                    ForEach(section.rows) { row in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(row.label)
                                                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                                                .frame(width: 68, alignment: .leading)
                                            Text(row.value)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .font(.system(.body, design: .monospaced))
                                    }
                                }
                            }
                            if let status = result.status {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(statusColor(status))
                                        .frame(width: 10, height: 10)
                                    Text(status.text)
                                        .font(.system(size: Minimal.fontSM, weight: .medium))
                                        .foregroundColor(statusColor(status))
                                }
                                .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    } else {
                        Text(L.s.primerResultPlaceholder)
                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
                .frame(minHeight: 150)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Minimal.radiusMD)
                .fill(Color(Minimal.card(dark: isDarkAppearance))))
            .overlay(RoundedRectangle(cornerRadius: Minimal.radiusMD)
                .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))

            HStack {
                Spacer()
                MinimalSecondaryButton(title: L.s.close) { isPresented = false }
                    .keyboardShortcut(.escape)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 500, height: 460)
        .minimalSheetContainer()
        .onAppear {
            if seqA.isEmpty && !prefill.isEmpty {
                seqA = prefill
            }
        }
    }

    private func parameterField(label: String, value: Binding<Double>, suffix: String, lowerBound: Double = 0) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: Minimal.fontXS))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            HStack(spacing: 2) {
                MinimalTextField(placeholder: "", text: Binding(
                    get: { value.wrappedValue == 0 ? "" : String(format: "%g", value.wrappedValue) },
                    set: { raw in
                        // 输入校验：负值会让 sqrt/log 产出 NaN 的「伪科学结果」；
                        // 解析失败（过渡态如 "-"、"1e"）保持原值不闪跳
                        guard let v = Double(raw) else { return }
                        value.wrappedValue = max(lowerBound, v.isFinite ? v : lowerBound)
                    }
                ))
                Text(suffix)
                    .font(.system(size: Minimal.fontXS))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            }
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
        case .warning: return Color(Minimal.destructive(dark: isDarkAppearance))
        }
    }

    private func emptyInputResult(_ message: String) -> PrimerResult {
        PrimerResult(sections: [
            PrimerResultSection(title: L.s.primerCalcFail, rows: [
                PrimerResultRow(label: L.s.primerError, value: message)
            ])
        ])
    }

    private func computeTm() -> PrimerResult? {
        guard !seqA.isEmpty else { return emptyInputResult(L.s.primerNeedSeqA) }
        do {
            let (tmMin, tmMax) = try PrimerCalculator.tm(seqA, options: tmOptions)
            return PrimerResult(sections: [
                PrimerResultSection(title: L.s.primerTmLabel, rows: [
                    PrimerResultRow(label: L.s.primerSeq, value: seqA.uppercased()),
                    PrimerResultRow(label: L.s.primerTmRange, value: "\(String(format: "%.1f", tmMin))°C ~ \(String(format: "%.1f", tmMax))°C"),
                ]),
                PrimerResultSection(title: L.s.primerParams, rows: [
                    PrimerResultRow(label: L.s.primerNa, value: String(format: "%.1f mM", na_mM)),
                    PrimerResultRow(label: L.s.primerMg, value: String(format: "%.1f mM", mg_mM)),
                    PrimerResultRow(label: L.s.primerOligo, value: String(format: "%.2f µM", oligo_uM)),
                ]),
            ])
        } catch {
            return PrimerResult(sections: [
                PrimerResultSection(title: L.s.primerCalcFail, rows: [
                    PrimerResultRow(label: L.s.primerError, value: error.localizedDescription)
                ])
            ])
        }
    }

    private func computeGC() -> PrimerResult? {
        guard !seqA.isEmpty else { return emptyInputResult(L.s.primerNeedSeqA) }
        let gc = PrimerCalculator.gcContent(seqA)
        return PrimerResult(sections: [
            PrimerResultSection(title: L.s.primerGC, rows: [
                PrimerResultRow(label: L.s.primerSeq, value: seqA.uppercased()),
                PrimerResultRow(label: "GC%", value: String(format: "%.2f%%", gc * 100)),
            ])
        ])
    }

    private func computeSelfDimer() -> PrimerResult? {
        guard !seqA.isEmpty else { return emptyInputResult(L.s.primerNeedSeqA) }
        let dg = PrimerCalculator.dimer(seqA, mode: .selfDimer)
        return PrimerResult(sections: [
            PrimerResultSection(title: L.s.primerSelfDimerTitle, rows: [
                PrimerResultRow(label: L.s.primerSeq, value: seqA.uppercased()),
                PrimerResultRow(label: L.s.primerDG, value: "\(String(format: "%.2f", dg)) kcal/mol"),
            ])
        ], status: dg < -5 ? .warning(L.s.primerWarnDimer) : .safe(L.s.primerSafeDimer))
    }

    private func computeHeteroDimer() -> PrimerResult? {
        if seqA.isEmpty { return emptyInputResult(L.s.primerNeedSeqA) }
        guard !seqB.isEmpty else { return emptyInputResult(L.s.primerNeedSeqB) }
        let dg = PrimerCalculator.dimer(seqA, b: seqB, mode: .hetero)
        return PrimerResult(sections: [
            PrimerResultSection(title: L.s.primerHeteroTitle, rows: [
                PrimerResultRow(label: L.s.primerSeqALbl, value: seqA.uppercased()),
                PrimerResultRow(label: L.s.primerSeqBLbl, value: seqB.uppercased()),
                PrimerResultRow(label: L.s.primerDG, value: "\(String(format: "%.2f", dg)) kcal/mol"),
            ])
        ], status: dg < -5 ? .warning(L.s.primerWarnDimer) : .safe(L.s.primerSafeDimer))
    }
}
