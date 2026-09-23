//  ContentView.swift
//  SeqAlignMac — 主窗口内容视图（三栏布局 + 中英文国际化）
//
//  模块划分：
//  本文件仅保留 ContentView 的结构体定义、状态变量、body 组合与 Sheet 挂载。
//  左侧栏 → LeftSidebarView.swift
//  中栏（搜索栏/画布/状态栏）→ CenterPanelView.swift
//  通知与上下文动作 → ContentView+Actions.swift
//  弹窗视图 → SheetViews.swift / ToolSheetViews.swift
//  共享组件 → SharedUIComponents.swift
//  导出预览 → ExportPreviewSheet.swift

import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var langManager = LanguageManager.shared

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    // MARK: - 状态变量（非 private，供 extension 跨文件访问）

    @State var cursorRow: Int = 0
    @State var cursorCol: Int = 0
    @State var showingPrimerSheet = false
    @State var showingSettings = false
    @State var showingTranslateSheet = false
    @State var renameSheet = false
    @State var renameText = ""
    @State var renameRow = 0
    @State var moveSheet = false
    @State var moveFrom = 0
    @State var moveTo = 0
    @State var externalAlignerSheet = false
    @State var externalAlignerPath = ""
    @State var showLegend = false
    @State var showAboutSheet = false
    @State var showGuideSheet = false
    @State var showQualityReportSheet = false
    @State var showCommandPalette = false
    @State var showExportPreview = false
    @State var showLogoSheet = false
    @State var showTreeSheet = false
    @State var showWindowChartSheet = false
    @State var showAnnotationSheet = false
    @State var primerPrefill = ""
    @StateObject var exportPreviewModel = ExportPreviewModel()
    /// 通知 observer token：onDisappear 统一反注册，
    /// 否则 NotificationCenter 永久持有闭包，每关一个标签泄漏一个 Workspace
    @State var notificationObservers: [NSObjectProtocol] = []
    @State var statsPanelWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "SeqAlignMac.statsPanelWidth")
        return saved > 0 ? CGFloat(saved) : 264
    }()
    @State var leftSidebarWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "SeqAlignMac.leftSidebarWidth")
        return saved > 0 ? CGFloat(saved) : 180
    }()

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // 左栏：全部工具按钮（垂直排列，宽度可拖拽调节）
            leftSidebar

            // 左栏拖宽分隔条 + 分隔线
            PanelResizer(width: $leftSidebarWidth, side: .left,
                         minWidth: 150, maxWidth: 320)
            Rectangle()
                .fill(Color(Minimal.border(dark: isDarkAppearance)))
                .frame(width: 1)

            // 中栏：搜索栏 + 画布 + 状态栏
            centerContent

            // 右栏分隔条 + 统计面板
            PanelResizer(width: $statsPanelWidth)
            StatsPanelView(workspace: workspace,
                           cursorRow: cursorRow,
                           cursorCol: cursorCol,
                           width: statsPanelWidth)
        }
        .background(Color(Minimal.surface(dark: isDarkAppearance)))
        // 面板宽度持久化：拖拽由 PanelResizer 经 Binding 回写 @State，
        // 只有 onChange 能可靠观测到这类变更（didSet 不会触发）
        .onChange(of: statsPanelWidth) { _, newValue in
            UserDefaults.standard.set(Double(newValue), forKey: "SeqAlignMac.statsPanelWidth")
        }
        .onChange(of: leftSidebarWidth) { _, newValue in
            UserDefaults.standard.set(Double(newValue), forKey: "SeqAlignMac.leftSidebarWidth")
        }
        // 跟随系统外观变化触发整树重算
        .observingAppearanceChanges()
        // 左栏（宽度 = leftSidebarWidth）滚动条整体不绘制：常驻滑块紧邻左右分界线，
        // 长度只占可视比例，视觉上像一条断掉的半截分隔线
        .thinScrollbars(suppressedSidebarWidth: leftSidebarWidth)
        // 跟随系统外观变化触发整树重算
        .observingAppearanceChanges()
        .onAppear {
            WindowRegistry.shared.register(workspace)
            WindowRegistry.shared.activeWorkspace = workspace
            setupNotifications()
            if let (align, name, format) = PendingWindowData.consume() {
                workspace.loadAlignment(align, fileName: name, format: format)
            }
            // 调试自检：SEQALIGN_SELFTEST=1 时检查左栏滚动条抑制是否生效
            if ProcessInfo.processInfo.environment["SEQALIGN_SELFTEST"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    ThinScrollerModifier.selfTestSidebarSuppression(expectedWidth: leftSidebarWidth)
                }
            }
        }
        .onDisappear {
            for token in notificationObservers {
                NotificationCenter.default.removeObserver(token)
            }
            notificationObservers.removeAll()
            WindowRegistry.shared.unregister(workspace)
        }
        .onChange(of: workspace.currentFileName) { _, _ in
            NotificationCenter.default.post(name: .tabDataChanged, object: nil)
        }
        .onChange(of: workspace.isDirty) { _, _ in
            NotificationCenter.default.post(name: .tabDataChanged, object: nil)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        // — Sheets（Bug #3：sheet dismiss 后焦点回流画布）—
        .modifier(SheetFocusRestorer(
            showingPrimerSheet: $showingPrimerSheet,
            showingSettings: $showingSettings,
            showingTranslateSheet: $showingTranslateSheet,
            renameSheet: $renameSheet,
            moveSheet: $moveSheet,
            externalAlignerSheet: $externalAlignerSheet,
            showAboutSheet: $showAboutSheet,
            showGuideSheet: $showGuideSheet,
            showQualityReportSheet: $showQualityReportSheet,
            showCommandPalette: $showCommandPalette,
            showExportPreview: $showExportPreview,
            showLogoSheet: $showLogoSheet,
            showTreeSheet: $showTreeSheet,
            showWindowChartSheet: $showWindowChartSheet,
            showAnnotationSheet: $showAnnotationSheet,
            pendingCloseRequest: $workspace.pendingCloseRequest,
            primerPrefill: primerPrefill,
            renameText: $renameText,
            renameRow: $renameRow,
            moveFrom: $moveFrom,
            moveTo: $moveTo,
            externalAlignerPath: $externalAlignerPath,
            workspace: workspace,
            exportPreviewModel: exportPreviewModel
        ))
        // 导出预览触发时配置模型
        .onChange(of: showExportPreview) { _, isShowing in
            if isShowing, let align = workspace.currentAlignment {
                exportPreviewModel.configure(
                    alignment: align,
                    scheme: workspace.currentScheme,
                    fontSize: workspace.fontSize,
                    selection: workspace.currentSelection,
                    darkMode: NSAppearance.isDarkNow
                )
            }
        }
    }
}

// MARK: - Bug #3：Sheet dismiss 后焦点回流画布的 ViewModifier
// 把所有 sheet + onChange 拆到独立 modifier，避免 body 中修饰器链过长导致类型检查超时

struct SheetFocusRestorer: ViewModifier {
    @Binding var showingPrimerSheet: Bool
    @Binding var showingSettings: Bool
    @Binding var showingTranslateSheet: Bool
    @Binding var renameSheet: Bool
    @Binding var moveSheet: Bool
    @Binding var externalAlignerSheet: Bool
    @Binding var showAboutSheet: Bool
    @Binding var showGuideSheet: Bool
    @Binding var showQualityReportSheet: Bool
    @Binding var showCommandPalette: Bool
    @Binding var showExportPreview: Bool
    @Binding var showLogoSheet: Bool
    @Binding var showTreeSheet: Bool
    @Binding var showWindowChartSheet: Bool
    @Binding var showAnnotationSheet: Bool
    @Binding var pendingCloseRequest: Bool
    let primerPrefill: String
    @Binding var renameText: String
    @Binding var renameRow: Int
    @Binding var moveFrom: Int
    @Binding var moveTo: Int
    @Binding var externalAlignerPath: String
    let workspace: Workspace
    let exportPreviewModel: ExportPreviewModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingPrimerSheet) {
                PrimerCalculatorView(isPresented: $showingPrimerSheet, prefill: primerPrefill)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(isPresented: $showingSettings, workspace: workspace)
            }
            .sheet(isPresented: $showingTranslateSheet) {
                TranslationOptionsView(isPresented: $showingTranslateSheet, workspace: workspace)
            }
            .sheet(isPresented: $renameSheet) {
                RenameView(isPresented: $renameSheet, name: $renameText, row: $renameRow, workspace: workspace)
            }
            .sheet(isPresented: $moveSheet) {
                MoveSequenceView(isPresented: $moveSheet, from: $moveFrom, to: $moveTo, workspace: workspace)
            }
            .sheet(isPresented: $externalAlignerSheet) {
                ExternalAlignerView(isPresented: $externalAlignerSheet, path: $externalAlignerPath)
            }
            .sheet(isPresented: $showAboutSheet) { AboutView() }
            .sheet(isPresented: $showGuideSheet) { GuideView() }
            .sheet(isPresented: $showQualityReportSheet) { QualityReportView(workspace: workspace) }
            .sheet(isPresented: $showCommandPalette) { CommandPaletteView() }
            .sheet(isPresented: $showExportPreview) {
                ExportPreviewSheet(model: exportPreviewModel, isPresented: $showExportPreview)
            }
            .sheet(isPresented: $showLogoSheet) { SequenceLogoView(workspace: workspace) }
            .sheet(isPresented: $showTreeSheet) { TreeSheetView(workspace: workspace) }
            .sheet(isPresented: $showWindowChartSheet) { WindowChartSheetView(workspace: workspace) }
            .sheet(isPresented: $showAnnotationSheet) { AnnotationSheetView(workspace: workspace) }
            .sheet(isPresented: Binding<Bool>(
                get: { pendingCloseRequest },
                set: { (v: Bool) in if !v { pendingCloseRequest = false } }
            )) {
                UnsavedChangesView(workspace: workspace)
            }
            .onChange(of: showingPrimerSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showingSettings) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showingTranslateSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: renameSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: moveSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: externalAlignerSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showAboutSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showGuideSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showQualityReportSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showCommandPalette) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showExportPreview) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showLogoSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showTreeSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showWindowChartSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: showAnnotationSheet) { _, v in if !v { Self.restoreFocus() } }
            .onChange(of: pendingCloseRequest) { _, v in if !v { Self.restoreFocus() } }
    }

    static func restoreFocus() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow, let cv = window.contentView else { return }
            func find(in view: NSView) -> AlignmentCanvasView? {
                if let c = view as? AlignmentCanvasView { return c }
                if let sv = view as? NSScrollView, let c = sv.documentView as? AlignmentCanvasView { return c }
                for sub in view.subviews { if let f = find(in: sub) { return f } }
                return nil
            }
            if let canvas = find(in: cv) { window.makeFirstResponder(canvas) }
        }
    }
}
