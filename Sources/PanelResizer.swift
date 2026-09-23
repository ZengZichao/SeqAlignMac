//  PanelResizer.swift
//  SeqAlignMac — 面板分隔拖拽条（从 SharedUIComponents.swift 拆分）
//
//  画布与统计面板之间的可拖拽分隔条，支持鼠标拖拽调整面板宽度。
//  拖拽过程中实时更新面板宽度，随鼠标同步移动（无预览竖线、无需松开生效）；
//  宽度持久化由 ContentView 侧的 .onChange(of:) 处理——@State 的 didSet 在
//  子视图经 Binding 回写时不会触发，不能用于持久化。

import AppKit
import SwiftUI

// MARK: - 面板分隔条

/// side = .right：分隔条右侧的面板（拖右变窄）；side = .left：分隔条左侧的面板（拖右变宽）
enum PanelResizerSide {
    case left
    case right
}

struct PanelResizer: View {
    @Binding var width: CGFloat
    var side: PanelResizerSide = .right
    var minWidth: CGFloat = 220
    var maxWidth: CGFloat = 460

    var body: some View {
        PanelResizerView(width: $width, side: side, minWidth: minWidth, maxWidth: maxWidth)
            .frame(width: 8)
            .contentShape(Rectangle())
    }
}

final class PanelResizerNSView: NSView {
    var widthBinding: Binding<CGFloat>?
    var side: PanelResizerSide = .right
    var minWidth: CGFloat = 220
    var maxWidth: CGFloat = 460
    private var dragStartWidth: CGFloat = 0
    private var totalDeltaX: CGFloat = 0
    private var isDragging = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragStartWidth = widthBinding?.wrappedValue ?? 264
        totalDeltaX = 0
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        // 实时更新面板宽度：随鼠标拖动同步移动，无需松开后才生效。
        totalDeltaX += event.deltaX
        let signed = side == .right ? -totalDeltaX : totalDeltaX
        let newWidth = min(maxWidth, max(minWidth, dragStartWidth + signed))
        widthBinding?.wrappedValue = newWidth
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}

struct PanelResizerView: NSViewRepresentable {
    @Binding var width: CGFloat
    let side: PanelResizerSide
    let minWidth: CGFloat
    let maxWidth: CGFloat

    func makeNSView(context: Context) -> PanelResizerNSView {
        let view = PanelResizerNSView()
        view.widthBinding = $width
        view.side = side
        view.minWidth = minWidth
        view.maxWidth = maxWidth
        return view
    }

    func updateNSView(_ nsView: PanelResizerNSView, context: Context) {
        nsView.widthBinding = $width
        nsView.side = side
        nsView.minWidth = minWidth
        nsView.maxWidth = maxWidth
    }
}
