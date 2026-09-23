//  CommandPaletteView.swift
//  SeqAlignMac — 命令面板弹窗（从 ToolSheetViews.swift 拆分）
//
//  类似 VS Code 的 ⌘⇧P 命令面板，支持模糊搜索快速执行命令。
//
//  U1（键盘导航三连失效修复）：
//  - 选中态用 accentSoft 圆角背景填充（若仅用 Minimal.primary 文字变色，
//    而 Minimal.primary 与 Minimal.text 色值完全相同，高亮在视觉上不存在）；
//  - query 变化时 selectedIndex 重置为 0；
//  - ScrollViewReader 在选中项变化时滚动跟随。

import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool

    private struct PaletteCommand: Identifiable {
        // 稳定 id：`let id = UUID()` 在每次 body 求值时重新生成，会让
        // ForEach 身份全变导致整表重建、滚动状态丢失
        let id: String
        let title: String
        let shortcut: String
        let action: () -> Void
    }

    /// 32 条命令含闭包结构体，按语言缓存
    private static var cachedCommands: (lang: AppLanguage, commands: [PaletteCommand])?

    private var commands: [PaletteCommand] {
        let lang = LanguageManager.shared.language
        if let cached = Self.cachedCommands, cached.lang == lang {
            return cached.commands
        }
        let built: [PaletteCommand] = [
            PaletteCommand(id: "open", title: L.s.cmdOpen, shortcut: "⌘O") { OpenFileManager.shared.openFile() },
            PaletteCommand(id: "save", title: L.s.cmdSave, shortcut: "⌘S") { SaveManager.shared.saveCurrent() },
            PaletteCommand(id: "saveAs", title: L.s.cmdSaveAs, shortcut: "⇧⌘S") { SaveManager.shared.saveAs() },
            PaletteCommand(id: "runAlign", title: L.s.cmdRunAlign, shortcut: "⇧⌘B") { NotificationCenter.default.post(name: .runAlignment, object: nil) },
            PaletteCommand(id: "translate", title: L.s.cmdTranslate, shortcut: "⇧⌘T") { NotificationCenter.default.post(name: .showTranslate, object: nil) },
            PaletteCommand(id: "primer", title: L.s.cmdPrimer, shortcut: "") { NotificationCenter.default.post(name: .showPrimer, object: nil) },
            PaletteCommand(id: "quality", title: L.s.cmdQuality, shortcut: "") { ToolActions.shared.showQualityReport() },
            PaletteCommand(id: "search", title: L.s.cmdSearch, shortcut: "⌘F") { SearchManager.shared.showSearch() },
            PaletteCommand(id: "copy", title: L.s.cmdCopy, shortcut: "⌘C") { CopyPasteRouter.shared.copy() },
            PaletteCommand(id: "selectAll", title: L.s.cmdSelectAll, shortcut: "⌘A") { CopyPasteRouter.shared.selectAll() },
            PaletteCommand(id: "revComp", title: L.s.cmdRevComp, shortcut: "⌘I") { EditActions.shared.reverseComplement() },
            PaletteCommand(id: "insertGap", title: L.s.cmdInsertGap, shortcut: "⌘D") { EditActions.shared.insertGap() },
            PaletteCommand(id: "deleteSeq", title: L.s.cmdDeleteSeq, shortcut: "⇧⌘X") { EditActions.shared.removeSelected() },
            PaletteCommand(id: "moveSeq", title: L.s.cmdMoveSeq, shortcut: "") { EditActions.shared.moveSequence() },
            PaletteCommand(id: "renameSeq", title: L.s.cmdRenameSeq, shortcut: "⇧⌘R") { EditActions.shared.renameSequence() },
            PaletteCommand(id: "schemeMinimal", title: L.s.cmdSchemeMinimal, shortcut: "⇧⌘1") { ColorSchemeManager.shared.setScheme(.minimal) },
            PaletteCommand(id: "schemeClustalX", title: L.s.cmdSchemeClustalX, shortcut: "⇧⌘2") { ColorSchemeManager.shared.setScheme(.clustalX) },
            PaletteCommand(id: "schemeZappo", title: L.s.cmdSchemeZappo, shortcut: "⇧⌘3") { ColorSchemeManager.shared.setScheme(.zappo) },
            PaletteCommand(id: "schemeSeaView", title: L.s.cmdSchemeSeaView, shortcut: "⇧⌘4") { ColorSchemeManager.shared.setScheme(.seaView) },
            PaletteCommand(id: "schemeDefault", title: L.s.cmdSchemeDefault, shortcut: "") { ColorSchemeManager.shared.setScheme(.defaultNucleotide) },
            PaletteCommand(id: "schemeTiTv", title: L.s.cmdSchemeTransitionTransversion, shortcut: "") { ColorSchemeManager.shared.setScheme(.transitionTransversion) },
            // 标注规范修正——快捷键实际是 ⌘=（⌘+ 需要 Shift），菜单注册同样是 "+"
            PaletteCommand(id: "zoomIn", title: L.s.cmdZoomIn, shortcut: "⌘=") { ZoomManager.shared.zoomIn() },
            PaletteCommand(id: "zoomOut", title: L.s.cmdZoomOut, shortcut: "⌘-") { ZoomManager.shared.zoomOut() },
            PaletteCommand(id: "zoomReset", title: L.s.cmdZoomReset, shortcut: "⇧⌘0") { ZoomManager.shared.reset() },
            PaletteCommand(id: "toggleConsensus", title: L.s.cmdToggleConsensus, shortcut: "⇧⌘G") { ToggleManager.shared.toggleConsensus() },
            PaletteCommand(id: "themeLight", title: L.s.cmdThemeLight, shortcut: "") { AppearanceStore.shared.apply(.light) },
            PaletteCommand(id: "themeDark", title: L.s.cmdThemeDark, shortcut: "") { AppearanceStore.shared.apply(.dark) },
            PaletteCommand(id: "themeSystem", title: L.s.cmdThemeSystem, shortcut: "") { AppearanceStore.shared.apply(.system) },
            PaletteCommand(id: "settings", title: L.s.cmdSettings, shortcut: "⌘,") { SettingsManager.shared.showSettings() },
            PaletteCommand(id: "guide", title: L.s.cmdGuide, shortcut: "") { HelpManager.shared.showGuide() },
            PaletteCommand(id: "loadExample", title: L.s.cmdLoadExample, shortcut: "") { HelpManager.shared.loadExample() },
            PaletteCommand(id: "about", title: L.s.cmdAbout, shortcut: "") { HelpManager.shared.showAbout() },
        ]
        Self.cachedCommands = (lang, built)
        return built
    }

    private var filtered: [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        return commands.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    .accessibilityHidden(true)
                TextField(L.s.cmdPalettePlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: Minimal.fontLG))
                    .focused($focused)
                    .onSubmit { execute(selectedIndex) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .fill(Color(Minimal.card(dark: isDarkAppearance))))
            .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L.s.cmdPaletteTitle)

            // ScrollViewReader 让选中项滚动进视口
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        if filtered.isEmpty {
                            Text(L.s.cmdPaletteNoMatch)
                                .font(.system(size: Minimal.fontSM))
                                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                                .padding(.vertical, 20)
                        } else {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, cmd in
                                CommandRow(cmd: CommandPaletteCommandRef(
                                    title: cmd.title, shortcut: cmd.shortcut) {
                                        dismiss()
                                        DispatchQueue.main.async { cmd.action() }
                                    },
                                    isSelected: index == selectedIndex,
                                    highlightQuery: query)
                                    .id(cmd.id)
                            }
                        }
                    }
                    .padding(1)
                }
                .frame(height: 260)
                .onChange(of: selectedIndex) { _, newValue in
                    guard !filtered.isEmpty else { return }
                    let target = filtered[min(max(0, newValue), filtered.count - 1)].id
                    // 受 shouldReduceMotion 守卫（项目统一动效约定）
                    if Minimal.shouldReduceMotion {
                        proxy.scrollTo(target, anchor: .center)
                    } else {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(Minimal.space4)
        .frame(width: 420, height: 330)
        .minimalSheetContainer()
        // 命令面板补 Esc 关闭快捷键（全工程唯一没挂的弹窗）
        .keyboardShortcut(.escape)
        .onAppear {
            focused = true
            selectedIndex = 0
        }
        // query 变化时重置选中索引，保证回车执行的是「最匹配的第一条」
        .onChange(of: query) { _, _ in
            if selectedIndex != 0 { selectedIndex = 0 }
        }
        // 键盘导航：↑/↓ 选择 + 回车执行（⌘⇧P 面板的基本预期）
        .onKeyPress(.upArrow) {
            if filtered.isEmpty { return .ignored }
            selectedIndex = (selectedIndex - 1 + filtered.count) % filtered.count
            return .handled
        }
        .onKeyPress(.downArrow) {
            if filtered.isEmpty { return .ignored }
            selectedIndex = (selectedIndex + 1) % filtered.count
            return .handled
        }
    }

    private func execute(_ index: Int) {
        guard !filtered.isEmpty else { return }
        let clamped = min(max(0, index), filtered.count - 1)
        let cmd = filtered[clamped]
        dismiss()
        DispatchQueue.main.async { cmd.action() }
    }
}

// MARK: - 单行命令（选中态 + 按压态 + hover / 子串高亮 / isSelected trait）

private struct CommandRow: View {
    let cmd: CommandPaletteCommandRef
    let isSelected: Bool
    let highlightQuery: String
    @State private var hovered = false

    var body: some View {
        Button {
            cmd.run()
        } label: {
            HStack {
                highlightedTitle
                    .font(.system(size: Minimal.fontBase))
                    .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                Spacer()
                // 空 shortcut 不再渲染空 Text 留白
                if !cmd.shortcut.isEmpty {
                    Text(cmd.shortcut)
                        .font(.system(size: Minimal.fontXS, design: .monospaced))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .fill(rowBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(MinimalButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var rowBackground: Color {
        // 选中行用 accentSoft 背景填充（旧 primary 文字变色与 text 同色，高亮不可见）
        if isSelected { return Color(Minimal.accentSoft(dark: isDarkAppearance)) }
        if hovered { return Color(Minimal.card(dark: isDarkAppearance)) }
        return Color.clear
    }

    /// 匹配子串加粗高亮（不匹配时原样返回）
    private var highlightedTitle: Text {
        let q = highlightQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let range = cmd.title.range(of: q, options: .caseInsensitive) else {
            return Text(cmd.title)
        }
        return Text(cmd.title[..<range.lowerBound])
            + Text(cmd.title[range]).fontWeight(.semibold)
            + Text(cmd.title[range.upperBound...])
    }
}

/// 跨 struct 的命令引用：CommandPaletteView.PaletteCommand 是 private 嵌套类型，
/// 提取行视图需要一个非嵌套的轻量盒
struct CommandPaletteCommandRef {
    let title: String
    let shortcut: String
    private let action: () -> Void
    init(title: String, shortcut: String, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }
    func run() {
        action()
    }
}
