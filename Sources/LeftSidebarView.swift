//  LeftSidebarView.swift
//  SeqAlignMac — 左侧栏
//
//  信息结构：文件 / 编辑 / 分析 / 显示 / 导出 / 系统。分组只承载“到哪里做事”，
//  不重复解释功能；行高 28、图标列 16、文字列统一左边界，保证纵向光学对齐。

import AppKit
import SwiftUI

// MARK: - 配色选项

struct SchemeOption: Identifiable {
    let id: ColorScheme
    let title: String
}

// MARK: - 撤销/重做（单行图标组，节省纵向空间）

/// 观察 WindowRegistry（editRevision + activeWorkspace 均 @Published）：
/// 任意工作区编辑或活动标签切换都会重算禁用态。
struct UndoRedoSidebarButtons: View {
    @ObservedObject private var registry = WindowRegistry.shared

    var body: some View {
        HStack(spacing: Minimal.space1) {
            MinimalIconButton(systemImage: "arrow.uturn.backward", help: L.s.helpUndo) {
                UndoRedoCoordinator.shared.undoCurrent()
            }
            .disabled(!UndoRedoCoordinator.shared.canUndo)

            MinimalIconButton(systemImage: "arrow.uturn.forward", help: L.s.helpRedo) {
                UndoRedoCoordinator.shared.redoCurrent()
            }
            .disabled(!UndoRedoCoordinator.shared.canRedo)

            Spacer(minLength: 0)
        }
        .frame(height: Minimal.controlH)
        .padding(.leading, Minimal.space2 - 6)   // 图标在 28pt 热区内居中，左缘与 16pt 图标列对齐
        .opacity(1)
    }
}

// MARK: - 左侧栏

extension ContentView {
    var leftSidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Minimal.space1) {
                    // 文件
                    sidebarSectionHeader(L.s.sidebarGroupFile)
                    SidebarButton(title: L.s.toolbarOpen, systemImage: "folder") {
                        OpenFileManager.shared.openFile()
                    }
                    .help(L.s.helpOpenFile)
                    SidebarButton(title: L.s.toolbarSave, systemImage: "square.and.arrow.down") {
                        SaveManager.shared.saveCurrent()
                    }
                    .help(L.s.helpSave)
                    .disabled(workspace.currentAlignment == nil)

                    sidebarDivider

                    // 编辑
                    sidebarSectionHeader(L.s.sidebarGroupEdit)
                    UndoRedoSidebarButtons()

                    sidebarDivider

                    // 分析
                    sidebarSectionHeader(L.s.sidebarGroupAnalysis)
                    SidebarButton(title: L.s.toolbarRunMSA, systemImage: "arrow.triangle.2.circlepath") {
                        NotificationCenter.default.post(name: .runAlignment, object: nil)
                    }
                    .help(L.s.helpRunMSA)
                    .disabled(workspace.currentAlignment == nil)

                    SidebarButton(title: L.s.toolbarTranslate, systemImage: "translate") {
                        showingTranslateSheet = true
                    }
                    .help(workspace.currentAlignment?.datatype == .aminoAcid ? L.s.helpTranslateDisabled : L.s.helpTranslate)
                    .disabled(workspace.currentAlignment == nil || workspace.currentAlignment?.datatype == .aminoAcid)

                    SidebarButton(title: L.s.toolbarPrimer, systemImage: "atom") {
                        NotificationCenter.default.post(name: .showPrimer, object: nil)
                    }
                    .help(workspace.currentAlignment?.datatype == .aminoAcid ? L.s.helpPrimerDisabled : L.s.helpPrimer)
                    .disabled(workspace.currentAlignment == nil || workspace.currentAlignment?.datatype == .aminoAcid)

                    SidebarButton(title: L.s.toolbarQuality, systemImage: "gauge.with.dots.needle.67percent") {
                        ToolActions.shared.showQualityReport()
                    }
                    .help(L.s.helpQuality)
                    .disabled(workspace.currentAlignment == nil)

                    SidebarButton(title: L.s.toolbarLogo, systemImage: "square.stack.3d.up") {
                        showLogoSheet = true
                    }
                    .help(L.s.toolbarLogo)
                    .disabled(workspace.currentAlignment == nil)

                    SidebarButton(title: L.s.toolbarWindowChart, systemImage: "waveform.path.ecg") {
                        showWindowChartSheet = true
                    }
                    .help(L.s.toolbarWindowChart)
                    .disabled(workspace.currentAlignment == nil)

                    SidebarButton(title: L.s.toolbarTree, systemImage: "point.3.filled.connected.trianglepath.dotted") {
                        showTreeSheet = true
                    }
                    .help(L.s.toolbarTree)
                    .disabled(workspace.currentAlignment == nil)

                    SidebarButton(title: L.s.toolbarAnnotation, systemImage: "tag") {
                        showAnnotationSheet = true
                    }
                    .help(L.s.toolbarAnnotation)
                    .disabled(workspace.currentAlignment == nil)

                    sidebarDivider

                    // 显示：配色、搜索、差异、图例、缩放
                    sidebarSectionHeader(L.s.toolbarColorScheme)
                    sidebarSchemePicker

                    sidebarDivider

                    sidebarSectionHeader(L.s.sidebarGroupView)
                    SidebarButton(title: L.s.toolbarSearch, systemImage: "magnifyingglass",
                                  isActive: workspace.isSearching) {
                        // 切换搜索：显示搜索栏时按钮高亮，隐藏时恢复
                        if workspace.isSearching {
                            workspace.isSearching = false
                        } else {
                            SearchManager.shared.showSearch()
                        }
                    }
                    .help(L.s.helpSearch)
                    .disabled(workspace.currentAlignment == nil)

                    SidebarButton(title: L.s.toolbarDifference, systemImage: "rectangle.split.2x1",
                                  isActive: workspace.differenceMode) {
                        if workspace.differenceMode {
                            workspace.differenceMode = false
                        } else {
                            // 以当前光标行为参考行（参考序列模式）
                            workspace.referenceRow = cursorRow
                            workspace.differenceMode = true
                        }
                    }
                    .help(L.s.helpDifference)
                    .disabled(workspace.currentAlignment == nil)

                    SidebarButton(title: L.s.toolbarLegend, systemImage: "info.circle") {
                        showLegend = true
                    }
                    .help(L.s.helpLegend)
                    .popover(isPresented: $showLegend) {
                        LegendPopover(scheme: workspace.currentScheme)
                    }

                    sidebarZoomControls

                    sidebarDivider

                    // 导出：图像 / 序列两个子菜单，分组标题不重复「导出」字样
                    sidebarSectionHeader(L.s.sidebarGroupExport)
                    sidebarExportMenu

                    sidebarDivider

                    // 系统
                    sidebarSectionHeader(L.s.sidebarGroupSystem)
                    SidebarButton(title: L.s.toolbarCommandPalette, systemImage: "command") {
                        CommandPalette.shared.toggle()
                    }
                    .help(L.s.helpCmdPalette)
                    SidebarButton(title: L.s.toolbarSettings, systemImage: "gearshape") {
                        NotificationCenter.default.post(name: .showSettings, object: nil)
                    }
                    .help(L.s.helpSettings)
                }
                .padding(.vertical, Minimal.space2)
                .padding(.horizontal, Minimal.space2 - 2)
            }

            Spacer(minLength: 0)

            // 底部固定区：外观 + 语言
            VStack(alignment: .leading, spacing: Minimal.space2 - 2) {
                Rectangle()
                    .fill(Color(Minimal.border(dark: isDarkAppearance)))
                    .frame(height: Minimal.hairline)

                ThemeSwitchMenu()
                LanguageSwitchButton()
            }
            .padding(.horizontal, Minimal.space2 - 2)
            .padding(.bottom, Minimal.space2)
        }
        .frame(width: leftSidebarWidth)
        .background(Color(Minimal.panel(dark: isDarkAppearance)))
        // 与内容区之间只留一条 0.5pt 分隔线，面板本身不再加边框
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(Minimal.border(dark: isDarkAppearance)))
                .frame(width: Minimal.hairline)
        }
    }

    var sidebarDivider: some View {
        Rectangle()
            .fill(Color(Minimal.border(dark: isDarkAppearance)))
            .frame(height: Minimal.hairline)
            .padding(.vertical, Minimal.space2 - 2)   // 分组间呼吸：上下各 6pt
    }

    func sidebarSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: Minimal.fontXXS, weight: .semibold))
            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            .tracking(0.5)
            .padding(.leading, Minimal.space2)
            .padding(.top, Minimal.space1)
            .padding(.bottom, Minimal.space1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 配色选择器（与普通侧栏按钮像素级对齐）
    var sidebarSchemePicker: some View {
        SidebarMenuButton(
            title: currentSchemeName,
            systemImage: "paintpalette",
            entries: Self.schemeOptions.map { opt in
                .item(opt.title) { workspace.currentScheme = opt.id }
            },
            isDisabled: workspace.currentAlignment == nil,
            currentItemIndex: Self.schemeOptions.firstIndex(where: { $0.id == workspace.currentScheme })
        )
        .help(L.s.helpColorScheme)
    }

    var currentSchemeName: String {
        Self.schemeOptions.first(where: { $0.id == workspace.currentScheme })?.title ?? L.s.schemeMinimal
    }

    static var schemeOptions: [SchemeOption] {
        [
            SchemeOption(id: .minimal, title: L.s.schemeMinimal),
            SchemeOption(id: .clustalX, title: L.s.schemeClustalX),
            SchemeOption(id: .zappo, title: L.s.schemeZappo),
            SchemeOption(id: .seaView, title: L.s.schemeSeaView),
            SchemeOption(id: .defaultNucleotide, title: L.s.schemeDefault),
            SchemeOption(id: .transitionTransversion, title: L.s.schemeTransitionTransversion),
            SchemeOption(id: .okabeIto, title: L.s.schemeOkabeIto),
        ]
    }

    // MARK: 缩放控制（分段控件：外框 6，内段透明，0.5pt 分隔线）
    var sidebarZoomControls: some View {
        HStack(spacing: 0) {
            ZoomSegmentButton(systemImage: "minus", help: L.s.helpZoomOut) {
                ZoomManager.shared.zoomOut()
            }

            Rectangle()
                .fill(Color(Minimal.border(dark: isDarkAppearance)))
                .frame(width: Minimal.hairline)

            Button(action: { ZoomManager.shared.reset() }) {
                Text("\(Int(workspace.fontSize / Workspace.defaultFontSize * 100))%")
                    .font(.system(size: Minimal.fontXXS, weight: .medium))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: Minimal.controlH)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MinimalButtonStyle())
            .help(L.s.helpZoomReset)
            .accessibilityLabel(L.s.helpZoomReset)
            .accessibilityValue("\(Int(workspace.fontSize / Workspace.defaultFontSize * 100))%")

            Rectangle()
                .fill(Color(Minimal.border(dark: isDarkAppearance)))
                .frame(width: Minimal.hairline)

            ZoomSegmentButton(systemImage: "plus", help: L.s.helpZoomIn) {
                ZoomManager.shared.zoomIn()
            }
        }
        .frame(height: Minimal.controlH)
        .background(
            RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .fill(Color(Minimal.surface(dark: isDarkAppearance)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: Minimal.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous))
        .padding(.horizontal, Minimal.space2)
    }

    /// 缩放分段按钮（内段无自身圆角，由外框统一裁切，避免内圆角与外圆角不同心）
    private struct ZoomSegmentButton: View {
        let systemImage: String
        let help: String
        let action: () -> Void
        @State private var hovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: Minimal.fontXS, weight: .medium))
                    .frame(width: 34, height: Minimal.controlH)
                    .background(hovered && isEnabled
                                ? Color(Minimal.hover(dark: NSAppearance.isDarkNow))
                                : Color.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MinimalButtonStyle())
            .help(help)
            .accessibilityLabel(help)
            .onHover { hovered = $0 }
        }
    }

    // MARK: 导出菜单
    var sidebarExportMenu: some View {
        let hasAlignment = workspace.currentAlignment != nil
        return VStack(alignment: .leading, spacing: Minimal.space1) {
            // 图像导出
            SidebarMenuButton(
                title: L.s.exportImage,
                systemImage: "photo",
                showChevron: false,
                entries: [
                    .item(L.s.exportPreviewTitle) {
                        NotificationCenter.default.post(name: .showExportPreview, object: nil)
                    },
                    .divider,
                    .item(L.s.exportPNG) { ExportCoordinator.shared.exportCurrent(format: .png) },
                    .item(L.s.exportPDF) { ExportCoordinator.shared.exportCurrent(format: .pdf) },
                    .item(L.s.exportSVG) { ExportCoordinator.shared.exportCurrent(format: .svg) },
                ],
                isDisabled: !hasAlignment
            )
            .help(L.s.helpExport)

            // 序列导出
            SidebarMenuButton(
                title: L.s.exportSequence,
                systemImage: "doc.text",
                showChevron: false,
                entries: [
                    .item(L.s.exportFASTA) { SaveManager.shared.saveAs(format: .fasta) },
                    .item(L.s.exportNEXUS) { SaveManager.shared.saveAs(format: .nexus) },
                    .item(L.s.exportPHYLIP) { SaveManager.shared.saveAs(format: .phylip) },
                    .item(L.s.exportCLUSTAL) { SaveManager.shared.saveAs(format: .clustal) },
                    .item(L.s.exportMSF) { SaveManager.shared.saveAs(format: .msf) },
                    .item(AppStrings.formatStockholm) { SaveManager.shared.saveAs(format: .stockholm) },
                ],
                isDisabled: !hasAlignment
            )
            .help(L.s.helpExport)
        }
    }
}
