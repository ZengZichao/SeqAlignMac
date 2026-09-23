//  SeqAlignMacApp.swift
//  SeqAlignMac — 序列对齐查看/编辑器（macOS 原生，中英文双语）
//
//  - 全部菜单字符串改用 L.s.xxx 获取当前语言文本
//  - 新增「语言」菜单（视图菜单下），支持中英文切换
//  - 窗口最小宽度增大以适应三栏布局
//  - 退出守卫、Toast 等消息本地化

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 应用入口

@main
struct SeqAlignMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // 无界面 CLI 模式：SeqAlignMac cli stats/export ...（ 可编程性）
        let args = ProcessInfo.processInfo.arguments
        if args.count > 1, args[1] == "cli" {
            CLIRunner.run(args)
        }
    }

    var body: some Scene {
        WindowGroupForAlignment()
    }
}

// MARK: - 窗口场景

struct WindowGroupForAlignment: Scene {
    var body: some Scene {
        WindowGroup(L.s.windowTitlePrefix, id: "seqalign-main") {
            WindowRootView()
                .frame(minWidth: 1100, minHeight: 520)
        }
        .defaultSize(width: 1500, height: 880)
        .commands {
            SeqAlignCommands()
        }
    }
}

// MARK: - 多窗口工作区状态

/// 搜索输入子模型。搜索框每个按键只失效订阅本模型的搜索栏视图，
/// 不再经由 Workspace.objectWillChange 牵连整棵视图树。
final class SearchTextModel: ObservableObject {
    @Published var text = ""
    /// #8：搜索防抖 DispatchWorkItem
    var debounceWorkItem: DispatchWorkItem?
}

/// 加载进度子模型。加载百分比的高频写入只失效加载覆盖层。
/// cancelLoading 经锁保护（后台解析线程读、主线程写，不再裸读写 Bool）。
final class LoadProgressModel: ObservableObject {
    @Published var isLoading = false
    @Published var progress: Double = 0
    private let cancelLock = NSLock()
    private var cancelFlag = false

    var cancelLoading: Bool {
        get { cancelLock.lock(); defer { cancelLock.unlock() }; return cancelFlag }
        set { cancelLock.lock(); cancelFlag = newValue; cancelLock.unlock() }
    }
}

/// Toast 子模型。toast 显示/清除只失效 toast 视图。
enum ToastKind { case success, info, warning, error }

final class ToastModel: ObservableObject {
    @Published var message: String?
    @Published var kind: ToastKind = .success
    private var clearWorkItem: DispatchWorkItem?

    func show(_ text: String, kind: ToastKind = .success) {
        self.kind = kind
        message = text
        clearWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.message == text { self?.message = nil }
        }
        clearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}

/// 跨线程安全的代次号。主线程写、后台搜索线程经锁读取，
/// 为后台搜索提供协作取消（后台直接读 Int 属形式化数据竞争）。
final class GenerationToken {
    private let lock = NSLock()
    private var value: Int
    init(_ v: Int = 0) { value = v }
    var current: Int {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

final class Workspace: ObservableObject {
    /// 默认字号（缩放百分比基准 / 重置值 / LeftSidebar 显示共用，消除双处硬编码）
    static let defaultFontSize: CGFloat = 13

    @Published var currentAlignment: Alignment?
    @Published var currentFileName: String = ""
    @Published var currentFormat: AlignmentFormat = .fasta
    @Published var sourceURL: URL?
    /// 文档来源于 gzip（.fasta.gz 等）。sourceURL 仍指向 .gz，
    /// 原地保存时必须把序列化文本重新 gzip 后再写盘，否则明文破坏 gzip 容器。
    @Published var sourceIsCompressed: Bool = false
    @Published var isDirty: Bool = false
    @Published var isSaving: Bool = false
    @Published var pendingCloseRequest = false
    @Published var pendingCloseIsTab = false
    @Published var currentSelection: SelectionRange?
    @Published var errorMessage: String?
    @Published var toastModel = ToastModel()
    @Published var loadModel = LoadProgressModel()
    @Published var searchTextModel = SearchTextModel()
    @Published var currentScheme: ColorScheme = {
        // integer(forKey:) 未设置时返回 0（恰为 .defaultNucleotide 的 rawValue），
        // 会覆盖「minimal 为默认」的意图；显式区分未设置状态
        if UserDefaults.standard.object(forKey: "SeqAlignMac.currentScheme") == nil {
            return .minimal
        }
        return ColorScheme(rawValue: Int32(UserDefaults.standard.integer(forKey: "SeqAlignMac.currentScheme"))) ?? .minimal
    }() {
        didSet { UserDefaults.standard.set(currentScheme.rawValue, forKey: "SeqAlignMac.currentScheme") }
    }
    @Published var showConsensus: Bool = true
    @Published var fontSize: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "SeqAlignMac.fontSize")
        return saved > 0 ? CGFloat(saved) : 13
    }() {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: "SeqAlignMac.fontSize") }
    }
    @Published var highContrast: Bool = UserDefaults.standard.bool(forKey: "SeqAlignMac.highContrast") {
        didSet { UserDefaults.standard.set(highContrast, forKey: "SeqAlignMac.highContrast") }
    }
    @Published var focusDimMode: Bool = UserDefaults.standard.bool(forKey: "SeqAlignMac.focusDimMode") {
        didSet { UserDefaults.standard.set(focusDimMode, forKey: "SeqAlignMac.focusDimMode") }
    }
    /// 差异模式：以 referenceRow 为参考，与参考相同的残基淡化显示，突出差异位点
    @Published var differenceMode: Bool = false
    @Published var referenceRow: Int = 0

    @Published var isSearching = false
    @Published var searchHits: [SearchHit] = []
    @Published var currentHitIndex = -1
    @Published var searchCompleted = false
    @Published var searchScope: SearchScope = .content
    @Published var searchUseRegex = false
    @Published var searchComputing = false
    /// 搜索代际号：经锁保护，后台线程可安全读取做协作取消
    private let searchGeneration = GenerationToken(0)
    /// 文件加载代次号：并发打开/多文件拖放时只让最新一次加载的结果落盘
    var loadGeneration = 0

    // —— 兼容转发：既有调用点继续读写 workspace.searchText / isLoading / cancelLoading，
    //    写入只失效对应子模型，不再牵连整个 Workspace 观察树——
    var searchText: String {
        get { searchTextModel.text }
        set { searchTextModel.text = newValue }
    }
    var searchDebounceWorkItem: DispatchWorkItem? {
        get { searchTextModel.debounceWorkItem }
        set { searchTextModel.debounceWorkItem = newValue }
    }
    var isLoading: Bool {
        get { loadModel.isLoading }
        set { loadModel.isLoading = newValue }
    }
    var loadProgress: Double {
        get { loadModel.progress }
        set { loadModel.progress = newValue }
    }
    var cancelLoading: Bool {
        get { loadModel.cancelLoading }
        set { loadModel.cancelLoading = newValue }
    }
    var toastMessage: String? {
        get { toastModel.message }
        set { toastModel.message = newValue }
    }

    /// 画布列统计增量失效信息。nil = 范围未知（画布全量重算）；
    /// Set = 受影响列集合（空集 = 编辑不影响列统计，画布直接复用旧统计）。
    var canvasDirtyColumns: Set<Int>? = Set()

    /// 编辑命令登记脏列（主线程调用）。nil（未知范围）覆盖已有集合。
    func registerEditDirtiness(_ columns: Set<Int>?) {
        guard let cols = columns else {
            canvasDirtyColumns = nil
            return
        }
        if let current = canvasDirtyColumns {
            canvasDirtyColumns = current.union(cols)
        }
    }

    /// 画布取走脏列信息（updateNSView 内调用）；取走后回到「已知空集」基线
    func takeCanvasDirtyColumns() -> Set<Int>? {
        let value = canvasDirtyColumns
        canvasDirtyColumns = Set()
        return value
    }

    /// 使所有在途后台搜索结果失效（关闭搜索 / 加载新文件时调用）
    func cancelPendingSearch() {
        searchGeneration.current += 1
        searchComputing = false
    }

    let id = UUID()
    var undoRedo = UndoRedoManager()

    /// 光标列一致度缓存：避免状态栏 body 内每次求值都加锁复制整列再建字典；
    /// 现按 (对象, revision, 列) 缓存，仅真正变化时算一次。
    private var identityCacheKey: (ObjectIdentifier, UInt64, Int)?
    private var identityCacheValue: Double?

    func cachedColumnIdentity(align: Alignment, col: Int) -> Double? {
        let key = (ObjectIdentifier(align), align.revision, col)
        if let cachedKey = identityCacheKey, cachedKey == key { return identityCacheValue }
        let colRes = align.columnResidues(col: col).filter { $0 != 0x2D }
        let value: Double?
        if colRes.isEmpty {
            value = nil
        } else {
            var freq: [UInt8: Int] = [:]
            for b in colRes { freq[b, default: 0] += 1 }
            value = Double(freq.values.max() ?? 0) / Double(colRes.count)
        }
        identityCacheKey = key
        identityCacheValue = value
        return value
    }

    func loadAlignment(_ alignment: Alignment, fileName: String, format: AlignmentFormat, sourceURL: URL? = nil, sourceIsCompressed: Bool = false) {
        currentAlignment = alignment
        currentFileName = fileName
        currentFormat = format
        self.sourceURL = sourceURL
        self.sourceIsCompressed = sourceIsCompressed
        isLoading = false
        loadProgress = 1.0
        cancelLoading = false
        errorMessage = nil
        isDirty = false
        isSaving = false
        pendingCloseRequest = false
        pendingCloseIsTab = false
        searchGeneration.current += 1
        searchHits = []
        currentHitIndex = -1
        searchCompleted = false
        searchComputing = false
        currentSelection = nil
        canvasDirtyColumns = Set()
        undoRedo.clear()
        WindowRegistry.shared.editRevision += 1
    }

    func showToast(_ message: String, kind: ToastKind = .success) {
        toastModel.show(message, kind: kind)
    }

    func performSearch() {
        guard let align = currentAlignment, !searchText.isEmpty else {
            searchGeneration.current += 1
            searchHits = []
            currentHitIndex = -1
            searchCompleted = false
            return
        }
        let scope = searchScope
        let useRegex = searchUseRegex
        if useRegex, !SearchEngine.validateRegex(searchText, scope: scope) {
            errorMessage = "\(L.s.errorRegexInvalid)\(searchText)"
            searchHits = []
            currentHitIndex = -1
            searchComputing = false
            searchCompleted = true
            return
        }
        // 搜索统一走后台：小比对也不在主线程同步执行，每个防抖周期
        // 都不在主线程深拷贝整个比对——快照移入后台后主线程零拷贝
        searchGeneration.current += 1
        let generation = searchGeneration.current
        let pattern = searchText
        searchComputing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = align.snapshot()
            let engine = SearchEngine(alignment: snapshot, pattern: pattern, scope: scope, useRegex: useRegex)
            // 协作取消——连续键入时进行中的全表扫描提前终止，不堆积
            let hits = engine.findAll(shouldStop: { [weak self] in
                self?.searchGeneration.current != generation
            })
            DispatchQueue.main.async {
                // 代际校验：搜索词被修改/清空或搜索已关闭时丢弃过期结果
                guard let self, self.searchGeneration.current == generation else { return }
                self.searchHits = hits
                self.currentHitIndex = hits.isEmpty ? -1 : 0
                self.searchComputing = false
                self.searchCompleted = true
            }
        }
    }

    func findNext() {
        guard !searchHits.isEmpty else { performSearch(); return }
        currentHitIndex = (currentHitIndex + 1) % searchHits.count
    }

    func findPrev() {
        guard !searchHits.isEmpty else { return }
        currentHitIndex = (currentHitIndex - 1 + searchHits.count) % searchHits.count
    }
}

final class WindowRegistry: ObservableObject {
    static let shared = WindowRegistry()
    @Published var activeWorkspace: Workspace?
    @Published var editRevision = 0
    private var workspaces: [UUID: Workspace] = [:]
    /// 按注册顺序维护的 workspace 列表：unregister 时回退到「最近的其它工作区」，
    /// Dictionary.values 无序，直接取 first 会导致命令路由的兜底目标不确定
    private var workspaceOrder: [UUID] = []
    private let windowTabStates = NSMapTable<NSWindow, WindowTabsState>(keyOptions: .weakMemory, valueOptions: .weakMemory)
    /// 弱引用窗口列表：NSWindow 关闭后必须能释放；windowWillClose 中调用 unregisterWindow
    private let windowList = NSHashTable<NSWindow>.weakObjects()

    func register(_ ws: Workspace) {
        workspaces[ws.id] = ws
        workspaceOrder.append(ws.id)
        if activeWorkspace == nil { activeWorkspace = ws }
    }

    func unregister(_ ws: Workspace) {
        workspaces.removeValue(forKey: ws.id)
        workspaceOrder.removeAll { $0 == ws.id }
        if activeWorkspace === ws {
            activeWorkspace = workspaceOrder.compactMap { workspaces[$0] }.first
        }
    }

    func registerWindow(_ window: NSWindow, tabs: WindowTabsState) {
        windowTabStates.setObject(tabs, forKey: window)
        windowList.add(window)
    }

    func unregisterWindow(_ window: NSWindow) {
        windowTabStates.removeObject(forKey: window)
        windowList.remove(window)
    }

    func tabState(for window: NSWindow?) -> WindowTabsState? {
        guard let w = window else { return nil }
        return windowTabStates.object(forKey: w)
    }

    func tabState(containing workspace: Workspace) -> WindowTabsState? {
        guard let enumerator = windowTabStates.objectEnumerator() else { return nil }
        for case let ts as WindowTabsState in enumerator {
            if ts.tabs.contains(where: { $0.workspace === workspace }) {
                return ts
            }
        }
        return nil
    }

    func workspace(for window: NSWindow?) -> Workspace? {
        tabState(for: window)?.activeWorkspace
    }

    func allWindows() -> [NSWindow] {
        windowList.allObjects.filter { w in
            guard w.contentView != nil else { return false }
            return w.isVisible
        }
    }

    static let debugTargetWindowCount: Int = {
        if let raw = ProcessInfo.processInfo.environment["SEQALIGN_DEBUG_OPEN_N"],
           let n = Int(raw), n > 0 {
            return n
        }
        return 0
    }()

    var active: Workspace? { activeWorkspace }
    var activeAlignment: Alignment? { active?.currentAlignment }
    var allWorkspaces: [Workspace] { workspaceOrder.compactMap { workspaces[$0] } }

    /// 退出时检查脏标签——被保留策略卸载的标签已从 workspaces 中 unregister，
    /// 只检查 allWorkspaces 会漏掉它们，因此此处遍历所有窗口的标签状态，
    /// 收集全部脏工作区（含已从 registry 移除但仍在 tabs 数组中的）。
    var allDirtyWorkspaces: [Workspace] {
        var dirty: [Workspace] = []
        // registry 中已注册的工作区
        dirty.append(contentsOf: allWorkspaces.filter { $0.isDirty })
        // 各窗口标签状态中可能存在的未注册脏工作区（被卸载保留的标签）
        guard let enumerator = windowTabStates.objectEnumerator() else { return dirty }
        for case let ts as WindowTabsState in enumerator {
            for tab in ts.tabs where tab.workspace.isDirty {
                if !dirty.contains(where: { $0 === tab.workspace }) {
                    dirty.append(tab.workspace)
                }
            }
        }
        return dirty
    }

    var activeForAction: Workspace? {
        workspace(for: NSApp.keyWindow) ?? activeWorkspace
    }
}

// MARK: - 菜单命令（本地化 + 语言切换）

struct SeqAlignCommands: Commands {
    @ObservedObject private var registry = WindowRegistry.shared
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = registry.editRevision
        let _ = lang.language  // 语言切换时刷新菜单

        CommandGroup(replacing: .newItem) {
            Button(L.s.menuNewTab) {
                TabManager.shared.newTab()
                NSApp.activate(ignoringOtherApps: true)
            }
                .keyboardShortcut("t")
            Button(L.s.menuNewWindow) { openWindow(id: "seqalign-main") }
                .keyboardShortcut("n")
            Button(L.s.menuOpen) { OpenFileManager.shared.openFile() }
                .keyboardShortcut("o")
            // Cmd+W 关标签、Cmd+Shift+W 关窗口（与 Safari/Chrome 惯例一致）
            Button(L.s.menuCloseTab) { TabManager.shared.closeActiveTab() }
                .keyboardShortcut("w")
            Button(L.s.menuCloseWindow) { NSApp.sendAction(#selector(NSWindow.performClose), to: nil, from: nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Menu(L.s.menuOpenRecent) {
                let recents = RecentFilesManager.shared.list()
                if recents.isEmpty {
                    Text(L.s.menuNoRecent)
                } else {
                    ForEach(recents, id: \.path) { url in
                        Button(url.lastPathComponent) { OpenFileManager.shared.openFile(at: url) }
                            .disabled(!FileManager.default.fileExists(atPath: url.path))
                    }
                }
            }
            Divider()
            Button(L.s.menuSave) { SaveManager.shared.saveCurrent() }
                .keyboardShortcut("s")
            Button(L.s.menuSaveAs) { SaveManager.shared.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button(L.s.exportPreviewTitle) { NotificationCenter.default.post(name: .showExportPreview, object: nil) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button(L.s.menuExportPNG) { ExportCoordinator.shared.exportCurrent(format: .png) }
            Button(L.s.menuExportPDF) { ExportCoordinator.shared.exportCurrent(format: .pdf) }
            Button(L.s.menuExportSVG) { ExportCoordinator.shared.exportCurrent(format: .svg) }
        }

        CommandGroup(replacing: .pasteboard) {
            Button(L.s.menuUndo) { UndoRedoCoordinator.shared.undoCurrent() }
                .keyboardShortcut("z")
                .disabled(!UndoRedoCoordinator.shared.canUndo)
            Button(L.s.menuRedo) { UndoRedoCoordinator.shared.redoCurrent() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!UndoRedoCoordinator.shared.canRedo)
            Divider()
            Button(L.s.menuCut) { CopyPasteRouter.shared.cut() }
                .keyboardShortcut("x")
            Button(L.s.menuCopy) { CopyPasteRouter.shared.copy() }
                .keyboardShortcut("c")
            Button(L.s.menuPaste) { CopyPasteRouter.shared.paste() }
                .keyboardShortcut("v")
            Button(L.s.menuSelectAll) { CopyPasteRouter.shared.selectAll() }
                .keyboardShortcut("a")
            Divider()
            Button(L.s.menuRevComp) { EditActions.shared.reverseComplement() }
                .keyboardShortcut("i")
            Button(L.s.menuInsertGap) { EditActions.shared.insertGap() }
                .keyboardShortcut("d")
            Button(L.s.menuDeleteSeq) { EditActions.shared.removeSelected() }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button(L.s.menuMoveSeq) { EditActions.shared.moveSequence() }
            Button(L.s.menuRenameSeq) { EditActions.shared.renameSequence() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandMenu(L.s.menuView) {
            Button(L.s.schemeMinimal) { ColorSchemeManager.shared.setScheme(.minimal) }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            Button(L.s.schemeClustalX) { ColorSchemeManager.shared.setScheme(.clustalX) }
                .keyboardShortcut("2", modifiers: [.command, .shift])
            Button(L.s.schemeZappo) { ColorSchemeManager.shared.setScheme(.zappo) }
                .keyboardShortcut("3", modifiers: [.command, .shift])
            Button(L.s.schemeSeaView) { ColorSchemeManager.shared.setScheme(.seaView) }
                .keyboardShortcut("4", modifiers: [.command, .shift])
            Button(L.s.schemeDefault) { ColorSchemeManager.shared.setScheme(.defaultNucleotide) }
            Button(L.s.schemeTransitionTransversion) { ColorSchemeManager.shared.setScheme(.transitionTransversion) }
            Button(L.s.schemeOkabeIto) { ColorSchemeManager.shared.setScheme(.okabeIto) }
                .keyboardShortcut("5", modifiers: [.command, .shift])
            Divider()
            Button(L.s.toolbarZoomIn) { ZoomManager.shared.zoomIn() }
                // 美式键盘 ⌘= 不生成 "+" 字符，补 "=" 备用快捷键
                .keyboardShortcut("+")
            Button("") { ZoomManager.shared.zoomIn() }
                .keyboardShortcut("=")
            Button(L.s.toolbarZoomOut) { ZoomManager.shared.zoomOut() }
                .keyboardShortcut("-")
            Button(L.s.toolbarZoomReset) { ZoomManager.shared.reset() }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            Divider()
            Button(L.s.menuToggleConsensus) { ToggleManager.shared.toggleConsensus() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Menu(L.s.menuAppearance) {
                Button(L.s.menuLight) { AppearanceStore.shared.apply(.light) }
                Button(L.s.menuDark) { AppearanceStore.shared.apply(.dark) }
                Button(L.s.menuFollowSystem) { AppearanceStore.shared.apply(.system) }
            }
            Menu(L.s.menuLanguage) {
                Button(L.s.menuChinese) { LanguageManager.shared.set(.zh) }
                Button(L.s.menuEnglish) { LanguageManager.shared.set(.en) }
            }
        }

        CommandMenu(L.s.menuTools) {
            Button(L.s.menuRunAlign) { NotificationCenter.default.post(name: .runAlignment, object: nil) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Button(L.s.menuTranslate) { NotificationCenter.default.post(name: .showTranslate, object: nil) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button(L.s.menuPrimer) { NotificationCenter.default.post(name: .showPrimer, object: nil) }
            Button(L.s.menuQuality) { ToolActions.shared.showQualityReport() }
            Button(L.s.menuSearch) { SearchManager.shared.showSearch() }
                .keyboardShortcut("f")
            Button(L.s.menuFindNext) { SearchManager.shared.findNext() }
                .keyboardShortcut("g")
            Button(L.s.menuFindPrev) { SearchManager.shared.findPrev() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button(L.s.menuCmdPalette) { CommandPalette.shared.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .appSettings) {
            Button(L.s.menuSettings) { SettingsManager.shared.showSettings() }
                .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(replacing: .help) {
            Button(L.s.menuGuide) { HelpManager.shared.showGuide() }
            Button(L.s.menuLoadExample) { HelpManager.shared.loadExample() }
            Button(L.s.menuAbout) { HelpManager.shared.showAbout() }
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceManager.shared.applyCurrent()
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            OpenFileManager.shared.openFile(at: url)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 用 allDirtyWorkspaces 替代 allWorkspaces.filter，
        // 覆盖被保留策略卸载但仍有未保存编辑的标签
        let dirty = WindowRegistry.shared.allDirtyWorkspaces
        guard !dirty.isEmpty else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = L.s.quitTitle
        if dirty.count == 1 {
            let name = dirty[0].currentFileName.isEmpty ? L.s.unnamed : dirty[0].currentFileName
            alert.informativeText = "“\(name)”\(L.s.quitSingleDesc)"
        } else {
            alert.informativeText = "\(dirty.count)\(L.s.quitMultiDesc)"
        }
        alert.addButton(withTitle: L.s.quitSaveExit)
        alert.addButton(withTitle: L.s.unsavedDontSave)
        alert.addButton(withTitle: L.s.cancel)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // 任一文档保存失败或用户在保存面板取消 → 中止退出，避免数据丢失
            if SaveManager.shared.saveAllDirty() {
                return .terminateNow
            }
            return .terminateCancel
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}

// MARK: - 全局管理器

final class OpenFileManager {
    static let shared = OpenFileManager()

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "fasta") ?? .data,
            UTType(filenameExtension: "fa") ?? .data,
            UTType(filenameExtension: "fas") ?? .data,
            UTType(filenameExtension: "fastq") ?? .data,
            UTType(filenameExtension: "fq") ?? .data,
            UTType(filenameExtension: "nexus") ?? .data,
            UTType(filenameExtension: "nex") ?? .data,
            UTType(filenameExtension: "phy") ?? .data,
            UTType(filenameExtension: "phylip") ?? .data,
            UTType(filenameExtension: "aln") ?? .data,
            UTType(filenameExtension: "msf") ?? .data,
            UTType(filenameExtension: "sto") ?? .data,
            UTType(filenameExtension: "stockholm") ?? .data,
            UTType(filenameExtension: "gz") ?? .data,
            .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openFile(at: url)
        }
    }

    func openFile(at url: URL) {
        guard let target = WindowRegistry.shared.activeForAction else {
            // 无窗口时先建窗再加载。WindowGroup 的 openWindow 经菜单命令触发，
            // 这里通过 NSApp.sendAction 间接调用「新建窗口」菜单项。
            NSApp.sendAction(#selector(NSWindow.newWindowForTab), to: nil, from: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.openFile(at: url)
            }
            return
        }
        // 向已修改的标签打开新文件前，复用关窗同款三选一确认，
        // 避免静默丢弃全部未保存编辑。空标签（无比对数据或未脏）直接加载。
        if target.isDirty, target.currentAlignment != nil {
            let alert = NSAlert()
            alert.messageText = L.s.unsavedTitle
            let name = target.currentFileName.isEmpty ? L.s.unnamed : target.currentFileName
            alert.informativeText = "“\(name)”\(L.s.quitSingleDesc)"
            alert.addButton(withTitle: L.s.unsavedSave)
            alert.addButton(withTitle: L.s.unsavedDontSave)
            alert.addButton(withTitle: L.s.cancel)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                // 先保存再加载
                SaveManager.shared.saveCurrent(for: target) { [weak self] success in
                    guard success else { return }
                    self?.actuallyLoadFile(at: url, target: target)
                }
            case .alertSecondButtonReturn:
                actuallyLoadFile(at: url, target: target)
            default:
                break   // 用户取消
            }
        } else {
            actuallyLoadFile(at: url, target: target)
        }
    }

    private func actuallyLoadFile(at url: URL, target: Workspace) {
        // 代次号 + 回写前校验保证只有最新加载生效：否则并发打开相互覆盖、
        // 多文件拖放只留最后一个。
        target.loadGeneration += 1
        let generation = target.loadGeneration
        target.cancelLoading = false
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                target.isLoading = true
                target.loadProgress = 0
            }
            do {
                var data = try Data(contentsOf: url)
                var fileName = url.lastPathComponent
                var wasCompressed = false
                // gzip 支持：.fasta.gz / .sto.gz 等直接打开
                if fileName.lowercased().hasSuffix(".gz"),
                   let decompressed = Gzip.decompress(data) {
                    data = decompressed
                    fileName = String(fileName.dropLast(3))
                    wasCompressed = true
                }
                if target.cancelLoading {
                    // 回写前校验代次——期间已有更新的加载启动时不得动它的状态
                    DispatchQueue.main.async {
                        guard target.loadGeneration == generation else { return }
                        target.isLoading = false
                    }
                    return
                }
                // 格式检测只解码前 64KB，
                // 避免上百 MB 文件在检测阶段就双倍占用内存
                let format = FormatDetector.detect(data.prefix(65_536))
                // 进度回调按增量 ≥1% 节流（解析在单一后台线程执行，局部变量无竞争）。
                // 否则 FASTQ 每条 read 一次主线程 hop + @Published 写入，大文件加载
                // 会被进度更新淹没。解析器内部对齐 FASTA 的行级节流后此处为双保险。
                var lastReported = -1.0
                let alignment = try AlignmentParser.parse(data, format: format) { done, total in
                    guard total > 0 else { return }
                    let fraction = Double(done) / Double(total)
                    guard fraction - lastReported >= 0.01 || fraction >= 1.0 else { return }
                    lastReported = fraction
                    DispatchQueue.main.async {
                        target.loadProgress = fraction
                    }
                }
                if target.cancelLoading {
                    DispatchQueue.main.async {
                        guard target.loadGeneration == generation else { return }
                        target.isLoading = false
                    }
                    return
                }
                DispatchQueue.main.async {
                    guard target.loadGeneration == generation else { return }
                    target.loadAlignment(alignment, fileName: fileName, format: format, sourceURL: url, sourceIsCompressed: wasCompressed)
                    RecentFilesManager.shared.record(url)
                    target.showFirstRunHintIfNeeded()
                }
            } catch {
                DispatchQueue.main.async {
                    // 错误回写同样校验代次——A 加载慢、B 已完成后，
                    // A 的错误不得覆盖状态并关掉 B 的加载指示
                    guard target.loadGeneration == generation else { return }
                    target.errorMessage = error.localizedDescription
                    target.isLoading = false
                }
            }
        }
    }
}

final class RecentFilesManager {
    static let shared = RecentFilesManager()
    private let key = "SeqAlignMac.recentFiles"
    private var cached: [URL] = []

    private init() { load() }

    private func load() {
        cached = (UserDefaults.standard.array(forKey: key) as? [String] ?? []).map { URL(fileURLWithPath: $0) }
    }

    private func save() {
        UserDefaults.standard.set(cached.map { $0.path }, forKey: key)
    }

    func record(_ url: URL) {
        let canonical = url.resolvingSymlinksInPath()
        var list = cached.filter { $0.resolvingSymlinksInPath() != canonical }
        list.insert(url, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        cached = list
        save()
    }

    func list() -> [URL] { cached }
}

final class SaveManager {
    static let shared = SaveManager()

    func saveCurrent(completion: ((Bool) -> Void)? = nil) {
        saveCurrent(for: WindowRegistry.shared.activeForAction, completion: completion)
    }

    /// 显式目标。未保存确认弹窗（属于某标签自己的 Workspace）必须保存"它自己"的文档，
    /// 而非 keyWindow 的活动标签。菜单入口走无参版（=activeForAction）。
    func saveCurrent(for ws: Workspace?, completion: ((Bool) -> Void)? = nil) {
        guard let ws = ws, let align = ws.currentAlignment else {
            completion?(false)
            return
        }
        if let url = ws.sourceURL, ws.currentFormat != .unknown {
            writeInBackground(alignment: align, workspace: ws, url: url,
                              format: ws.currentFormat, updateLocation: false,
                              completion: completion)
        } else {
            saveAs(for: ws, completion: completion)
        }
    }

    func saveAs(completion: ((Bool) -> Void)? = nil) {
        saveAs(for: WindowRegistry.shared.activeForAction, completion: completion)
    }

    func saveAs(for ws: Workspace?, completion: ((Bool) -> Void)? = nil) {
        guard let ws = ws, let align = ws.currentAlignment else {
            completion?(false)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "fasta") ?? .plainText,
            UTType(filenameExtension: "nexus") ?? .plainText,
            UTType(filenameExtension: "phy") ?? .plainText,
            UTType(filenameExtension: "aln") ?? .plainText,
            UTType(filenameExtension: "msf") ?? .plainText,
        ]
        panel.nameFieldStringValue = ws.currentFileName.isEmpty ? "alignment.fasta" : ws.currentFileName

        if panel.runModal() == .OK, let url = panel.url {
            let ext = url.pathExtension.lowercased()
            writeInBackground(alignment: align, workspace: ws, url: url,
                              format: format(for: ext), updateLocation: true,
                              completion: completion)
        } else {
            completion?(false)
        }
    }

    /// 按指定格式另存为（供导出序列子菜单使用）
    func saveAs(format: AlignmentFormat) {
        saveAs(format: format, completion: nil)
    }

    func saveAs(format: AlignmentFormat, completion: ((Bool) -> Void)? = nil) {
        guard let align = WindowRegistry.shared.activeForAction?.currentAlignment,
              let ws = WindowRegistry.shared.activeForAction else {
            completion?(false)
            return
        }
        let panel = NSSavePanel()
        let ext: String
        switch format {
        case .nexus: ext = "nexus"
        case .phylip: ext = "phy"
        case .clustal: ext = "aln"
        case .msf: ext = "msf"
        case .fastq: ext = "fastq"
        case .stockholm: ext = "sto"
        default: ext = "fasta"
        }
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .plainText]
        let baseName = ws.currentFileName.isEmpty ? "alignment" : (ws.currentFileName as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName).\(ext)"

        if panel.runModal() == .OK, let url = panel.url {
            writeInBackground(alignment: align, workspace: ws, url: url,
                              format: format, updateLocation: false,
                              completion: completion)
        } else {
            completion?(false)
        }
    }

    /// 退出时保存全部脏文档。返回 false 表示有文档保存失败或用户在保存面板取消
    /// （退出应中止）。对无 sourceURL 的文档不得直接 continue、写盘错误不得用
    /// try? 吞掉 —— 否则用户明确选择「保存并退出」却可能带着数据丢失退出。
    /// 注：退出路径保持同步（applicationShouldTerminate 需要同步结果且本就是模态流程）；
    /// 主线程后台化针对的是 Cmd+S 高频路径（saveCurrent/saveAs）。
    @discardableResult
    func saveAllDirty() -> Bool {
        var allSaved = true
        // 用 allDirtyWorkspaces 替代 allWorkspaces.filter，覆盖被卸载的脏标签
        for ws in WindowRegistry.shared.allDirtyWorkspaces {
            guard let align = ws.currentAlignment else { continue }
            if let url = ws.sourceURL, ws.currentFormat != .unknown {
                do {
                    var data = dataForFormat(align, format: ws.currentFormat)
                    if ws.sourceIsCompressed {
                        guard let gz = Gzip.compress(data) else { throw NSError(domain: "SeqAlignMac", code: 1) }
                        data = gz
                    }
                    try data.write(to: url)
                    ws.isDirty = false
                } catch {
                    ws.errorMessage = "\(L.s.errorSaveFail)\(error.localizedDescription)"
                    allSaved = false
                }
            } else {
                // 从未保存过的文档：逐个弹保存面板
                if !promptSaveUntitled(ws, alignment: align) {
                    allSaved = false
                }
            }
        }
        return allSaved
    }

    /// 序列化 + 写盘统一后台执行（照抄导出路径范式：后台快照 → 序列化 →
    /// 写盘 → 回主线程回写状态）。Cmd+S 不得在主线程全量序列化 + 写盘，
    /// 否则大比对会让整个 UI 冻结数百 ms 到数秒。
    private func writeInBackground(alignment: Alignment,
                                   workspace ws: Workspace,
                                   url: URL,
                                   format: AlignmentFormat,
                                   updateLocation: Bool,
                                   completion: ((Bool) -> Void)?) {
        ws.isSaving = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let snapshot = alignment.snapshot()
                var data = Self.dataForFormat(snapshot, format: format)
                // gzip 来源原地保存 → 重新压缩，保持合法 .gz 容器
                if ws.sourceIsCompressed {
                    guard let gz = Gzip.compress(data) else {
                        throw NSError(domain: "SeqAlignMac", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "\(L.s.errorSaveFail)gzip"])
                    }
                    data = gz
                }
                try data.write(to: url)
                DispatchQueue.main.async {
                    ws.isSaving = false
                    ws.isDirty = false
                    if updateLocation {
                        ws.sourceURL = url
                        ws.currentFormat = format
                        ws.currentFileName = url.lastPathComponent
                        ws.sourceIsCompressed = false   // 另存为写出的是未压缩文件
                    }
                    ws.showToast("\(L.s.toastSaved) \(url.lastPathComponent)")
                    RecentFilesManager.shared.record(url)
                    completion?(true)
                }
            } catch {
                DispatchQueue.main.async {
                    ws.isSaving = false
                    ws.errorMessage = "\(L.s.errorSaveFail)\(error.localizedDescription)"
                    completion?(false)
                }
            }
        }
    }

    /// 未保存文档的另存面板；用户取消或写盘失败返回 false
    private func promptSaveUntitled(_ ws: Workspace, alignment: Alignment) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "fasta") ?? .plainText,
            UTType(filenameExtension: "nexus") ?? .plainText,
            UTType(filenameExtension: "phy") ?? .plainText,
            UTType(filenameExtension: "aln") ?? .plainText,
            UTType(filenameExtension: "msf") ?? .plainText,
        ]
        panel.nameFieldStringValue = ws.currentFileName.isEmpty ? "alignment.fasta" : ws.currentFileName
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let ext = url.pathExtension.lowercased()
        do {
            try dataForFormat(alignment, format: format(for: ext)).write(to: url)
            ws.sourceURL = url
            ws.currentFormat = format(for: ext)
            ws.currentFileName = url.lastPathComponent
            ws.isDirty = false
            RecentFilesManager.shared.record(url)
            return true
        } catch {
            ws.errorMessage = "\(L.s.errorSaveFail)\(error.localizedDescription)"
            return false
        }
    }

    private static func dataForFormat(_ align: Alignment, format: AlignmentFormat) -> Data {
        switch format {
        case .stockholm: return AlignmentWriter.writeStockholm(align)
        case .nexus: return AlignmentWriter.writeNexus(align)
        case .phylip: return AlignmentWriter.writePhylip(align)
        case .clustal: return AlignmentWriter.writeClustal(align)
        case .msf: return AlignmentWriter.writeMsf(align)
        case .fastq: return AlignmentWriter.writeFastq(align)
        default: return AlignmentWriter.writeFasta(align)
        }
    }

    private func dataForFormat(_ align: Alignment, format: AlignmentFormat) -> Data {
        Self.dataForFormat(align, format: format)
    }

    private func format(for ext: String) -> AlignmentFormat {
        switch ext {
        case "nexus", "nex": return .nexus
        case "phy", "phylip": return .phylip
        case "aln": return .clustal
        case "msf": return .msf
        case "sto", "stockholm": return .stockholm
        case "fastq", "fq": return .fastq
        default: return .fasta
        }
    }
}

final class UndoRedoCoordinator {
    static let shared = UndoRedoCoordinator()

    private var activeManager: UndoRedoManager? {
        WindowRegistry.shared.activeForAction?.undoRedo
    }

    /// 撤销/重做 Toast 的命令描述本地化：核心库 EditCommand 无法访问 App 层 L10n，
    /// 这里按命令类型映射；快照型命令构造时已传入 L.s 文案，直接使用其 description。
    private func localizedDescription(_ command: EditCommand) -> String {
        switch command {
        case let c as CompositeCommand:
            return String(format: L.s.cmdTransaction, c.commands.count)
        case is RenameCommand: return L.s.cmdRenameSeq
        case is RemoveSeqCommand: return L.s.cmdDeleteSeq
        case is ReverseComplementCommand: return L.s.cmdRevComp
        case is InsertGapCommand: return L.s.cmdInsertGap
        case is BatchReplaceCommand: return L.s.cmdBatchReplace
        case is AddSeqCommand: return L.s.cmdAddSeq
        case is MoveSeqCommand: return L.s.cmdMoveSeq
        case is ReplaceAlignmentCommand: return L.s.cmdReplaceAlignment
        default: return command.description
        }
    }

    /// 命令 execute/undo/redo 统一在 Alignment 的锁内执行。
    /// 主线程不得无锁直写 sequences 数组——与后台统计/搜索的锁内遍历并发
    /// 会产生随机崩溃面（EXC_BAD_ACCESS / 数组越界）。NSRecursiveLock 支持命令
    /// 内部再调用同锁 accessor（如 AddSeqCommand → padToMaxLength）。
    /// 同时登记增量列统计所需的脏列信息。
    private func applyWithSideEffects(_ work: (Alignment, UndoRedoManager) -> EditCommand?, descriptionBuilder: (EditCommand) -> String) {
        guard let align = WindowRegistry.shared.activeForAction?.currentAlignment,
              let mgr = activeManager else { return }
        let command: EditCommand? = align.performLocked {
            let c = work(align, mgr)
            if c != nil { align.revision += 1 }   // revision 自增入锁，与快照/统计读取同一临界区
            return c
        }
        guard let command else { return }
        let ws = WindowRegistry.shared.activeForAction
        ws?.objectWillChange.send()
        ws?.showToast(descriptionBuilder(command))
        ws?.isDirty = true
        ws?.registerEditDirtiness(command.dirtyColumns)
        WindowRegistry.shared.editRevision += 1
    }

    func execute(_ command: EditCommand) {
        applyWithSideEffects({ align, mgr in
            mgr.execute(command, on: align)
            return command
        }, descriptionBuilder: { localizedDescription($0) })
    }

    func executeTransaction(_ commands: [EditCommand], description: String) {
        guard !commands.isEmpty else { return }
        applyWithSideEffects({ align, mgr in
            mgr.beginTransaction()
            for cmd in commands { mgr.execute(cmd, on: align) }
            mgr.commitTransaction()
            // 脏列信息由 CompositeCommand.dirtyColumns 汇总（任一未知 → 全量重算）
            return CompositeCommand(commands: commands)
        }, descriptionBuilder: { _ in description })
    }

    func clear() {
        WindowRegistry.shared.activeForAction?.undoRedo.clear()
        WindowRegistry.shared.editRevision += 1
    }

    func undoCurrent() {
        applyWithSideEffects({ align, mgr in
            mgr.undoCommand(on: align)
        }, descriptionBuilder: { "\(L.s.toastUndo) \(localizedDescription($0))" })
    }

    func redoCurrent() {
        applyWithSideEffects({ align, mgr in
            mgr.redoCommand(on: align)
        }, descriptionBuilder: { "\(L.s.toastRedo) \(localizedDescription($0))" })
    }

    var canUndo: Bool {
        guard WindowRegistry.shared.activeForAction?.currentAlignment != nil else { return false }
        return activeManager?.canUndo ?? false
    }

    var canRedo: Bool {
        guard WindowRegistry.shared.activeForAction?.currentAlignment != nil else { return false }
        return activeManager?.canRedo ?? false
    }
}

final class ColorSchemeManager {
    static let shared = ColorSchemeManager()
    func setScheme(_ scheme: ColorScheme) {
        WindowRegistry.shared.activeForAction?.currentScheme = scheme
    }
}

final class ZoomManager {
    static let shared = ZoomManager()

    func zoomIn() {
        guard let ws = WindowRegistry.shared.activeForAction else { return }
        ws.fontSize = min(28, ws.fontSize + 1)
    }
    func zoomOut() {
        guard let ws = WindowRegistry.shared.activeForAction else { return }
        ws.fontSize = max(8, ws.fontSize - 1)
    }
    func reset() {
        WindowRegistry.shared.activeForAction?.fontSize = Workspace.defaultFontSize
    }
}

final class ToggleManager {
    static let shared = ToggleManager()
    func toggleConsensus() {
        WindowRegistry.shared.activeForAction?.showConsensus.toggle()
    }
}

final class SearchManager {
    static let shared = SearchManager()

    func showSearch() { WindowRegistry.shared.activeForAction?.isSearching = true }
    func performSearch() { WindowRegistry.shared.activeForAction?.performSearch() }
    func findNext() { WindowRegistry.shared.activeForAction?.findNext() }
    func findPrev() { WindowRegistry.shared.activeForAction?.findPrev() }
}

final class EditActions {
    static let shared = EditActions()
    private init() {}

    func removeSelected() {
        NotificationCenter.default.post(name: .removeSelectedSeq, object: nil)
    }
    func reverseComplement() {
        NotificationCenter.default.post(name: .reverseComplement, object: nil)
    }
    func insertGap() {
        NotificationCenter.default.post(name: .insertGap, object: nil)
    }
    func renameSequence() {
        NotificationCenter.default.post(name: .renameSeq, object: nil)
    }
    func moveSequence() {
        NotificationCenter.default.post(name: .moveSeq, object: nil)
    }
}

final class ToolActions {
    static let shared = ToolActions()
    private init() {}

    func runAlignment() {
        NotificationCenter.default.post(name: .runAlignment, object: nil)
    }

    func translate() {
        NotificationCenter.default.post(name: .showTranslate, object: nil)
    }

    func showPrimerCalculator() {
        NotificationCenter.default.post(name: .showPrimer, object: nil)
    }

    func showQualityReport() {
        guard WindowRegistry.shared.activeForAction?.currentAlignment != nil else { return }
        NotificationCenter.default.post(name: .showQualityReport, object: nil)
    }
}

final class CopyPasteRouter {
    static let shared = CopyPasteRouter()
    private init() {}

    func copy() {
        if let canvas = firstResponderCanvas() {
            canvas.copySelection(nil)
        } else {
            NSApp.sendAction(#selector(NSText.copy), to: nil, from: nil)
        }
    }

    func cut() {
        // 画布选区有内容时映射为「复制+删除」命令
        if let canvas = firstResponderCanvas(), canvas.selectionRect != nil {
            canvas.copySelection(nil)
            NotificationCenter.default.post(name: .insertGap, object: nil)
        } else {
            NSApp.sendAction(#selector(NSText.cut), to: nil, from: nil)
        }
    }

    func paste() {
        if firstResponderCanvas() != nil {
            NotificationCenter.default.post(name: .pasteFromClipboard, object: nil)
        } else {
            NSApp.sendAction(#selector(NSText.paste), to: nil, from: nil)
        }
    }

    func selectAll() {
        if let canvas = firstResponderCanvas() {
            canvas.selectAllSelection(nil)
        } else {
            NSApp.sendAction(#selector(NSText.selectAll), to: nil, from: nil)
        }
    }

    private func firstResponderCanvas() -> AlignmentCanvasView? {
        var responder: NSResponder? = NSApp.keyWindow?.firstResponder
        while let r = responder {
            if let c = r as? AlignmentCanvasView { return c }
            responder = r.nextResponder
        }
        return nil
    }
}

final class ExportCoordinator {
    static let shared = ExportCoordinator()

    func exportCurrent(format: ExportFormat) {
        guard let ws = WindowRegistry.shared.activeForAction, let align = ws.currentAlignment else { return }
        let scheme = ws.currentScheme

        let panel = NSSavePanel()
        switch format {
        case .png: panel.allowedContentTypes = [.png]
        case .pdf: panel.allowedContentTypes = [.pdf]
        case .svg: panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .plainText]
        }

        let baseName = (ws.currentFileName as NSString).deletingPathExtension
        let ext: String
        switch format {
        case .png: ext = "png"
        case .pdf: ext = "pdf"
        case .svg: ext = "svg"
        }
        let fileName = baseName.isEmpty ? "alignment" : baseName
        panel.nameFieldStringValue = "\(fileName)_alignment.\(ext)"

        let checkbox = NSButton(checkboxWithTitle: L.s.exportOnlySelection, target: nil, action: nil)
        checkbox.state = (ws.currentSelection != nil) ? .on : .off
        let sizeLabel = NSTextField(labelWithString: sizeDescription(align, format: format, fontSize: ws.fontSize))
        sizeLabel.font = NSFont.systemFont(ofSize: 10)
        sizeLabel.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [checkbox, sizeLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 44)
        panel.accessoryView = stack

        if panel.runModal() == .OK, let url = panel.url {
            var options = ExportOptions(format: format,
                                        colorScheme: scheme, dark: NSAppearance.isDarkNow)
            if checkbox.state == .on, let sel = ws.currentSelection {
                options.rowRange = sel.rowStart...sel.rowEnd
                options.colRange = sel.colStart...sel.colEnd
            }
            let savedNameW = UserDefaults.standard.double(forKey: "SeqAlignMac.nameColWidth")
            let nameW = savedNameW > 0 ? CGFloat(savedNameW) : 150
            options.fontSize = ws.fontSize
            options.nameColWidth = nameW
            options.showConsensus = true

            // 大文件导出（含全量渲染 + 可能 GB 级位图编码）放后台执行，
            // 主线程同步渲染会直接 beachball；后台渲染使用快照，避免与编辑竞争
            let wsForToast = ws
            // 导出期间给出进行中反馈
            wsForToast.showToast(L.s.exportingText)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let snapshot = align.snapshot()
                    let data = try ExportManager.exportImage(snapshot, options: options)
                    try data.write(to: url)
                    DispatchQueue.main.async {
                        wsForToast.showToast("\(L.s.toastExported) \(url.lastPathComponent)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        wsForToast.errorMessage = "\(L.s.errorExportFail)\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func sizeDescription(_ align: Alignment, format: ExportFormat, fontSize: CGFloat) -> String {
        let savedNameW = UserDefaults.standard.double(forKey: "SeqAlignMac.nameColWidth")
        let nameWidth = savedNameW > 0 ? CGFloat(savedNameW) : 150
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let cellWidth = max(4, ("A" as NSString).size(withAttributes: [.font: mono]).width)
        let cellHeight = fontSize * 1.4
        let railHeight: CGFloat = 12
        let rulerHeight: CGFloat = 24
        let consensusHeight = cellHeight + 4
        let topBar = railHeight + rulerHeight
        let width = nameWidth + CGFloat(align.length) * cellWidth
        let height = topBar + consensusHeight + CGFloat(align.seqCount) * cellHeight
        switch format {
        case .png:
            let scale = 300.0 / 72.0
            return String(format: "%.0f × %.0f px (300 DPI)", width * scale, height * scale)
        case .pdf, .svg:
            return String(format: "%.0f × %.0f pt", width, height)
        }
    }
}

final class SettingsManager {
    static let shared = SettingsManager()
    func showSettings() {
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }
}

// MARK: - 外观偏好

enum AppearanceMode: String, CaseIterable {
    case system, light, dark
}

final class AppearanceManager {
    static let shared = AppearanceManager()
    static let key = "SeqAlignMac.appearance"

    func current() -> AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "system") ?? .system
    }

    func apply(_ mode: AppearanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: Self.key)
        switch mode {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func applyCurrent() { apply(current()) }
}

final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()
    @Published var mode: AppearanceMode = AppearanceManager.shared.current()

    func apply(_ m: AppearanceMode) {
        AppearanceManager.shared.apply(m)
        mode = m
    }

    var systemImage: String {
        switch mode {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "display"
        }
    }
}

final class CommandPalette {
    static let shared = CommandPalette()
    private init() {}
    func toggle() {
        NotificationCenter.default.post(name: .showCommandPalette, object: nil)
    }
}

final class HelpManager {
    static let shared = HelpManager()

    func showGuide() {
        NotificationCenter.default.post(name: .showGuide, object: nil)
    }

    func loadExample() {
        guard let target = WindowRegistry.shared.activeForAction else { return }
        let exampleFasta = """
        >Homo_sapiens_BRCA1
        ATGGATTTATCTGCTCTTCGCGTTGAAGAAGTACAAAATGTCATTAATGAG
        >Pan_troglodytes_BRCA1
        ATGGATTTATCTGCTCTTCGCGTTGAAGAAGTACAAAATGTCATTAATGAA
        >Mus_musculus_Brca1
        ATGGATTTATCTGCTCTTCGCGTTGAAGAAGTACAAAATGTCATTAATGAG
        >Rattus_norvegicus_Brca1
        ATGGATTTATCTGCTCTTCGCGTTGAAGAAGTACAAAATGTCATTAATGAA
        """
        let data = exampleFasta.data(using: .utf8) ?? Data()
        do {
            let alignment = try AlignmentParser.parse(data, format: .fasta)
            DispatchQueue.main.async {
                target.loadAlignment(alignment, fileName: "example.fasta", format: .fasta)
                target.showFirstRunHintIfNeeded()
            }
        } catch {
            print("Load example failed: \(error)")
        }
    }

    func showAbout() {
        NotificationCenter.default.post(name: .showAbout, object: nil)
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let removeSelectedSeq = Notification.Name("removeSelectedSeq")
    static let reverseComplement = Notification.Name("reverseComplement")
    static let insertGap = Notification.Name("insertGap")
    static let renameSeq = Notification.Name("renameSeq")
    static let moveSeq = Notification.Name("moveSeq")
    static let runAlignment = Notification.Name("runAlignment")
    static let showPrimer = Notification.Name("showPrimer")
    static let showSettings = Notification.Name("showSettings")
    static let showTranslate = Notification.Name("showTranslate")
    static let showAbout = Notification.Name("showAbout")
    static let showGuide = Notification.Name("showGuide")
    static let showQualityReport = Notification.Name("showQualityReport")
    static let showCommandPalette = Notification.Name("showCommandPalette")
    static let showExportPreview = Notification.Name("showExportPreview")
    static let pasteFromClipboard = Notification.Name("pasteFromClipboard")
    static let tabStateChanged = Notification.Name("tabStateChanged")
    static let tabDataChanged = Notification.Name("tabDataChanged")
    static let lastTabClosed = Notification.Name("lastTabClosed")
    // languageChanged is declared in Localization.swift
}

// MARK: - Workspace 扩展（首次运行引导）

extension Workspace {
    func showFirstRunHintIfNeeded() {
        let key = "SeqAlignMac.firstRunHintShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showToast(L.s.toastFirstRun)
        }
    }
}
