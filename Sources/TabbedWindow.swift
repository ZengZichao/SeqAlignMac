//  TabbedWindow.swift
//  SeqAlignMac — 窗口内多标签页（三栏布局 + 悬浮标签页重构）
//
//  设计要点：
//  - 标签页改为悬浮式：完整四角圆角矩形卡片，嵌入标题栏横带（Edge 式高标签）
//  - 标签条经 setupWindow 以 NSTitlebarAccessoryViewController(.left) 嵌入标题栏，
//    紧跟红绿灯右侧，与红绿灯同高平齐
//  - 标签 tooltip 使用 SwiftUI .help()（原生）
//  - 工具栏移至左侧栏（ContentView 三栏布局），窗口顶部仅保留标签条

import AppKit
import SwiftUI

// MARK: - 标签页模型

/// 单个标签：ID + 独立 Workspace（数据 / 撤销栈 / 搜索状态全部随标签隔离）
struct WorkspaceTab: Identifiable {
    let id = UUID()
    let workspace: Workspace

    init() {
        self.workspace = Workspace()
    }
}

// MARK: - 窗口级标签状态

/// 每个窗口一份：管理本窗口的标签列表与活动标签。
/// 由 WindowRootView 以 @StateObject 持有，标签条 / 菜单命令通过它操作。
final class WindowTabsState: ObservableObject {
    @Published var tabs: [WorkspaceTab] = []
    @Published var activeTabID: UUID?

    /// 待关闭标签（脏确认流程中暂存，确认完成后回跳）
    var pendingCloseTabID: UUID?

    /// 活动标签的 Workspace（命令路由目标）
    var activeWorkspace: Workspace? {
        guard let id = activeTabID else { return nil }
        return tabs.first { $0.id == id }?.workspace
    }

    /// 新建标签并激活
    @discardableResult
    func addTab() -> WorkspaceTab {
        let tab = WorkspaceTab()
        tabs.append(tab)
        activate(tab.id)
        return tab
    }

    /// 切换活动标签
    func activate(_ id: UUID) {
        guard activeTabID != id, tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        if let ws = activeWorkspace {
            WindowRegistry.shared.activeWorkspace = ws
        }
        NotificationCenter.default.post(name: .tabStateChanged, object: nil)
    }

    /// 关闭标签入口：脏标签先弹确认，干净标签直接关
    func closeTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if tab.workspace.isDirty {
            // 先激活该标签，确保其视图树被保留、未保存弹窗可呈现，
            // 并让确认弹窗归属与 activeForAction 一致（配合显式目标）。
            activate(id)
            pendingCloseTabID = id
            tab.workspace.pendingCloseRequest = true
            tab.workspace.pendingCloseIsTab = true
        } else {
            closeTabNow(id)
        }
    }

    /// 确认后真正关闭标签
    func closeTabNow(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: idx)
        let wasActive = removed.id == activeTabID
        if wasActive {
            if tabs.isEmpty {
                // object 携带本窗口的 tabState：接收方据此过滤，
                // object: nil 会让其它窗口误执行 performClose
                NotificationCenter.default.post(name: .lastTabClosed, object: self)
            } else {
                activate(tabs[min(idx, tabs.count - 1)].id)
            }
        } else {
            NotificationCenter.default.post(name: .tabStateChanged, object: nil)
        }
        WindowRegistry.shared.unregister(removed.workspace)
    }

    /// 窗口标题 / 标签条数据变化时由上层触发的统一刷新
    func notifyDataChanged() {
        NotificationCenter.default.post(name: .tabDataChanged, object: nil)
    }
}

// MARK: - 窗口根视图（一窗口多标签 + 悬浮标签条 + 三栏布局）

struct WindowRootView: View {
    @StateObject private var tabState = WindowTabsState()
    @State private var windowRef: NSWindow?
    @State private var didSetupWindow = false
    @State private var delegateHandler: WindowDelegateHandler?
    // 保留最近活跃的 N 个标签的完整视图树，其余标签以轻量占位符渲染——
    // 大比对多标签的内存由 O(所有标签) 线性叠加降为 O(N)；
    // 切回被卸载的标签时视图重建（数据仍在 workspace 中，不丢失）
    @State private var recentlyActiveIDs: [UUID] = []
    private static let retainedTabs = 3

    var body: some View {
        VStack(spacing: 0) {
            // 标签内容区（多标签 ZStack 叠加，仅活动标签可见）
            // 标签条不再放在内容区顶部，而是经 setupWindow 以 NSTitlebarAccessoryViewController
            // 嵌入标题栏横带（紧跟红绿灯右侧），与红绿灯同高平齐
            ZStack {
                ForEach(tabState.tabs) { tab in
                    if isRetained(tab) {
                        ContentView(workspace: tab.workspace)
                            .opacity(tab.id == tabState.activeTabID ? 1 : 0)
                            .allowsHitTesting(tab.id == tabState.activeTabID)
                            .accessibilityHidden(tab.id != tabState.activeTabID)
                            .id(tab.id)
                    } else {
                        // 非保留标签的轻量占位符（不参与 body 重算、不持有画布树）
                        Color.clear
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .background(WindowSetupView { window in
            guard let w = window else { return }
            windowRef = w
            guard !didSetupWindow else { return }
            didSetupWindow = true
            setupWindow(w)
        })
        .onAppear {
            if tabState.tabs.isEmpty {
                tabState.addTab()
            }
            if let id = tabState.activeTabID, !recentlyActiveIDs.contains(id) {
                recentlyActiveIDs.insert(id, at: 0)
            }
        }
        .onChange(of: tabState.activeTabID) { _, newID in
            guard let id = newID else { return }
            recentlyActiveIDs.removeAll { $0 == id }
            recentlyActiveIDs.insert(id, at: 0)
            if recentlyActiveIDs.count > Self.retainedTabs {
                recentlyActiveIDs.removeLast(recentlyActiveIDs.count - Self.retainedTabs)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lastTabClosed)) { note in
            // 只响应本窗口最后一个标签关闭；其它窗口的广播被忽略
            guard (note.object as? WindowTabsState) === tabState else { return }
            windowRef?.performClose(nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabDataChanged)) { _ in
            updateWindowTitle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabStateChanged)) { _ in
            updateWindowTitle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            updateWindowTitle()
        }
    }

    /// 活动标签 + 最近活跃 N-1 个标签保留完整视图树；
    /// 有待确认关闭请求的标签必须保留，否则其未保存确认弹窗无处呈现、卡死。
    private func isRetained(_ tab: WorkspaceTab) -> Bool {
        tab.id == tabState.activeTabID
            || recentlyActiveIDs.contains(tab.id)
            || tab.workspace.pendingCloseRequest
    }

    /// 一次性窗口装配：透明标题栏 + fullSizeContentView + 窗口 delegate + 注册。
    /// 标签条经 NSTitlebarAccessoryViewController(.left) 嵌入标题栏横带。
    private func setupWindow(_ w: NSWindow) {
        w.tabbingMode = .disallowed
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.styleMask.insert(.fullSizeContentView)

        // 窗口背景色
        w.backgroundColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return Minimal.controlSurface(dark: isDark)
        }

        WindowRegistry.shared.registerWindow(w, tabs: tabState)

        // 标签条嵌入标题栏：NSTitlebarAccessoryViewController(.left) 紧跟红绿灯右侧，
        // 与红绿灯同一水平线。SwiftUI 内容由 NSHostingView 承载。
        // 宿主视图宽度跟随窗口宽度（窗口缩放时由 delegate 同步），
        // 标签从红绿灯右侧排起，「+」按钮紧跟最后一个标签，随标签增多不断右移。
        let tabBar = FloatingTabBar(tabState: tabState)
        let hosting = NSHostingView(rootView: tabBar)
        // 36pt：高于标准标题栏时 AppKit 自动撑高标题栏（Edge 浏览器式高标签）
        // 初始宽度在布局未完成时可能取到 0，用安全回退值并
        // 在 windowDidResize 中同步宽度（见 WindowDelegateHandler）
        let hostWidth = max(640, w.contentView?.frame.width ?? 640)
        hosting.frame = NSRect(x: 0, y: 0, width: hostWidth, height: 36)
        hosting.autoresizingMask = [.width]
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = hosting
        accessory.layoutAttribute = .left
        w.addTitlebarAccessoryViewController(accessory)

        let handler = WindowDelegateHandler(tabState: tabState)
        handler.tabBarHost = hosting
        w.delegate = handler
        delegateHandler = handler
    }

    /// 动态窗口标题
    private func updateWindowTitle() {
        guard let w = windowRef else { return }
        let name = tabState.activeWorkspace?.currentFileName ?? ""
        let prefix = L.s.windowTitlePrefix
        w.title = name.isEmpty ? L.s.windowTitleUnnamed : "\(prefix) — \(name)"
        w.isDocumentEdited = tabState.activeWorkspace?.isDirty ?? false
    }
}

// MARK: - 悬浮标签条（SwiftUI 原生视图，嵌入标题栏 accessory）

/// 悬浮式标签条：完整圆角矩形标签 + + 按钮，嵌入标题栏横带（Edge 式）。
/// 标签等宽：按标题栏可见宽度均分，标签增多时自动收窄，「+」按钮永不被顶出。
struct FloatingTabBar: View {
    @ObservedObject var tabState: WindowTabsState

    var body: some View {
        // 140 = 红绿灯区域(≈78) + 「+」按钮(32) + 尾部留白(8) + 冗余(22)
        GeometryReader { geo in
            let count = max(1, tabState.tabs.count)
            let usable = geo.size.width - 140
            let tabW = min(220 as CGFloat, max(44, (usable - 4 * CGFloat(count)) / CGFloat(count)))
            HStack(spacing: 4) {
                ForEach(tabState.tabs) { tab in
                    FloatingTabItem(
                        tabState: tabState,
                        tab: tab,
                        width: tabW
                    )
                }

                // + 新建标签按钮：热区为整个按钮面（32×28）
                Button(action: { tabState.addTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: Minimal.fontSM, weight: .medium))
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                                .fill(Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(L.s.tooltipNewTab)
                .accessibilityLabel(L.s.tooltipNewTab)
            }
            .padding(.leading, 0)   // 紧贴红绿灯左对齐（titlebar accessory 已定位在其右侧）
            .padding(.trailing, Minimal.space2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 单个悬浮标签页

struct FloatingTabItem: View {
    @ObservedObject var tabState: WindowTabsState
    let tab: WorkspaceTab
    var width: CGFloat = 220
    @State private var hovered = false
    /// 工作区变化（文件加载/重命名/脏标记）时触发本视图重算标题：
    /// tabState 不随 workspace 的 @Published 变化通知，标签标题会一直显示「未命名」
    @State private var workspaceTick = 0

    private var isActive: Bool { tab.id == tabState.activeTabID }
    private var title: String {
        _ = workspaceTick
        let name = tab.workspace.currentFileName
        let base = name.isEmpty ? L.s.unnamed : name
        // 脏标签前加「•」标记，让用户区分哪个标签有未保存修改
        return tab.workspace.isDirty ? "• \(base)" : base
    }
    private var dark: Bool { isDarkAppearance }

    var body: some View {
        HStack(spacing: Minimal.space2 - Minimal.space1) {
            // 文本标签居左
            Text(title)
                .font(.system(size: Minimal.fontSM, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(Color(isActive
                    ? Minimal.text(dark: dark)
                    : Minimal.textMuted(dark: dark)))

            Spacer(minLength: 0)

            // 关闭叉号固定在标签右端（激活或悬停时显示）
                if isActive || hovered {
                Button(action: { tabState.closeTab(tab.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: Minimal.fontXXS - 1, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: Minimal.radiusXS, style: .continuous)
                                .fill(hovered ? Color(Minimal.border(dark: dark)) : Color.clear)
                        )
                        .foregroundColor(Color(Minimal.textMuted(dark: dark)))
                }
                .buttonStyle(.plain)
                .help(L.s.tooltipCloseTab)
                .accessibilityLabel(L.s.tooltipCloseTab)
            }
        }
        .padding(.horizontal, Minimal.space2 + Minimal.space1)
        .frame(height: Minimal.controlH)   // 28pt 标签，在 36pt 标题栏横带内居中（Edge 式高标签）
        .frame(width: width)               // Edge 式等宽标签：随标签数增多自动收窄，长名称中间省略
        .background(
            RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .fill(isActive
                    ? Color(Minimal.surface(dark: dark))
                    : (hovered ? Color(Minimal.card(dark: dark)) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .stroke(isActive
                    ? Color(Minimal.border(dark: dark))
                    : Color.clear,   // hover 仅填充，无边框
                    lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hovered = hovering
        }
        .onReceive(tab.workspace.objectWillChange) { _ in
            workspaceTick += 1
        }
        .onTapGesture {
            tabState.activate(tab.id)
        }
        .contextMenu {
            Button(L.s.tooltipCloseTab) { tabState.closeTab(tab.id) }
        }
    }
}

// MARK: - 窗口装配视图（NSViewRepresentable，捕获 NSWindow）

struct WindowSetupView: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = WindowSetupCaptureView()
        v.onWindow = onWindow
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class WindowSetupCaptureView: NSView {
    var onWindow: ((NSWindow?) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindow?(window)
    }
}

// MARK: - 窗口 delegate（活动标签脏守卫 + keyWindow 路由）

final class WindowDelegateHandler: NSObject, NSWindowDelegate {
    let tabState: WindowTabsState
    /// 标题栏标签条宿主视图：窗口宽度变化时同步其宽度，使标签条可铺满整个标题栏
    weak var tabBarHost: NSView?

    init(tabState: WindowTabsState) {
        self.tabState = tabState
        super.init()
    }

    func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, let host = tabBarHost else { return }
        let newWidth = w.contentView?.frame.width ?? host.frame.width
        if abs(host.frame.width - newWidth) > 0.5 {
            host.frame.size.width = newWidth
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let ws = tabState.activeWorkspace, ws.isDirty {
            ws.pendingCloseRequest = true
            ws.pendingCloseIsTab = false
            return false
        }
        // 只校验活动标签会让其余脏标签的未保存修改在关窗时静默丢失。
        // 切换到第一个脏标签走既有的确认流程，让用户看到是哪份文档需要保存。
        if let dirty = tabState.tabs.first(where: { $0.workspace.isDirty }) {
            tabState.activate(dirty.id)
            dirty.workspace.pendingCloseRequest = true
            dirty.workspace.pendingCloseIsTab = false
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // 反注册窗口：不调用 unregisterWindow 时 windowList 强引用链
        // 会导致关闭的窗口及其全部 Workspace/Alignment 永不释放
        if let w = notification.object as? NSWindow {
            WindowRegistry.shared.unregisterWindow(w)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let ws = tabState.activeWorkspace {
            WindowRegistry.shared.activeWorkspace = ws
        }
    }
}

// MARK: - 标签命令路由（菜单 / 快捷键）

final class TabManager {
    static let shared = TabManager()
    private init() {}

    func newTab() {
        guard let ts = WindowRegistry.shared.tabState(for: NSApp.keyWindow) else { return }
        ts.addTab()
    }

    func closeActiveTab() {
        guard let ts = WindowRegistry.shared.tabState(for: NSApp.keyWindow),
              let id = ts.activeTabID else { return }
        ts.closeTab(id)
    }
}
