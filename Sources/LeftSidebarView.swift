//  LeftSidebarView.swift
//  SeqAlignMac — 左侧栏视图（从 ContentView.swift 拆分）
//
//  包含：文件/分析/配色/视图编辑/缩放/导出/系统分组按钮。
//  配色方案改为下拉菜单（UI5 修复），搜索栏常驻顶部（UI7 修复）。

import AppKit
import SwiftUI

// MARK: - 配色选项

struct SchemeOption: Identifiable {
    let id: ColorScheme
    let title: String
}

// MARK: - 撤销/重做按钮

/// 观察 WindowRegistry（editRevision + activeWorkspace 均 @Published）：
/// 任意工作区编辑或活动标签切换都会重算禁用态。
struct UndoRedoSidebarButtons: View {
    @ObservedObject private var registry = WindowRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarButton(title: L.s.toolbarUndo, systemImage: "arrow.uturn.backward") {
                UndoRedoCoordinator.shared.undoCurrent()
            }
            .help(L.s.helpUndo)
            .disabled(!UndoRedoCoordinator.shared.canUndo)

            SidebarButton(title: L.s.toolbarRedo, systemImage: "arrow.uturn.forward") {
                UndoRedoCoordinator.shared.redoCurrent()
            }
            .help(L.s.helpRedo)
            .disabled(!UndoRedoCoordinator.shared.canRedo)
        }
    }
}

// MARK: - 左侧栏

extension ContentView {
    var leftSidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
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
                    SidebarButton(title: L.s.toolbarExample, systemImage: "sparkles") {
                        HelpManager.shared.loadExample()
                    }
                    .help(L.s.helpExample)

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

                    SidebarButton(title: L.s.toolbarTree, systemImage: "point.3.filled.connected.trianglepath.dotted") {
                        showTreeSheet = true
                    }
                    .help(L.s.toolbarTree)
                    .disabled(workspace.currentAlignment == nil)

                    SidebarButton(title: L.s.toolbarWindowChart, systemImage: "waveform.path.ecg") {
                        showWindowChartSheet = true
                    }
                    .help(L.s.toolbarWindowChart)
                    .disabled(workspace.currentAlignment == nil)

                    SidebarButton(title: L.s.toolbarAnnotation, systemImage: "tag") {
                        showAnnotationSheet = true
                    }
                    .help(L.s.toolbarAnnotation)
                    .disabled(workspace.currentAlignment == nil)

                    sidebarDivider

                    // 配色（带分组标题）
                    sidebarSectionHeader(L.s.toolbarColorScheme)
                    sidebarSchemePicker

                    sidebarDivider

                    // 视图/编辑
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

                    SidebarButton(title: L.s.toolbarDifference, systemImage: "rectangle.and.rectangle.tilted.right",
                                  isActive: workspace.differenceMode) {
                        if workspace.differenceMode {
                            workspace.differenceMode = false
                        } else {
                            // 以当前光标行为参考行（ 参考序列模式）
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

                    // 撤销/重做禁用态跟随（纯栈操作后按钮禁用态可能滞留，需显式刷新）
                    UndoRedoSidebarButtons()

                    sidebarDivider

                    // 缩放
                    sidebarZoomControls

                    sidebarDivider

                    // 导出（分组标题 + 图像/序列两个子菜单，不再重复「导出」字样）
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
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)

            // 底部固定区：外观 + 语言
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(Color(Minimal.border(dark: isDarkAppearance)))
                    .frame(height: 1)

                ThemeSwitchMenu()
                LanguageSwitchButton()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(width: leftSidebarWidth)
        .background(Color(Minimal.controlSurface(dark: isDarkAppearance)))
    }

    var sidebarDivider: some View {
        Rectangle()
            .fill(Color(Minimal.border(dark: isDarkAppearance)))
            .frame(height: 1)
            .opacity(Minimal.dividerOpacity)   // opacity 令牌化
            .padding(.vertical, Minimal.space1 + 2)   // 分组间垂直呼吸，保证各组间距均匀
    }

    func sidebarSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: Minimal.fontXXS, weight: .semibold))
            .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
            .tracking(0.5)
            .padding(.leading, Minimal.space2)
            .padding(.top, Minimal.space1 + 2)
            .padding(.bottom, Minimal.space1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 配色选择器（SidebarMenuButton：与普通侧栏按钮像素级对齐）
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

    // MARK: 缩放控制（segmented control 风格）
    var sidebarZoomControls: some View {
        VStack(alignment: .leading, spacing: Minimal.space1) {
            // 分组标题复用 sidebarSectionHeader
            sidebarSectionHeader(L.s.toolbarZoom)

            HStack(spacing: 0) {
                ZoomSegmentButton(systemImage: "minus.magnifyingglass",
                                  help: L.s.helpZoomOut) { ZoomManager.shared.zoomOut() }

                // 分隔线
                Rectangle().fill(Color(Minimal.border(dark: isDarkAppearance))).frame(width: 1)

                // 百分比
                Button(action: { ZoomManager.shared.reset() }) {
                    Text("\(Int(workspace.fontSize / Workspace.defaultFontSize * 100))%")
                        .font(.system(size: Minimal.fontXS, weight: .medium))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: Minimal.controlH)
                        .contentShape(Rectangle())
                        .background(Color.clear)
                }
                .buttonStyle(MinimalButtonStyle())
                .help(L.s.helpZoomReset)
                .accessibilityLabel(L.s.helpZoomReset)
                // 缩放比例动态播报
                .accessibilityValue("\(Int(workspace.fontSize / Workspace.defaultFontSize * 100))%")

                // 分隔线
                Rectangle().fill(Color(Minimal.border(dark: isDarkAppearance))).frame(width: 1)

                ZoomSegmentButton(systemImage: "plus.magnifyingglass",
                                  help: L.s.helpZoomIn) { ZoomManager.shared.zoomIn() }
            }
            .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .fill(Color(Minimal.card(dark: isDarkAppearance))))
            .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
        }
    }

    /// 缩放三联按钮（含 hover / 按压反馈）
    private struct ZoomSegmentButton: View {
        let systemImage: String
        let help: String
        let action: () -> Void
        @State private var hovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: Minimal.fontSM))
                    .frame(width: Minimal.controlH + Minimal.space2, height: Minimal.controlH)
                    .background(hovered && isEnabled
                                ? Color(Minimal.border(dark: isDarkAppearance).withAlphaComponent(0.4))
                                : Color.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MinimalButtonStyle())
            .help(help)
            .accessibilityLabel(help)
            .onHover { hovered = $0 }
        }
    }

    // MARK: 导出菜单（分组标题已由 sidebarGroupExport 提供，此处不再重复「导出」文字）
    var sidebarExportMenu: some View {
        let hasAlignment = workspace.currentAlignment != nil
        return VStack(alignment: .leading, spacing: Minimal.space1) {
            // 图像导出（SidebarMenuButton：与普通侧栏按钮像素级对齐）
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

            // 序列导出（SidebarMenuButton：与普通侧栏按钮像素级对齐）
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
