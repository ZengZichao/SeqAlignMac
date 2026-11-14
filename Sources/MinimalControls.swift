//  MinimalControls.swift
//  SeqAlignMac — 控件库
//
//  统一输入框 / 主按钮 / 次按钮 / 图标按钮的视觉实现，只消费 Minimal 令牌：
//  圆角 6（嵌套内层 4）、0.5pt 细边框、gray-12 实心主按钮、gray-11 次要文字。
//  不做悬停动画：状态用颜色瞬时切换表达，避免界面在指针移动时持续“呼吸”。

import AppKit
import SwiftUI

// MARK: - 按压态按钮样式

struct MinimalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1.0)
    }
}

// MARK: - 输入框

/// 输入框：plain 文本样式 + surface 底 + 0.5pt 边框 + 6pt 圆角
struct MinimalTextField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    var onEnter: (() -> Void)? = nil
    var onChange: ((String) -> Void)? = nil

    @FocusState private var isFocused: Bool

    private var dark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: Minimal.fontSM))
            .focused($isFocused)
            .foregroundColor(Color(Minimal.text(dark: dark)))
            .padding(.horizontal, Minimal.space3 - 2)
            .frame(height: Minimal.controlH)
            .background(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .fill(Color(Minimal.surface(dark: dark)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .stroke(isFocused ? Color(Minimal.focusRing(dark: dark)) : Color(Minimal.border(dark: dark)),
                            lineWidth: Minimal.hairline)
            )
            .onChange(of: text) { _, newValue in
                onChange?(newValue)
            }
            .onSubmit {
                // onEnter 优先（跳下一命中），回退到 onSubmit（新搜索）
                if let onEnter = onEnter {
                    onEnter()
                } else {
                    onSubmit?()
                }
            }
    }
}

// MARK: - 按钮

/// 主按钮：gray-12 实心、gray-1 文字、6pt 圆角
struct MinimalPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = Minimal.controlH
    /// 成对出现的主/次按钮传入同一个最小宽度，保证两枚圆角矩形尺寸一致
    var minWidth: CGFloat = 0
    let action: () -> Void

    @State private var hovered = false
    private var dark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Minimal.fontXS, weight: .medium))
                        .frame(width: 14, height: 14)
                }
                Text(title)
                    .font(.system(size: Minimal.fontSM, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(Color(Minimal.onPrimary(dark: dark)))
            .padding(.horizontal, Minimal.space3)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .fill(Color(hovered ? Minimal.primaryHover(dark: dark) : Minimal.primary(dark: dark)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MinimalButtonStyle())
        .onHover { hovered = $0 }
    }
}

/// 次按钮：surface 底 + 0.5pt gray-7 边框
struct MinimalSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = Minimal.controlH
    var minWidth: CGFloat = 0
    let action: () -> Void

    @State private var hovered = false
    private var dark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Minimal.fontXS, weight: .medium))
                        .frame(width: 14, height: 14)
                }
                Text(title)
                    .font(.system(size: Minimal.fontSM, weight: .regular))
                    .lineLimit(1)
            }
            .foregroundColor(Color(Minimal.text(dark: dark)))
            .padding(.horizontal, Minimal.space3)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .fill(Color(hovered ? Minimal.hover(dark: dark) : Minimal.surface(dark: dark)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .stroke(Color(Minimal.borderStrong(dark: dark)), lineWidth: Minimal.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MinimalButtonStyle())
        .onHover { hovered = $0 }
    }
}

/// 紧凑文字按钮（搜索栏“上一个 / 下一个”等）：无边框，悬停填充
struct MinimalBarButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    @State private var hovered = false
    private var dark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Minimal.fontXS, weight: .medium))
                        .frame(width: 13, height: 13)
                }
                Text(title)
                    .font(.system(size: Minimal.fontXS, weight: .regular))
                    .lineLimit(1)
            }
            .foregroundColor(Color(Minimal.text(dark: dark)))
            .padding(.horizontal, Minimal.space2 + 2)
            .frame(height: Minimal.controlSM + 6)
            .background(
                RoundedRectangle(cornerRadius: Minimal.radiusXS, style: .continuous)
                    .fill(Color(hovered ? Minimal.hover(dark: dark) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MinimalButtonStyle())
        .onHover { hovered = $0 }
    }
}

/// 纯图标按钮（28×28）：关闭、复制、翻页等动作唯一且不需要文字的场合
struct MinimalIconButton: View {
    let systemImage: String
    let help: String
    var size: CGFloat = Minimal.controlH
    let action: () -> Void

    @State private var hovered = false
    private var dark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Minimal.fontXS, weight: .regular))
                .frame(width: 16, height: 16)
                .foregroundColor(Color(hovered ? Minimal.text(dark: dark) : Minimal.textMuted(dark: dark)))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                        .fill(Color(hovered ? Minimal.hover(dark: dark) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(MinimalButtonStyle())
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovered = $0 }
    }
}

// MARK: - 分段控件

/// 自绘分段控件（2–3 段、标签短）。
/// 系统 `.segmented` 的选中底色由 AppKit 决定：暗色下只有约 1.6:1 的对比，
/// 选中与未选中的文字亮度也几乎一致，状态读不出来，且颜色不在 Radix 色板内。
/// 这里改用 gray-12 实底 + gray-1 文字，明暗两端都保持明确对比。
struct MinimalSegmentedControl<Value: Hashable>: View {
    struct Option {
        let title: String
        let value: Value
    }

    let options: [Option]
    @Binding var selection: Value
    /// 与同列其他控件同宽时传入，保证左缘落在同一条竖线上
    var width: CGFloat? = nil

    private var dark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                SegmentCell(
                    title: options[index].title,
                    isSelected: options[index].value == selection,
                    dark: dark,
                    action: { selection = options[index].value }
                )
            }
        }
        .padding(2)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .fill(Color(Minimal.card(dark: dark)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                .stroke(Color(Minimal.border(dark: dark)), lineWidth: Minimal.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous))
    }
}

/// 分段单元：外层 6 圆角、四周内缩 2 → 内层 4，同心嵌套
private struct SegmentCell: View {
    let title: String
    let isSelected: Bool
    let dark: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Minimal.fontSM, weight: isSelected ? .medium : .regular))
                .foregroundColor(Color(isSelected ? Minimal.onPrimary(dark: dark) : Minimal.textMuted(dark: dark)))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: Minimal.controlH - 4)
                .background(
                    RoundedRectangle(cornerRadius: Minimal.radiusXS, style: .continuous)
                        .fill(fillColor)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(MinimalButtonStyle())
        .onHover { hovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fillColor: Color {
        if isSelected { return Color(Minimal.primary(dark: dark)) }
        return hovered ? Color(Minimal.hover(dark: dark)) : Color.clear
    }
}
