//  SettingsView.swift
//  SeqAlignMac — 偏好设置
//
//  只放全局、低频、需要一次决定的事项：外观、画布默认、分析口径。
//  与某次操作绑定的参数（比对器超时）属于对应操作面板，不在这里出现。

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

    /// 标签列宽 / 选择器宽度统一走令牌；两列同宽才能让控件左缘落在同一条竖线上
    private let labelWidth: CGFloat = 92
    private let controlWidth: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(text: L.s.settingsTitle)
                .padding(.bottom, Minimal.space4)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 外观
                    SheetSectionTitle(text: L.s.settingsAppearance)
                        .padding(.bottom, Minimal.space2)

                    rows {
                        settingRow(L.s.settingsTheme) {
                            MinimalSegmentedControl(
                                options: [
                                    .init(title: L.s.settingsLight, value: AppearanceMode.light),
                                    .init(title: L.s.settingsDark, value: AppearanceMode.dark),
                                    .init(title: L.s.settingsSystem, value: AppearanceMode.system),
                                ],
                                selection: Binding(
                                    get: { appearanceStore.mode },
                                    set: { appearanceStore.apply($0) }
                                ),
                                width: controlWidth
                            )
                        }

                        settingRow(L.s.settingsColorScheme) {
                            // 下拉菜单而非分段：七个选项在分段控件里会被截断
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
                            .labelsHidden()
                            .frame(width: controlWidth, alignment: .leading)
                            .accessibilityLabel(L.s.settingsColorScheme)
                        }

                        settingRow(L.s.settingsFontSize) {
                            // 数值与加减器分开摆：Stepper 自带 label 内边距，
                            // 会把数值推到控件列右侧，与其他行错开一格
                            HStack(spacing: Minimal.space2) {
                                Text("\(Int(workspace.fontSize)) pt")
                                    .monospacedDigit()
                                    .font(.system(size: Minimal.fontSM, design: .monospaced))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                Stepper("", value: $workspace.fontSize, in: 8...28)
                                    .labelsHidden()
                            }
                            .accessibilityLabel(L.s.settingsFontSize)
                            .accessibilityValue("\(Int(workspace.fontSize)) pt")
                        }
                    }

                    SheetHairline()
                        .padding(.vertical, Minimal.space4)

                    // 画布
                    SheetSectionTitle(text: L.s.settingsCanvas)
                        .padding(.bottom, Minimal.space1)

                    VStack(alignment: .leading, spacing: Minimal.space1) {
                        Toggle(isOn: $workspace.showConsensus) {
                            Text(L.s.settingsShowConsensus)
                                .font(.system(size: Minimal.fontSM))
                        }
                        .toggleStyle(.checkbox)

                        Toggle(isOn: $workspace.highContrast) {
                            Text(L.s.settingsHighContrast)
                                .font(.system(size: Minimal.fontSM))
                        }
                        .toggleStyle(.checkbox)

                        Toggle(isOn: $workspace.focusDimMode) {
                            Text(L.s.settingsFocusDim)
                                .font(.system(size: Minimal.fontSM))
                        }
                        .toggleStyle(.checkbox)
                    }
                    .frame(minHeight: 26 * 3, alignment: .leading)

                    SheetHairline()
                        .padding(.vertical, Minimal.space4)

                    // 分析口径
                    SheetSectionTitle(text: L.s.sidebarGroupAnalysis)
                        .padding(.bottom, Minimal.space2)

                    rows {
                        settingRow(L.s.consensusMode) {
                            Picker("", selection: $consensusMode) {
                                Text(L.s.consensusMajority).tag(0)
                                Text(L.s.consensusIUPAC).tag(1)
                                Text(L.s.consensusStrict).tag(2)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: controlWidth, alignment: .leading)
                            .accessibilityLabel(L.s.consensusMode)
                            .onChange(of: consensusMode) { _, newVal in
                                UserDefaults.standard.set(newVal, forKey: "SeqAlignMac.consensusMode")
                                workspace.objectWillChange.send()
                            }
                        }

                        // 阈值只对 ClustalX 方案生效：不相关时不该出现，避免用户为无效选项做判断
                        if workspace.currentScheme == .clustalX {
                            VStack(alignment: .leading, spacing: Minimal.space1) {
                                HStack(spacing: Minimal.space2) {
                                    Text(L.s.clustalXThreshold)
                                        .font(.system(size: Minimal.fontXXS))
                                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                                    Spacer()
                                    Text("\(Int(clustalXThreshold * 100))%")
                                        .font(.system(size: Minimal.fontXXS, design: .monospaced))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
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
                                .accessibilityLabel(L.s.clustalXThreshold)
                                .accessibilityValue("\(Int(clustalXThreshold * 100))%")

                                Text(L.s.clustalXThresholdHint)
                                    .font(.system(size: Minimal.fontXXS))
                                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            SheetHairline()
                .padding(.top, Minimal.space3)

            HStack {
                Spacer()
                MinimalSecondaryButton(title: L.s.settingsDone) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Minimal.space3)
        }
        .padding(Minimal.space5)
        .frame(width: 460)
        .frame(minHeight: 400, maxHeight: 540)
        // 原生控件（分段、勾选）默认取系统蓝，这里统一压到主色（Radix gray-12 系），
        // 面板里不允许出现调色板外的颜色
        .tint(Color(Minimal.primary(dark: isDarkAppearance)))
        .minimalSheetContainer()
    }

    /// 一组设置行，行距统一
    private func rows<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Minimal.space2) {
            content()
        }
    }

    /// 标签列定宽 + 控件左缘对齐
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
