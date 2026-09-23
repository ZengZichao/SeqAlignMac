//  MinimalControls.swift
//  SeqAlignMac — 极简控件库
//
//  统一输入框 / 主按钮 / 次按钮的视觉实现，只消费 Minimal 令牌：
//  圆角 6px、1px 中性边框、近黑实心主按钮、灰阶卡片输入底。
//  替换系统 .roundedBorder / .borderedProminent 的蓝色 chrome，与中性灰极简 shell 一致。
//  供搜索栏、各 sheet（引物 / 重命名 / 外部比对 / 空状态）复用。

import AppKit
import SwiftUI

// MARK: - 按压态按钮样式

struct MinimalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration)
    }

    /// ButtonStyle 不是 View，无法直接持有 @State，故包一层内部视图承载 hover 态。
    private struct HoverLabel: View {
        let configuration: Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1.0)
                .brightness(hovered && !configuration.isPressed ? 0.04 : 0)
                .onHover { hovered = $0 }
                .animation(Minimal.shouldReduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        }
    }
}

/// 极简输入框：plain 文本样式 + card 底 + 1px 边框 + 6px 圆角
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
            .padding(.horizontal, Minimal.space2)
            .frame(height: Minimal.controlH)
            .background(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .fill(Color(Minimal.surface(dark: dark)))
            )
            // focus 状态补充
            .overlay(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .stroke(isFocused ? Color(Minimal.primary(dark: dark)) : Color(Minimal.border(dark: dark)),
                            lineWidth: isFocused ? 1.5 : 1)
            )
            .onChange(of: text) { _, newValue in
                onChange?(newValue)
            }
            .onSubmit {
                // #8：onEnter 优先（跳下一命中），回退到 onSubmit（新搜索）
                if let onEnter = onEnter {
                    onEnter()
                } else {
                    onSubmit?()
                }
            }
    }
}

/// 极简主按钮：近黑实心、白字、6px 圆角（替代系统 borderedProminent 蓝色 chrome）
struct MinimalPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = Minimal.controlH
    let action: () -> Void

    private var dark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Minimal.fontXS, weight: .medium))
                }
                Text(title)
                    .font(.system(size: Minimal.fontSM, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(Color(Minimal.surface(dark: dark)))
            .padding(.horizontal, Minimal.space4 - Minimal.space1)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .fill(Color(Minimal.primary(dark: dark)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MinimalButtonStyle())
    }
}

/// 极简次按钮：白底 + 1px 中性边框（替代系统 bordered）
struct MinimalSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = Minimal.controlH
    let action: () -> Void

    private var dark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Minimal.fontXS, weight: .medium))
                }
                Text(title)
                    .font(.system(size: Minimal.fontSM, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(Color(Minimal.text(dark: dark)))
            .padding(.horizontal, Minimal.space4 - Minimal.space1)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .fill(Color(Minimal.surface(dark: dark)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                    .stroke(Color(Minimal.border(dark: dark)), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MinimalButtonStyle())
    }
}

/// 搜索栏极简按钮（小号，供「查找 / 上一个 / 下一个」使用）
struct MinimalBarButton: View {
    let title: String
    let action: () -> Void

    private var dark: Bool { NSAppearance.isDarkNow }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Minimal.fontSM, weight: .medium))
                .lineLimit(1)
                .foregroundColor(Color(Minimal.text(dark: dark)))
                .padding(.horizontal, Minimal.space3 - Minimal.space1)
                .frame(height: Minimal.controlH)
                .background(
                    RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                        .fill(Color(Minimal.card(dark: dark)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                        .stroke(Color(Minimal.border(dark: dark)), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(MinimalButtonStyle())
    }
}
