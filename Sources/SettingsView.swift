//  SettingsView.swift
//  SeqAlignMac — 设置弹窗（从 ToolSheetViews.swift 拆分）
//
//  外观模式、配色方案、字号、共识显示、ClustalX 阈值等全局设置。
//  共识模式改 .menu。
//  固定 480×480 改为 minHeight + ScrollView（英文长 Toggle 标题折行后底部被裁剪）；
//      标签列宽度与选择器宽度消费 Minimal 令牌。

import AppKit
import SwiftUI

/// 全局设置读取入口。共识模式如果只有写入点（设置面板）而全工程无读取点，
/// 导致三选一恒走多数规则。集中从此处读取，画布 / 导出 / 统计面板共用同一真相源。
enum AppSettings {
    /// 外部比对器超时可配置。
    static var externalAlignerTimeoutSeconds: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "SeqAlignMac.externalAlignerTimeout")
            return v > 0 ? v : 300
        }
        set { UserDefaults.standard.set(newValue, forKey: "SeqAlignMac.externalAlignerTimeout") }
    }

    static var consensusMode: ConsensusMode {
        ConsensusMode(rawValue: UserDefaults.standard.integer(forKey: "SeqAlignMac.consensusMode")) ?? .majority
    }
}

struct SettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject var workspace: Workspace
    @ObservedObject private var appearanceStore = AppearanceStore.shared
    @State private var clustalXThreshold: Double = ColorComputer.clustalXThreshold
    @State private var consensusMode: Int = UserDefaults.standard.integer(forKey: "SeqAlignMac.consensusMode")
    @State private var alignerTimeout: Int = UserDefaults.standard.integer(forKey: "SeqAlignMac.externalAlignerTimeout") == 0
        ? 300 : UserDefaults.standard.integer(forKey: "SeqAlignMac.externalAlignerTimeout")

    /// 标签列宽 / 选择器宽度统一走令牌
    private let labelWidth: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.s.settingsTitle).font(.system(size: Minimal.fontXL, weight: .semibold))

            // 内容可滚动，高度改 minHeight（长文案不再被裁剪）
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        settingLabel(L.s.settingsAppearance)
                        Picker("", selection: Binding(
                            get: { appearanceStore.mode },
                            set: { appearanceStore.apply($0) }
                        )) {
                            Text(L.s.settingsLight).tag(AppearanceMode.light)
                            Text(L.s.settingsDark).tag(AppearanceMode.dark)
                            Text(L.s.settingsSystem).tag(AppearanceMode.system)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: Minimal.schemePickerW)
                        .tint(Color(Minimal.primary(dark: isDarkAppearance)))
                        .accessibilityLabel(L.s.settingsAppearance)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        settingLabel(L.s.settingsColorScheme)
                        // 下拉菜单替代 6 段 segmented：段宽不足会遮挡「默认」等选项文字
                        Picker("", selection: $workspace.currentScheme) {
                            Text(L.s.schemeMinimal).tag(ColorScheme.minimal)
                            Text(L.s.schemeClustalX).tag(ColorScheme.clustalX)
                            Text(L.s.schemeZappo).tag(ColorScheme.zappo)
                            Text(L.s.schemeSeaView).tag(ColorScheme.seaView)
                            Text(L.s.schemeDefault).tag(ColorScheme.defaultNucleotide)
                            Text(L.s.schemeTransitionTransversion).tag(ColorScheme.transitionTransversion)
                            Text(L.s.schemeOkabeIto).tag(ColorScheme.okabeIto)
                        }
                        .pickerStyle(.menu)
                        .frame(width: Minimal.schemePickerW, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(L.s.settingsColorScheme)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        settingLabel(L.s.settingsFontSize)
                        Stepper(value: $workspace.fontSize, in: 8...28) {
                            // 步进器补单位
                            Text("\(Int(workspace.fontSize)) pt")
                                .monospacedDigit()
                                .font(.system(size: Minimal.fontSM))
                                .frame(width: 44, alignment: .leading)
                        }
                        .accessibilityLabel(L.s.settingsFontSize)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Toggle 走主题字号
                        Toggle(L.s.settingsShowConsensus, isOn: $workspace.showConsensus)
                            .font(.system(size: Minimal.fontSM))
                        Toggle(L.s.settingsHighContrast, isOn: $workspace.highContrast)
                            .font(.system(size: Minimal.fontSM))
                        Toggle(L.s.settingsFocusDim, isOn: $workspace.focusDimMode)
                            .font(.system(size: Minimal.fontSM))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L.s.clustalXThreshold)
                                .font(.system(size: Minimal.fontSM))
                            Spacer()
                            Text("\(Int(clustalXThreshold * 100))%")
                                .font(.system(size: Minimal.fontSM, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                        }
                        Slider(value: $clustalXThreshold, in: 0.1...0.9, step: 0.05) {
                            EmptyView()
                        } onEditingChanged: { editing in
                            if !editing {
                                ColorComputer.clustalXThreshold = clustalXThreshold
                                workspace.objectWillChange.send()
                            }
                        }
                        .tint(Color(Minimal.primary(dark: isDarkAppearance)))
                        // 无障碍标签
                        .accessibilityLabel(L.s.clustalXThreshold)
                        .accessibilityValue("\(Int(clustalXThreshold * 100))%")
                        Text(L.s.clustalXThresholdHint)
                            .font(.system(size: Minimal.fontXXS))
                            .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                    }

                    HStack(alignment: .center, spacing: 12) {
                        settingLabel(L.s.consensusMode)
                        // 与配色方案一致改 .menu（"IUPAC Degenerate" 在 segmented 中被截断）
                        Picker("", selection: $consensusMode) {
                            Text(L.s.consensusMajority).tag(0)
                            Text(L.s.consensusIUPAC).tag(1)
                            Text(L.s.consensusStrict).tag(2)
                        }
                        .pickerStyle(.menu)
                        .frame(width: Minimal.schemePickerW, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(L.s.consensusMode)
                        .onChange(of: consensusMode) { _, newVal in
                            UserDefaults.standard.set(newVal, forKey: "SeqAlignMac.consensusMode")
                            workspace.objectWillChange.send()
                        }
                    }

                    // 外部比对器超时可配置
                    HStack(alignment: .center, spacing: 12) {
                        settingLabel(L.s.settingsAlignerTimeout)
                        Stepper(value: $alignerTimeout, in: 30...3600, step: 30) {
                            Text("\(alignerTimeout) s")
                                .font(.system(size: Minimal.fontSM))
                                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                                .frame(width: 72, alignment: .leading)
                        }
                        .accessibilityLabel(L.s.settingsAlignerTimeout)
                        .onChange(of: alignerTimeout) { _, newVal in
                            AppSettings.externalAlignerTimeoutSeconds = newVal
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer()
            HStack {
                Spacer()
                MinimalPrimaryButton(title: L.s.settingsDone) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 480)
        .frame(minHeight: 440, maxHeight: 560)
        .minimalSheetContainer()
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Minimal.fontSM))
            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            .frame(width: labelWidth, alignment: .leading)
    }
}
