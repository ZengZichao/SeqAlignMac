//  CenterPanelView.swift
//  SeqAlignMac — 中栏视图（从 ContentView.swift 拆分）
//
//  包含：搜索栏（常驻顶部，UI7）、主画布、状态栏。
//  搜索栏 / 加载覆盖层 / Toast 拆为独立子视图，仅订阅各自的高频子模型，
//  键入、进度、toast 不再经由 Workspace 牵连整树重算。

import AppKit
import SwiftUI

// MARK: - 搜索栏（订阅 SearchTextModel，键入失效面收敛到本视图）

struct SearchBarView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var textModel: SearchTextModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Minimal.fontSM))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .accessibilityHidden(true)

            searchScopeToggle

            MinimalTextField(placeholder: searchPlaceholder,
                             text: $textModel.text,
                             onEnter: {
                // #8：Enter 已有命中时跳下一处，否则执行新搜索
                if !workspace.searchHits.isEmpty {
                    workspace.findNext()
                } else {
                    workspace.performSearch()
                }
            }, onChange: { _ in
                // #8：逐字实时检索（防抖 300ms）
                workspace.searchDebounceWorkItem?.cancel()
                let workItem = DispatchWorkItem { workspace.performSearch() }
                workspace.searchDebounceWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
            })
            .frame(maxWidth: 300)

            searchRegexToggle

            if !workspace.searchHits.isEmpty {
                MinimalBarButton(title: L.s.searchPrev) { workspace.findPrev() }
                MinimalBarButton(title: L.s.searchNext) { workspace.findNext() }
            }

            if workspace.searchCompleted && workspace.searchHits.isEmpty && !workspace.searchText.isEmpty {
                Text(L.s.searchNoMatch)
                    .font(.system(size: Minimal.fontXS))
                    .lineLimit(1)
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            } else if !workspace.searchHits.isEmpty {
                Text("\(workspace.currentHitIndex + 1) / \(workspace.searchHits.count)")
                    .font(.system(size: Minimal.fontXS))
                    .lineLimit(1)
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    .monospacedDigit()
            }

            if workspace.searchComputing {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 0)

            // 关闭搜索：隐藏搜索栏并清除高亮
            Button(action: closeSearch) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: Minimal.fontSM))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
            }
            .buttonStyle(.plain)
            .help(L.s.searchClose)
            .accessibilityLabel(L.s.searchClose)
        }
        .padding(.horizontal, Minimal.space3)
        .padding(.vertical, 6)
        .background(Color(Minimal.controlSurface(dark: isDarkAppearance)))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(Minimal.border(dark: isDarkAppearance))).frame(height: 1)
        }
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

    private var searchScopeToggle: some View {
        HStack(spacing: 2) {
            ForEach(SearchScope.allCases, id: \.rawValue) { scope in
                searchScopePill(scope)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
            .fill(Color(Minimal.card(dark: isDarkAppearance))))
        .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
            .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
    }

    private func searchScopePill(_ scope: SearchScope) -> some View {
        let selected = workspace.searchScope == scope
        return Button {
            workspace.searchScope = scope
            workspace.performSearch()
        } label: {
            Text(scope == .content ? L.s.searchScopeContent : L.s.searchScopeName)
                .font(.system(size: Minimal.fontXS, weight: selected ? .medium : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(Color(selected
                    ? Minimal.primary(dark: isDarkAppearance)   // 近黑/近白
                    : Minimal.text(dark: isDarkAppearance)))
                .padding(.horizontal, Minimal.space2)
                .frame(height: Minimal.controlSM)
                .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .fill(selected ? Color(Minimal.surface(dark: isDarkAppearance)) : Color.clear))
                .shadow(color: Color(selected ? Minimal.shadowMD()[0].color : .clear), radius: Minimal.shadowMD()[0].radius, x: 0, y: Minimal.shadowMD()[0].offset.height)
                .shadow(color: Color(selected ? Minimal.shadowMD()[1].color : .clear), radius: Minimal.shadowMD()[1].radius, x: 0, y: Minimal.shadowMD()[1].offset.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(scope == .content ? L.s.searchScopeContent : L.s.searchScopeName)
    }

    private var searchRegexToggle: some View {
        Button {
            workspace.searchUseRegex.toggle()
            workspace.performSearch()
        } label: {
            Text(L.s.searchRegex)
                .font(.system(size: Minimal.fontXS, weight: workspace.searchUseRegex ? .medium : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(Color(workspace.searchUseRegex
                    ? Minimal.primary(dark: isDarkAppearance)   // 近黑/近白
                    : Minimal.text(dark: isDarkAppearance)))
                .padding(.horizontal, Minimal.space2)
                .frame(height: Minimal.controlH)
                .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .fill(Color(Minimal.card(dark: isDarkAppearance))))
                .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .help(workspace.searchUseRegex ? L.s.helpRegexOn : L.s.helpRegexOff)
        .accessibilityLabel(L.s.searchRegex)
    }
}

// MARK: - 加载覆盖层（仅订阅 LoadProgressModel）

struct LoadingOverlayView: View {
    @ObservedObject var loadModel: LoadProgressModel
    let dark: Bool

    var body: some View {
        VStack(spacing: 14) {
            ProgressView(value: loadModel.progress)
                .frame(width: 300)
            Text("\(L.s.loadingText) \(Int(loadModel.progress * 100))%")
                .lineLimit(1)
                .foregroundColor(Color(Minimal.textMuted(dark: dark)))
            Button(L.s.loadingCancel, role: .cancel) { loadModel.cancelLoading = true }
                .controlSize(.small)
        }
        .frame(width: 400, height: 140)
        .background(RoundedRectangle(cornerRadius: Minimal.radiusMD)
            .fill(Color(Minimal.surface(dark: dark))))
        // 多层阴影消费 shadowMD 令牌
        .shadow(color: Color(Minimal.shadowMD()[0].color), radius: Minimal.shadowMD()[0].radius, x: 0, y: Minimal.shadowMD()[0].offset.height)
        .shadow(color: Color(Minimal.shadowMD()[1].color), radius: Minimal.shadowMD()[1].radius, x: 0, y: Minimal.shadowMD()[1].offset.height)
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
                HStack(spacing: 8) {
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
                    .accessibilityHidden(true)
                    Text(toast)
                        .font(.system(size: Minimal.fontSM, weight: .medium))
                }
                .padding(.horizontal, Minimal.space3)
                .padding(.vertical, Minimal.space2)
                .background(Capsule().fill(Color(Minimal.controlSurface(dark: dark))))
                // 多层阴影消费 shadowMD 令牌
                .shadow(color: Color(Minimal.shadowMD()[0].color), radius: Minimal.shadowMD()[0].radius, x: 0, y: Minimal.shadowMD()[0].offset.height)
                .shadow(color: Color(Minimal.shadowMD()[1].color), radius: Minimal.shadowMD()[1].radius, x: 0, y: Minimal.shadowMD()[1].offset.height)
                .padding(.bottom, Minimal.space4)
            }
        }
    }
}

// MARK: - 错误横幅（仅订阅 errorMessage 相关状态）

struct ErrorBannerView: View {
    @ObservedObject var workspace: Workspace
    let dark: Bool

    var body: some View {
        VStack {
            if let err = workspace.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(Minimal.destructive(dark: dark)))
                    Text(err)
                        .font(.system(size: Minimal.fontSM))
                        .foregroundColor(Color(Minimal.textMuted(dark: dark)))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: { workspace.errorMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(Minimal.textMuted(dark: dark)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Minimal.space3)
                .padding(.vertical, Minimal.space2)
                .background(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                    .fill(Color(Minimal.controlSurface(dark: dark))))
                .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                    .stroke(Color(Minimal.destructive(dark: dark)).opacity(0.4), lineWidth: 1))
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

    var statusBar: some View {
        HStack(spacing: 0) {
            if let align = workspace.currentAlignment {
                statusItem(L.s.statusSeqCount, "\(align.seqCount)")
                statusDivider()
                statusItem(L.s.statusColCount, "\(align.length)")
                statusDivider()
                statusItem(L.s.statusPosition, "\(cursorRow + 1), \(cursorCol + 1)")
                statusDivider()
                statusItem(L.s.statusResidue, cursorResidue)
                if let identity = cursorColumnIdentity {
                    statusDivider()
                    statusItem(L.s.statusIdentity, "\(Int(round(identity * 100)))%")
                }
                statusDivider()
                statusItem(L.s.statusType, align.datatype == .nucleicAcid ? L.s.statusNucleic : L.s.statusAmino)

                if !align.charsets.isEmpty {
                    statusDivider()
                    statusItem("Charset", "\(align.charsets.count)")
                }

                // 后台保存期间的状态提示
                if workspace.isSaving {
                    statusDivider()
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(L.s.savingText)
                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    }
                }

                Spacer()
                if !workspace.currentFileName.isEmpty {
                    if workspace.isDirty {
                        Text("●")
                            .font(.system(size: Minimal.fontXXS))
                            .foregroundColor(Color(Minimal.destructive(dark: NSAppearance.isDarkNow)))
                    }
                    Image(systemName: "doc")
                        .font(.system(size: Minimal.fontXS))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
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
        .font(.system(size: Minimal.fontXS))
        .padding(.horizontal, Minimal.space3)
        .padding(.vertical, Minimal.space2)
        .background(Color(Minimal.controlSurface(dark: isDarkAppearance)))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(Minimal.border(dark: isDarkAppearance))).frame(height: 1)
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
        HStack(spacing: 4) {
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
            .fill(Color(Minimal.border(dark: isDarkAppearance)))   // borderStrong → border
            .frame(width: 1, height: Minimal.space3)
            .padding(.horizontal, Minimal.space2)
    }
}
