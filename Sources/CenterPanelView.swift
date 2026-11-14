//  CenterPanelView.swift
//  SeqAlignMac — 中栏：搜索栏、画布、状态栏
//
//  搜索的默认路径只有「输入 → 回车」，范围与正则收进选项浮层：
//  它们是需要配置一次的判断，不该常驻在每一次检索的主路径上。
//  搜索栏 / 加载覆盖层 / Toast 拆为独立子视图，仅订阅各自的高频子模型，
//  键入、进度、toast 不再经由 Workspace 牵连整树重算。

import AppKit
import SwiftUI

// MARK: - 搜索栏

struct SearchBarView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var textModel: SearchTextModel
    @State private var showOptions = false

    var body: some View {
        HStack(spacing: Minimal.space2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Minimal.fontXS))
                .frame(width: 16, height: 16, alignment: .center)
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .accessibilityHidden(true)

            MinimalTextField(placeholder: searchPlaceholder,
                             text: $textModel.text,
                             onEnter: {
                // Enter 已有命中时跳下一处，否则执行新搜索
                if !workspace.searchHits.isEmpty {
                    workspace.findNext()
                } else {
                    workspace.performSearch()
                }
            }, onChange: { _ in
                // 逐字实时检索（防抖 300ms）
                workspace.searchDebounceWorkItem?.cancel()
                let workItem = DispatchWorkItem { workspace.performSearch() }
                workspace.searchDebounceWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
            })
            .frame(maxWidth: 340)

            // 结果计数占据固定宽度，命中数变化时按钮不左右跳动
            Group {
                if workspace.searchComputing {
                    ProgressView().controlSize(.mini)
                } else if workspace.searchCompleted && workspace.searchHits.isEmpty && !workspace.searchText.isEmpty {
                    Text(L.s.searchNoMatch)
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                } else if !workspace.searchHits.isEmpty {
                    Text("\(workspace.currentHitIndex + 1)/\(workspace.searchHits.count)")
                        .monospacedDigit()
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                }
            }
            .font(.system(size: Minimal.fontXS))
            .frame(width: 64, alignment: .leading)

            if !workspace.searchHits.isEmpty {
                MinimalIconButton(systemImage: "chevron.up", help: L.s.searchPrev) { workspace.findPrev() }
                MinimalIconButton(systemImage: "chevron.down", help: L.s.searchNext) { workspace.findNext() }
            }

            Button {
                showOptions.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: Minimal.fontXS))
                    .frame(width: 16, height: 16)
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    .frame(width: Minimal.controlH, height: Minimal.controlH)
                    .background(
                        RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                            .fill(showOptions || workspace.searchUseRegex || workspace.searchScope != .content
                                  ? Color(Minimal.selected(dark: isDarkAppearance)) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(MinimalButtonStyle())
            .help(L.s.searchOptions)
            .accessibilityLabel(L.s.searchOptions)
            .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                searchOptions
            }

            Spacer(minLength: 0)

            MinimalIconButton(systemImage: "xmark", help: L.s.searchClose) { closeSearch() }
        }
        .padding(.leading, Minimal.space3)
        .padding(.trailing, Minimal.space1)
        .padding(.vertical, Minimal.space2 - 2)
        .background(Color(Minimal.panel(dark: isDarkAppearance)))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(Minimal.border(dark: isDarkAppearance)).opacity(0.9))
                .frame(height: Minimal.hairline)
        }
    }

    private var searchOptions: some View {
        VStack(alignment: .leading, spacing: Minimal.space3) {
            // 范围与正则只需配置一次，收进浮层后默认路径只剩「输入 → 回车」
            HStack(spacing: 0) {
                scopeSegment(.content, title: L.s.searchScopeContent)
                scopeSegment(.name, title: L.s.searchScopeName)
            }
            .frame(height: Minimal.controlH)
            .background(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .fill(Color(Minimal.card(dark: isDarkAppearance)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: Minimal.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous))

            Toggle(L.s.searchRegex, isOn: Binding(
                get: { workspace.searchUseRegex },
                set: { newValue in
                    workspace.searchUseRegex = newValue
                    workspace.performSearch()
                }
            ))
            .toggleStyle(.switch)
            .font(.system(size: Minimal.fontSM))
        }
        .padding(Minimal.space3)
        .frame(width: 220)
    }

    private func scopeSegment(_ scope: SearchScope, title: String) -> some View {
        let selected = workspace.searchScope == scope
        return Button {
            workspace.searchScope = scope
            workspace.performSearch()
        } label: {
            Text(title)
                .font(.system(size: Minimal.fontXS, weight: selected ? .medium : .regular))
                .foregroundColor(Color(selected ? Minimal.text(dark: isDarkAppearance)
                                                : Minimal.textMuted(dark: isDarkAppearance)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    // 内层 4pt：外框 6pt 内缩 2pt 的同心圆角
                    RoundedRectangle(cornerRadius: Minimal.radiusXS, style: .continuous)
                        .fill(selected ? Color(Minimal.selected(dark: isDarkAppearance)) : .clear)
                        .padding(2)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(MinimalButtonStyle())
        .accessibilityLabel(title)
    }

    private var searchPlaceholder: String {
        if workspace.searchScope == .name {
            return workspace.searchUseRegex ? L.s.searchPlaceholderNameRegex : L.s.searchPlaceholderName
        }
        return workspace.searchUseRegex ? L.s.searchPlaceholderContentRegex : L.s.searchPlaceholderContent
    }

    private func closeSearch() {
        workspace.isSearching = false
        workspace.searchText = ""
        workspace.searchHits = []
        workspace.currentHitIndex = -1
        workspace.searchCompleted = false
        workspace.cancelPendingSearch()
    }
}

// MARK: - 加载覆盖层（仅订阅 LoadProgressModel）

struct LoadingOverlayView: View {
    @ObservedObject var loadModel: LoadProgressModel
    let dark: Bool

    var body: some View {
        VStack(spacing: Minimal.space3) {
            ProgressView(value: loadModel.progress)
                .frame(width: 260)
            HStack(spacing: Minimal.space2) {
                Text(L.s.loadingText)
                    .foregroundColor(Color(Minimal.textMuted(dark: dark)))
                Text("\(Int(loadModel.progress * 100))%")
                    .monospacedDigit()
                    .foregroundColor(Color(Minimal.text(dark: dark)))
            }
            .font(.system(size: Minimal.fontXS))
            .lineLimit(1)

            MinimalSecondaryButton(title: L.s.loadingCancel) { loadModel.cancelLoading = true }
        }
        .padding(Minimal.space5)
        .background(
            RoundedRectangle(cornerRadius: Minimal.radiusMD, style: .continuous)
                .fill(Color(Minimal.surface(dark: dark)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Minimal.radiusMD, style: .continuous)
                .stroke(Color(Minimal.border(dark: dark)), lineWidth: Minimal.hairline)
        )
        .shadow(color: Color(Minimal.shadowMD()[0].color), radius: Minimal.shadowMD()[0].radius,
                x: 0, y: Minimal.shadowMD()[0].offset.height)
    }
}

// MARK: - Toast（仅订阅 ToastModel）

struct ToastOverlayView: View {
    @ObservedObject var toastModel: ToastModel
    let dark: Bool

    var body: some View {
        VStack {
            Spacer()
            if let toast = toastModel.message {
                HStack(spacing: Minimal.space2) {
                    Group {
                        switch toastModel.kind {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(Minimal.success(dark: dark)))
                        case .info:
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(Color(Minimal.textMuted(dark: dark)))
                        case .warning:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color(Minimal.warning(dark: dark)))
                        case .error:
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundColor(Color(Minimal.destructive(dark: dark)))
                        }
                    }
                    .font(.system(size: Minimal.fontXS))
                    .accessibilityHidden(true)

                    Text(toast)
                        .font(.system(size: Minimal.fontSM, weight: .medium))
                        .foregroundColor(Color(Minimal.text(dark: dark)))
                        .lineLimit(2)
                }
                .padding(.horizontal, Minimal.space3)
                .padding(.vertical, Minimal.space2 + 2)
                .background(
                    RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                        .fill(Color(Minimal.panel(dark: dark)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                        .stroke(Color(Minimal.border(dark: dark)), lineWidth: Minimal.hairline)
                )
                .shadow(color: Color(Minimal.shadowMD()[0].color), radius: Minimal.shadowMD()[0].radius,
                        x: 0, y: Minimal.shadowMD()[0].offset.height)
                .padding(.bottom, Minimal.space4)
            }
        }
    }
}

// MARK: - 错误横幅

struct ErrorBannerView: View {
    @ObservedObject var workspace: Workspace
    let dark: Bool

    var body: some View {
        VStack {
            if let err = workspace.errorMessage {
                HStack(alignment: .top, spacing: Minimal.space2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: Minimal.fontXS))
                        .foregroundColor(Color(Minimal.destructive(dark: dark)))
                    Text(err)
                        .font(.system(size: Minimal.fontXS))
                        .foregroundColor(Color(Minimal.text(dark: dark)))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    MinimalIconButton(systemImage: "xmark", help: L.s.close) {
                        workspace.errorMessage = nil
                    }
                }
                .padding(.leading, Minimal.space3)
                .padding(.trailing, Minimal.space1)
                .padding(.vertical, Minimal.space2 - 2)
                .background(
                    RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                        .fill(Color(Minimal.destructiveSoft(dark: dark)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                        .stroke(Color(Minimal.destructive(dark: dark).withAlphaComponent(0.35)),
                                lineWidth: Minimal.hairline)
                )
                .padding(.horizontal, Minimal.space3)
                .padding(.top, Minimal.space2)
            }
            Spacer()
        }
    }
}

// MARK: - 中栏内容

extension ContentView {
    // 搜索栏仅在工作区处于搜索状态（isSearching）时显示，由左侧栏「搜索」按钮或 Cmd+F 触发
    var centerContent: some View {
        VStack(spacing: 0) {
            if workspace.isSearching {
                SearchBarView(workspace: workspace, textModel: workspace.searchTextModel)
            }
            mainCanvas
            statusBar
        }
    }

    // MARK: - 主画布

    var mainCanvas: some View {
        ZStack {
            AlignmentCanvasRepresentable(
                alignment: workspace.currentAlignment,
                colorScheme: workspace.currentScheme,
                showConsensus: workspace.showConsensus,
                fontSize: workspace.fontSize,
                highContrast: workspace.highContrast,
                focusDimMode: workspace.focusDimMode,
                differenceReferenceRow: workspace.differenceMode ? workspace.referenceRow : nil,
                searchHits: workspace.searchHits,
                currentHitIndex: workspace.currentHitIndex,
                dirtyColumnsProvider: { [weak workspace] in workspace?.takeCanvasDirtyColumns() },
                onPositionChanged: { row, col in
                    cursorRow = row
                    cursorCol = col
                },
                onFontSizeChanged: { newSize in
                    workspace.fontSize = newSize
                },
                onRenameRequest: { row in
                    renameRow = row
                    if let align = workspace.currentAlignment, row < align.seqCount {
                        renameText = align.sequences[row].name
                    }
                    renameSheet = true
                },
                onDeleteRequest: { row in
                    if let align = workspace.currentAlignment {
                        let cmd = RemoveSeqCommand(
                            indices: [row],
                            removedSequences: [align.sequences[row]]
                        )
                        UndoRedoCoordinator.shared.execute(cmd)
                    }
                },
                onMoveRequest: { from, to in
                    let cmd = MoveSeqCommand(fromIndex: from, toIndex: to)
                    UndoRedoCoordinator.shared.execute(cmd)
                },
                onContextAction: { action in
                    handleContextAction(action)
                },
                onCopied: { message, kind in
                    workspace.showToast(message, kind: kind)
                },
                onSelectionChanged: { range in
                    // 相等性去重——拖选中每次鼠标事件的上报只在真正变化时写 @Published
                    if workspace.currentSelection != range {
                        workspace.currentSelection = range
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if workspace.currentAlignment == nil {
                EmptyStateView()
            }

            if workspace.isLoading {
                LoadingOverlayView(loadModel: workspace.loadModel, dark: isDarkAppearance)
            }

            if workspace.errorMessage != nil {
                ErrorBannerView(workspace: workspace, dark: isDarkAppearance)
            }

            ToastOverlayView(toastModel: workspace.toastModel, dark: isDarkAppearance)
        }
    }

    // MARK: - 状态栏
    //
    //  只保留「当前指向哪里」与「改过没有」：序列数 / 列数 / 类型已经在右侧统计面板
    //  的概览里，状态栏重复一遍只会把真正会随光标变化的三项挤到右边。

    var statusBar: some View {
        HStack(spacing: 0) {
            if let align = workspace.currentAlignment {
                statusItem(L.s.statusPosition, "\(cursorRow + 1):\(cursorCol + 1)")
                statusDivider()
                statusItem(L.s.statusResidue, cursorResidue)
                if let identity = cursorColumnIdentity {
                    statusDivider()
                    statusItem(L.s.statusIdentity, "\(Int(round(identity * 100)))%")
                }
                if !align.charsets.isEmpty {
                    statusDivider()
                    statusItem(L.s.statusCharset, "\(align.charsets.count)")
                }
                if workspace.isSaving {
                    statusDivider()
                    HStack(spacing: Minimal.space1) {
                        ProgressView().controlSize(.mini)
                        Text(L.s.savingText)
                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    }
                }

                Spacer(minLength: Minimal.space3)
                if !workspace.currentFileName.isEmpty {
                    if workspace.isDirty {
                        Circle()
                            .fill(Color(Minimal.warningSolid(dark: isDarkAppearance)))
                            .frame(width: 5, height: 5)
                    }
                    Text(workspace.currentFileName)
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(workspace.sourceURL?.path ?? workspace.currentFileName)
                }
            } else {
                Text(L.s.statusNoFile)
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                Spacer()
            }
        }
        .font(.system(size: Minimal.fontXXS))
        .padding(.horizontal, Minimal.space3)
        .frame(height: 26)
        .background(Color(Minimal.panel(dark: isDarkAppearance)))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(Minimal.border(dark: isDarkAppearance)))
                .frame(height: Minimal.hairline)
        }
    }

    private var cursorResidue: String {
        guard let align = workspace.currentAlignment, align.seqCount > 0, align.length > 0 else { return "-" }
        let r = min(max(0, cursorRow), align.seqCount - 1)
        let c = min(max(0, cursorCol), align.length - 1)
        let byte = align.residue(row: r, col: c)
        return byte == 0x2D ? "-" : String(UnicodeScalar(byte))
    }

    /// 经 Workspace 的 (对象, revision, 列) 缓存读取
    private var cursorColumnIdentity: Double? {
        guard let align = workspace.currentAlignment, align.seqCount > 0, align.length > 0 else { return nil }
        let c = min(max(0, cursorCol), align.length - 1)
        return workspace.cachedColumnIdentity(align: align, col: c)
    }

    private func statusItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: Minimal.space1 + 2) {
            Text(label)
                .lineLimit(1)
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
                .monospacedDigit()
                .fontWeight(.medium)
                .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
        }
    }

    private func statusDivider() -> some View {
        Rectangle()
            .fill(Color(Minimal.border(dark: isDarkAppearance)))
            .frame(width: Minimal.hairline, height: Minimal.space2 + 2)
            .padding(.horizontal, Minimal.space2 + 2)
    }
}
