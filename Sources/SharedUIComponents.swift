//  SharedUIComponents.swift
//  SeqAlignMac — 共享 UI 组件（从 ContentView.swift 拆分）
//
//  包含：全局外观辅助、侧栏按钮、画布包装、空状态视图、
//  待载入数据通道、主题/语言切换。
//  面板分隔条 → PanelResizer.swift

import AppKit
import SwiftUI

// MARK: - 全局外观辅助

/// 系统深浅色切换的 SwiftUI 失效机制。
/// `isDarkAppearance` 在 body 求值时读取 AppKit 全局状态，SwiftUI 对它没有任何
/// 依赖跟踪；应用处于「跟随系统」时，用户在系统设置切深浅色，SwiftUI 树能否
/// 整体重算没有保证。本修饰符挂一个观察 NSView（viewDidChangeEffectiveAppearance
/// 与 PanelResizer 同一机制），系统外观变化时触发所在视图树重算。
struct AppearanceObservingModifier: ViewModifier {
    @State private var tick = 0
    func body(content: Content) -> some View {
        content
            .background(AppearanceObservingRepresentable(onChange: { tick += 1 }).frame(width: 0, height: 0))
    }
}

/// NSViewRepresentable 包装：NSView 不能直接作为 SwiftUI 子视图
struct AppearanceObservingRepresentable: NSViewRepresentable {
    let onChange: () -> Void
    func makeNSView(context: Context) -> NSView { AppearanceObservingView(onChange: onChange) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 零尺寸视图：仅作为 effectiveAppearance 变化的信号源
final class AppearanceObservingView: NSView {
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onChange()
    }
}

extension View {
    var isDarkAppearance: Bool { NSAppearance.isDarkNow }

    /// 跟随系统外观变化触发本视图重算（凡在 body 中读取
    /// NSApp.effectiveAppearance / isDarkAppearance 的视图树根都应挂接）
    func observingAppearanceChanges() -> some View {
        modifier(AppearanceObservingModifier())
    }

    func minimalSheetContainer() -> some View {
        let dark = NSAppearance.isDarkNow
        return self
            .background(RoundedRectangle(cornerRadius: Minimal.radiusMD)
                .fill(Color(Minimal.surface(dark: dark))))
            .overlay(RoundedRectangle(cornerRadius: Minimal.radiusMD)
                .stroke(Color(Minimal.border(dark: dark)), lineWidth: 1))
            // 多层阴影改用 Minimal.shadowLG() 令牌
            .shadow(color: Color(Minimal.shadowLG()[0].color), radius: Minimal.shadowLG()[0].radius, x: 0, y: Minimal.shadowLG()[0].offset.height)
            .shadow(color: Color(Minimal.shadowLG()[1].color), radius: Minimal.shadowLG()[1].radius, x: 0, y: Minimal.shadowLG()[1].offset.height)
            // 弹窗内 NSScrollView 一并应用细滚动条
            .thinScrollbars()
            // 弹窗根挂接系统外观变化监听
            .observingAppearanceChanges()
    }
}

// MARK: - 侧栏按钮（图标 + 文字，水平排列）

struct SidebarButton: View {
    let title: String
    let systemImage: String
    var isActive: Bool = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: Minimal.fontXS, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: Minimal.fontSM, weight: isActive ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(height: Minimal.controlH)
            .padding(.horizontal, Minimal.space2)
            // hover 仅填充，无边框；激活态用更深填充 + 主色文字
            .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .fill(isActive && isEnabled
                      ? Color(Minimal.accentSoft(dark: isDarkAppearance))
                      : (hovered && isEnabled ? Color(Minimal.card(dark: isDarkAppearance)) : Color.clear)))
            .contentShape(Rectangle())
        }
        // 按压态（主题已有 MinimalButtonStyle：侧栏按钮 hover 有反馈、按下无反馈）
        .buttonStyle(MinimalButtonStyle())
        .foregroundColor(Color(isActive
            ? Minimal.primary(dark: isDarkAppearance)
            : Minimal.text(dark: isDarkAppearance)))
        .opacity(isEnabled ? 1 : Minimal.disabledOpacity)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 侧栏下拉按钮（NSMenu.popUp 实现，与 SidebarButton 像素级对齐）

/// NSMenuButton（SwiftUI Menu）自带内边距，label 与普通侧栏按钮永远错位几像素。
/// 本组件外观与 SidebarButton 完全一致，点击时用 NSMenu.popUp 在光标处弹出菜单。
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

enum SidebarMenuEntry {
    case item(String, () -> Void)
    case divider
}

struct SidebarMenuButton: View {
    let title: String
    let systemImage: String
    var showChevron: Bool = true
    var entries: [SidebarMenuEntry]
    var isDisabled: Bool = false
    /// 弹出菜单定位/勾选当前项（如配色菜单高亮当前方案），nil = 无当前项
    var currentItemIndex: Int? = nil
    @State private var hovered = false

    var body: some View {
        Button(action: popup) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: Minimal.fontXS, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: Minimal.fontSM, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if showChevron {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: Minimal.fontXXS))
                        .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                }
            }
            .frame(height: Minimal.controlH)
            .padding(.horizontal, Minimal.space2)
            .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .fill(hovered && !isDisabled ? Color(Minimal.card(dark: isDarkAppearance)) : Color.clear))
            .contentShape(Rectangle())
        }
        // 补按压态
        .buttonStyle(MinimalButtonStyle())
        .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
        .opacity(isDisabled ? Minimal.disabledOpacity : 1)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
    }

    private func popup() {
        guard !isDisabled else { return }
        let menu = NSMenu()
        var currentItem: NSMenuItem? = nil
        for (index, entry) in entries.enumerated() {
            switch entry {
            case .item(let title, let action):
                let item = ClosureMenuItem(title: title, handler: action)
                menu.addItem(item)
                if index == currentItemIndex {
                    item.state = .on   // 当前项勾选态
                    currentItem = item
                }
            case .divider:
                menu.addItem(.separator())
            }
        }
        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: currentItem, at: NSPoint(x: loc.x, y: loc.y - 6), in: nil)
    }
}

/// 侧栏纯图标按钮
// SidebarIconButton 全工程零调用，已删除（连同 WidthPreferenceKey）

// MARK: - 细滚动条（窄轨道 + 浅色 knob）

/// 自定义细滚动条：不绘制轨道背景，在 draw(_:) 中直接绘制 knob。
/// overlay 模式下系统通过 draw(_:) 调用绘制，drawKnob() 仅作后备。
final class ThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    /// true = 本滚动条整条不绘制、不参与命中（左栏用，见 thinScrollbars(suppressedSidebarWidth:)）
    var isSuppressed = false

    /// overlay 模式下系统调用此方法绘制整个 scroller 区域。
    /// 之前为空实现导致 knob 也不被绘制 → 滚动条不可见。
    /// 现在在此处直接绘制 knob，确保滚动条始终可见。
    override func draw(_ dirtyRect: NSRect) {
        guard !isSuppressed else { return }
        // 不绘制轨道背景（保持透明）
        drawKnob()
    }

    override func drawKnob() {
        // 颜色走 Minimal 令牌
        let dark = NSAppearance.isDarkNow
        let alpha: Double = (hitPart != .knob && hitPart != .knobSlot) ? 0.35 : 0.55
        let base = Minimal.textMuted(dark: dark)
        let knobColor = base.withAlphaComponent(alpha)
        // 使用系统提供的 knob rect
        let knobRect = rect(for: .knob)
        // 跳过无效 knob rect（内容不足以滚动时系统返回 empty）
        guard knobRect.width > 0, knobRect.height > 0 else { return }
        var rect = knobRect
        if rect.height >= rect.width {
            // 垂直：收窄宽度到 6pt 居中
            let w: CGFloat = 6
            rect.origin.x = knobRect.midX - w / 2
            rect.size.width = w
            rect.origin.y += 1
            rect.size.height -= 2
        } else {
            // 水平：收窄高度到 6pt 居中
            let h: CGFloat = 6
            rect.origin.y = knobRect.midY - h / 2
            rect.size.height = h
            rect.origin.x += 1
            rect.size.width -= 2
        }
        let radius = min(rect.width, rect.height) / 2
        knobColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}

// MARK: - SwiftUI ScrollView 细滚动条辅助

/// 在 SwiftUI ScrollView 底层查找 NSScrollView 并应用细滚动条样式
struct ThinScrollerModifier: NSViewRepresentable {
    /// 宽度匹配的 ScrollView（左栏）整体抑制滚动条绘制，其余照常
    var suppressedSidebarWidth: CGFloat? = nil

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let v = view, let window = v.window, let cv = window.contentView else { return }
            Self.applyToAllScrollViews(in: cv, suppressedWidth: suppressedSidebarWidth)
            // 兜底补跑：首帧布局未定时侧栏 frame 宽度可能还是 0、宽度匹配不上，
            // 布局稳定后再执行一遍（configureScrollView 幂等，重复执行无副作用）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak view] in
                guard let v = view, let window = v.window, let cv = window.contentView else { return }
                Self.applyToAllScrollViews(in: cv, suppressedWidth: suppressedSidebarWidth)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    static func applyToAllScrollViews(in view: NSView, suppressedWidth: CGFloat? = nil) {
        if let sv = view as? NSScrollView {
            // 主画布跳过：AlignmentCanvasRepresentable 已配置为 legacy 常驻细滚动条
            // （overlay 转瞬即逝，长序列无法拖动横条浏览），而 configureScrollView
            // 会把 scrollerStyle 强制改回 overlay，覆盖画布自己的常驻配置。
            if !(sv.documentView is AlignmentCanvasView) {
                configureScrollView(sv)
                if let w = suppressedWidth, abs(sv.frame.width - w) < 0.5 {
                    // 左栏：常驻滑块紧邻左右分界线、长度只占可视比例，视觉上像断掉的
                    // 半截分隔线，故抑制绘制（滚轮滚动不受影响）。
                    // 注意不可设 scroller.isHidden——那会让 NSScrollView 弃用
                    // ThinScroller 换回系统滚动条，反而重新画出半截线
                    (sv.verticalScroller as? ThinScroller)?.isSuppressed = true
                    (sv.horizontalScroller as? ThinScroller)?.isSuppressed = true
                }
            }
        }
        for sub in view.subviews {
            applyToAllScrollViews(in: sub, suppressedWidth: suppressedWidth)
        }
    }

    /// 调试自检（SEQALIGN_SELFTEST=1 时由 ContentView.onAppear 触发）：
    /// 打印窗口内各 NSScrollView 的宽度与抑制状态，验证左栏抑制是否生效
    static func selfTestSidebarSuppression(expectedWidth: CGFloat) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
              let cv = window.contentView else {
            NSLog("SELFTEST: no visible window")
            return
        }
        func walk(_ v: NSView) {
            if let sv = v as? NSScrollView {
                let vsc = sv.verticalScroller as? ThinScroller
                NSLog("SELFTEST: sv width=%.1f (expect %.1f) suppressed=%@ scroller=%@",
                      sv.frame.width, expectedWidth,
                      vsc?.isSuppressed.description ?? "nil",
                      sv.verticalScroller.map { "\(type(of: $0))" } ?? "nil")
            }
            for s in v.subviews { walk(s) }
        }
        walk(cv)
    }

    static func configureScrollView(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        // 不自动隐藏滚动条：确保滚动条始终可见可拖拽
        scrollView.autohidesScrollers = false
        // 替换系统默认 scroller 为 ThinScroller
        if !(scrollView.verticalScroller is ThinScroller) {
            let thin = ThinScroller()
            scrollView.verticalScroller = thin
        }
        if !(scrollView.horizontalScroller is ThinScroller) {
            let thin = ThinScroller()
            scrollView.horizontalScroller = thin
        }
    }
}

extension View {
    /// 为 SwiftUI ScrollView 应用细滚动条样式（延迟查找窗口内所有 NSScrollView）
    func thinScrollbars() -> some View {
        thinScrollbars(suppressedSidebarWidth: nil)
    }

    /// 同上，且宽度为 `suppressedSidebarWidth` 的 ScrollView 滚动条整体不绘制
    /// （ContentView 根部调用，传入左栏宽度；每个标签重挂载时都会重新执行一遍）
    func thinScrollbars(suppressedSidebarWidth: CGFloat?) -> some View {
        background(ThinScrollerModifier(suppressedSidebarWidth: suppressedSidebarWidth)
            .frame(width: 0, height: 0))
    }
}

// MARK: - 画布 NSView 包装

struct AlignmentCanvasRepresentable: NSViewRepresentable {
    let alignment: Alignment?
    let colorScheme: ColorScheme
    let showConsensus: Bool
    let fontSize: CGFloat
    let highContrast: Bool
    let focusDimMode: Bool
    var differenceReferenceRow: Int? = nil
    let searchHits: [SearchHit]
    let currentHitIndex: Int
    /// 编辑命令上报的脏列信息提供者（updateNSView 内取走，避免 body 求值副作用）
    var dirtyColumnsProvider: (() -> Set<Int>?)? = nil
    let onPositionChanged: (Int, Int) -> Void
    var onFontSizeChanged: ((CGFloat) -> Void)? = nil
    var onRenameRequest: ((Int) -> Void)? = nil
    var onDeleteRequest: ((Int) -> Void)? = nil
    var onMoveRequest: ((Int, Int) -> Void)? = nil
    var onContextAction: ((ContextAction) -> Void)? = nil
    var onCopied: ((String, ToastKind) -> Void)? = nil
    var onSelectionChanged: ((SelectionRange?) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let canvas = AlignmentCanvasView(frame: .zero)
        canvas.onPositionChanged = onPositionChanged
        canvas.onFontSizeChanged = onFontSizeChanged
        canvas.onRenameRequest = onRenameRequest
        canvas.onDeleteRequest = onDeleteRequest
        canvas.onMoveRequest = onMoveRequest
        canvas.onContextAction = onContextAction
        canvas.onCopied = onCopied
        canvas.onSelectionChanged = onSelectionChanged
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        // 不自动隐藏滚动条：确保用户始终可以看到并拖动滚动条浏览全部序列
        scrollView.autohidesScrollers = false
        scrollView.backgroundColor = Minimal.surface(dark: NSAppearance.isDarkNow)
        scrollView.drawsBackground = true
        // 细滚动条：替换系统默认粗滚动条为自定义 ThinScroller
        if let vScroller = scrollView.verticalScroller {
            let thin = ThinScroller(frame: vScroller.bounds)
            thin.autoresizingMask = vScroller.autoresizingMask
            scrollView.verticalScroller = thin
        }
        if let hScroller = scrollView.horizontalScroller {
            let thin = ThinScroller(frame: hScroller.bounds)
            thin.autoresizingMask = hScroller.autoresizingMask
            scrollView.horizontalScroller = thin
        }
        // 常驻滚动条（否则打开长序列后底部看不到、无法拖动横向滚动条）：
        // overlay 样式滚动条只在滚动手势期间浮现、随即淡出，静止时既不可见也不可抓取，
        // 长比对必须随时能抓住横条向右拖。legacy 样式配合 autohidesScrollers=false
        // 让横/纵细滚动条常驻（ThinScroller 只画 6pt knob，无轨道底，视觉仍极简）。
        scrollView.scrollerStyle = .legacy
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let canvas = scrollView.documentView as? AlignmentCanvasView else { return }
        let c = context.coordinator
        // 差异化更新：仅属性真正变化时写回并触发重绘。
        // 无条件 needsDisplay + updateContentSize 会让光标移动/拖选的每个
        // 事件都经 SwiftUI 回流引发一次全可见区重绘，叠加列一致度全量重算后
        // 大文件拖选必然卡顿。
        if c.lastAlignment !== alignment {
            canvas.alignment = alignment
            c.lastAlignment = alignment
            c.lastRevision = alignment?.revision ?? 0
            canvas.needsDisplay = true
            canvas.updateContentSize()
        } else if let align = alignment, c.lastRevision != align.revision {
            // 编辑命令原地修改同一 Alignment 实例（revision 自增），
            // 若不检测 revision 变化，插 gap/粘贴/删序列后画布不重绘、
            // 内容尺寸不更新。revision 变化即触发重绘 + 尺寸更新。
            c.lastRevision = align.revision
            canvas.needsDisplay = true
            canvas.updateContentSize()
        }
        if c.colorScheme != colorScheme {
            canvas.colorScheme = colorScheme
            c.colorScheme = colorScheme
        }
        if c.showConsensus != showConsensus {
            canvas.showConsensus = showConsensus
            c.showConsensus = showConsensus
        }
        // fontSize 守卫：避免重设触发 didSet 重建 3 个 NSFont 并重测字宽
        if canvas.fontSize != fontSize {
            canvas.fontSize = fontSize
        }
        if c.highContrast != highContrast {
            canvas.highContrast = highContrast
            c.highContrast = highContrast
            canvas.needsDisplay = true
        }
        if c.focusDimMode != focusDimMode {
            canvas.focusDimMode = focusDimMode
            c.focusDimMode = focusDimMode
            canvas.needsDisplay = true
        }
        if c.differenceReferenceRow != differenceReferenceRow {
            canvas.differenceReferenceRow = differenceReferenceRow
            c.differenceReferenceRow = differenceReferenceRow
            canvas.needsDisplay = true
        }
        if c.searchHits != searchHits {
            canvas.searchHits = searchHits
            c.searchHits = searchHits
            canvas.needsDisplay = true
        }
        // 命中导航：仅索引变化时滚动一次
        if c.currentHitIndex != currentHitIndex {
            canvas.currentHitIndex = currentHitIndex
            c.currentHitIndex = currentHitIndex
            canvas.needsDisplay = true
            if currentHitIndex >= 0 && currentHitIndex < searchHits.count {
                canvas.scrollToHit(searchHits[currentHitIndex])
            }
        }
        // 取走编辑命令上报的脏列集合，ensureStats 优先走增量路径
        if let provider = dirtyColumnsProvider {
            canvas.pendingDirtyColumns = provider()
        }
        // 深浅切换后同步滚动背景
        let dark = NSAppearance.isDarkNow
        if c.lastScrollViewDark != dark {
            scrollView.backgroundColor = Minimal.surface(dark: dark)
            c.lastScrollViewDark = dark
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastAlignment: Alignment?
        var lastRevision: UInt64 = 0   // 编辑后 revision 变化触发重绘
        var colorScheme: ColorScheme = .defaultNucleotide
        var showConsensus: Bool = true
        var highContrast: Bool = false
        var focusDimMode: Bool = false
        var differenceReferenceRow: Int?
        var searchHits: [SearchHit] = []
        var currentHitIndex: Int = -1
        var lastScrollViewDark = NSAppearance.isDarkNow
    }
}

// MARK: - 空状态引导卡片

struct EmptyStateView: View {
    @State private var appeared = false
    /// logo 从磁盘只读一次
    private static let logoImage: NSImage? = Bundle.main.url(forResource: "logo", withExtension: "svg")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        VStack(spacing: 18) {
            logoMark
                .frame(width: 72, height: 72)
            Text(L.s.emptyTitle)
                .font(.system(size: Minimal.font2XL, weight: .semibold))
            VStack(spacing: 6) {
                Text(L.s.emptyDesc1)
                Text(L.s.emptyDesc2)
            }
            .font(.system(size: Minimal.fontSM))
            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            HStack(spacing: 12) {
                MinimalPrimaryButton(title: L.s.emptyOpenFile, systemImage: "folder", height: Minimal.controlLG) {
                    OpenFileManager.shared.openFile()
                }
                MinimalSecondaryButton(title: L.s.emptyLoadExample, systemImage: "sparkles", height: Minimal.controlLG) {
                    HelpManager.shared.loadExample()
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(Minimal.surface(dark: isDarkAppearance)))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            if Minimal.shouldReduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            }
        }
    }

    @ViewBuilder
    private var logoMark: some View {
        if let nsImage = Self.logoImage {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            let dark = isDarkAppearance
            RoundedRectangle(cornerRadius: Minimal.radiusLG)
                .fill(Color(Minimal.primary(dark: dark)))
                .overlay(
                    Text("Σ")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(Color(Minimal.surface(dark: dark)))
                )
        }
    }
}

// MARK: - 新窗口待载入数据通道

enum PendingWindowData {
    private static var pending: (alignment: Alignment, fileName: String, format: AlignmentFormat)?

    static func prepare(alignment: Alignment, fileName: String, format: AlignmentFormat) {
        pending = (alignment, fileName, format)
    }

    static func consume() -> (Alignment, String, AlignmentFormat)? {
        guard let p = pending else { return nil }
        pending = nil
        return (p.alignment, p.fileName, p.format)
    }
}

// MARK: - 常驻主题切换

struct ThemeSwitchMenu: View {
    @ObservedObject private var store = AppearanceStore.shared
    @State private var hovered = false

    var body: some View {
        Menu {
            Button(L.s.settingsLight) { store.apply(.light) }
            Button(L.s.settingsDark) { store.apply(.dark) }
            Button(L.s.settingsSystem) { store.apply(.system) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: store.systemImage)
                    .font(.system(size: Minimal.fontSM))
                    .frame(width: 16)
                Text(L.s.toolbarAppearance)
                    .font(.system(size: Minimal.fontSM))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Minimal.controlH)
            .padding(.horizontal, Minimal.space2)
            // hover 仅填充，无边框
            .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .fill(hovered ? Color(Minimal.card(dark: isDarkAppearance)) : Color.clear))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering in
            hovered = hovering
        }
        .help(L.s.helpAppearance)
    }
}

// MARK: - 语言切换按钮

struct LanguageSwitchButton: View {
    @ObservedObject private var lang = LanguageManager.shared
    @State private var hovered = false

    var body: some View {
        Menu {
            Button(L.s.menuChinese) { lang.set(.zh) }
            Button(L.s.menuEnglish) { lang.set(.en) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: lang.language.systemImage)
                    .font(.system(size: Minimal.fontSM))
                    .frame(width: 16)
                Text(L.s.toolbarLanguage)
                    .font(.system(size: Minimal.fontSM))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Minimal.controlH)
            .padding(.horizontal, Minimal.space2)
            // hover 仅填充，无边框
            .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .fill(hovered ? Color(Minimal.card(dark: isDarkAppearance)) : Color.clear))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering in
            hovered = hovering
        }
        .help(L.s.helpLanguage)
    }
}
