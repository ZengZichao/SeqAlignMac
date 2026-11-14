//  MinimalTheme.swift
//  SeqAlignMac — 设计令牌（Radix UI Colors 语义层）
//
//  设计定位：实验室仪器式的克制界面。编辑部式的水平分隔线、单一色调的层级、
//  清晰的字号阶梯；装饰性圆角与阴影一律不出现，只在浮层留一层极浅的投影。
//
//  颜色全部取自 Radix UI Colors（gray / blue / green / amber / red），并遵循其
//  1–12 步的使用规范：
//    1  应用背景            2  次级背景（分区带）
//    3  UI 元素背景         4  悬停态
//    5  选中 / 激活态       6  细边框与分隔线
//    7  元素边框 / 焦点环   8  悬停边框
//    9  实心底色           10  实心底色悬停
//   11  低对比文字         12  高对比文字
//  文字只使用 11 / 12 两步，保证任何字号都满足对比度要求；层级差异靠字号、
//  字重与间距表达，而不是把文字调浅到读不清。
//
//  其余规则：字号仅 12 / 13 / 16 三档；边框一律 0.5pt；圆角仅 4 / 6 / 10 三档，
//  嵌套元素按同心圆计算（外 6 内缩 2 → 内 4）。

import AppKit
import SwiftUI

enum Minimal {
    // MARK: - Radix 色板（sRGB，数值取自 @radix-ui/colors 3.x）

    /// Radix gray（中性灰，全应用唯一的结构色）
    private static let grayLight: [NSColor] = [
        0xFCFCFC, 0xF9F9F9, 0xF0F0F0, 0xE8E8E8, 0xE0E0E0, 0xD9D9D9,
        0xCECECE, 0xBBBBBB, 0x8D8D8D, 0x838383, 0x646464, 0x202020
    ].map(NSColor.hex)

    private static let grayDark: [NSColor] = [
        0x111111, 0x191919, 0x222222, 0x2A2A2A, 0x313131, 0x3A3A3A,
        0x484848, 0x606060, 0x6E6E6E, 0x7B7B7B, 0xB4B4B4, 0xEEEEEE
    ].map(NSColor.hex)

    /// Radix blue（唯一的功能性彩色：搜索命中，以及需要提示“可交互”的焦点态）
    private static let blueLight: [NSColor] = [
        0xFBFDFF, 0xF4FAFF, 0xE6F4FE, 0xD5EFFF, 0xC2E5FF, 0xACD8FC,
        0x8EC8F6, 0x5EB1EF, 0x0090FF, 0x0588F0, 0x0D74CE, 0x113264
    ].map(NSColor.hex)

    private static let blueDark: [NSColor] = [
        0x0D1520, 0x111927, 0x0D2847, 0x003362, 0x004074, 0x104D87,
        0x205D9E, 0x2870BD, 0x0090FF, 0x3B9EFF, 0x70B8FF, 0xC2E6FF
    ].map(NSColor.hex)

    /// Radix green（成功 / 通过）
    private static let greenLight: [NSColor] = [
        0xFBFEFC, 0xF4FBF6, 0xE6F6EB, 0xD6F1DF, 0xC4E8D1, 0xADDDC0,
        0x8ECEA8, 0x5BB98B, 0x30A46C, 0x2B9A66, 0x218358, 0x193B2D
    ].map(NSColor.hex)

    private static let greenDark: [NSColor] = [
        0x0E1512, 0x121B17, 0x132D21, 0x113B29, 0x174933, 0x20573E,
        0x28684A, 0x2F7C57, 0x30A46C, 0x33B074, 0x3DD68C, 0xB1F1CB
    ].map(NSColor.hex)

    /// Radix amber（警示 / 数据完整性提示）
    private static let amberLight: [NSColor] = [
        0xFEFDFB, 0xFEFBE9, 0xFFF7C2, 0xFFEE9C, 0xFBE577, 0xF3D673,
        0xE9C162, 0xE2A336, 0xFFC53D, 0xFFBA18, 0xAB6400, 0x4F3422
    ].map(NSColor.hex)

    private static let amberDark: [NSColor] = [
        0x16120C, 0x1D180F, 0x302008, 0x3F2700, 0x4D3000, 0x5C3D05,
        0x714F19, 0x8F6424, 0xFFC53D, 0xFFD60A, 0xFFCA16, 0xFFE7B3
    ].map(NSColor.hex)

    /// Radix red（错误 / 破坏性操作）
    private static let redLight: [NSColor] = [
        0xFFFCFC, 0xFFF7F7, 0xFEEBEC, 0xFFDBDC, 0xFFCDCE, 0xFDBDBE,
        0xF4A9AA, 0xEB8E90, 0xE5484D, 0xDC3E42, 0xCE2C31, 0x641723
    ].map(NSColor.hex)

    private static let redDark: [NSColor] = [
        0x191111, 0x201314, 0x3B1219, 0x500F1C, 0x611623, 0x72232D,
        0x8C333A, 0xB54548, 0xE5484D, 0xEC5D5E, 0xFF9592, 0xFFD1D9
    ].map(NSColor.hex)

    /// 取色板第 step 步（1…12）
    private static func step(_ light: [NSColor], _ dark: [NSColor], _ step: Int, dark isDark: Bool) -> NSColor {
        let index = max(0, min(11, step - 1))
        return isDark ? dark[index] : light[index]
    }

    // MARK: - 颜色：语义层

    /// 应用背景（gray-1）
    static func surface(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 1, dark: dark)
    }

    /// 分区背景（gray-2）：侧栏、搜索栏、状态栏等结构性“带”
    static func panel(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 2, dark: dark)
    }

    /// 控件底 / 分组底（gray-3）
    static func card(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 3, dark: dark)
    }

    /// 悬停态填充（gray-4）
    static func hover(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 4, dark: dark)
    }

    /// 选中 / 激活态填充（gray-5）
    static func selected(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 5, dark: dark)
    }

    /// 主文字（gray-12）
    static func text(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 12, dark: dark)
    }

    /// 次要文字（gray-11）；第三层级只靠字号与字重区分，不再继续调浅
    static func textMuted(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 11, dark: dark)
    }

    static func textFaint(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 11, dark: dark)
    }

    /// 实心底色（gray-12）：主按钮、激活指示
    static func primary(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 12, dark: dark)
    }

    /// 实心底色上的文字（gray-1）
    static func onPrimary(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 1, dark: dark)
    }

    /// 实心底色悬停（gray-11 更深的一侧不可用，故用 gray-12 叠 8% 反色）
    static func primaryHover(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.86, green: 0.86, blue: 0.86, alpha: 1)
            : NSColor(srgbRed: 0.24, green: 0.24, blue: 0.24, alpha: 1)
    }

    // 兼容旧语义名：强调色不再另设色相，统一为 gray-12
    static func accent(dark: Bool) -> NSColor { primary(dark: dark) }
    static func accentText(dark: Bool) -> NSColor { text(dark: dark) }
    static func accentSoft(dark: Bool) -> NSColor { selected(dark: dark) }

    /// 焦点环（gray-8）
    static func focusRing(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 8, dark: dark)
    }

    // 边框（结构性中性）
    /// 细边框 / 分隔线（gray-6）
    static func border(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 6, dark: dark)
    }

    /// 元素边框强调（gray-7）
    static func borderStrong(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 7, dark: dark)
    }

    /// 0.5pt 细线：Retina 上一物理像素，视觉上不抢内容
    static let hairline: CGFloat = 0.5

    // 灰阶图表（保守度轨道 / 极简残基 / 分布柱）——gray 4/6/8/10/12，深色反向
    static let chart: [(light: NSColor, dark: NSColor)] = [
        (step(grayLight, grayDark, 4, dark: false), step(grayLight, grayDark, 6, dark: true)),
        (step(grayLight, grayDark, 6, dark: false), step(grayLight, grayDark, 8, dark: true)),
        (step(grayLight, grayDark, 8, dark: false), step(grayLight, grayDark, 10, dark: true)),
        (step(grayLight, grayDark, 10, dark: false), step(grayLight, grayDark, 11, dark: true)),
        (step(grayLight, grayDark, 12, dark: false), step(grayLight, grayDark, 12, dark: true)),
    ]

    static func chartGradient(dark: Bool, index: Int) -> NSColor {
        let idx = max(0, min(4, index))
        return dark ? chart[idx].dark : chart[idx].light
    }

    /// 灰阶取色（identity 0→chart[0]，1→chart[4]）
    static func chartColor(identity: Double, dark: Bool) -> NSColor {
        let clamped = max(0, min(1, identity))
        let idx = min(4, Int((clamped * 4).rounded()))
        return dark ? chart[idx].dark : chart[idx].light
    }

    // 功能色：文字一律取第 11 步（Radix 指定的低对比文字步），实心点取第 9 步
    static func success(dark: Bool) -> NSColor {
        step(greenLight, greenDark, 11, dark: dark)
    }
    static func successSolid(dark: Bool) -> NSColor {
        step(greenLight, greenDark, 9, dark: dark)
    }
    static func destructive(dark: Bool) -> NSColor {
        step(redLight, redDark, 11, dark: dark)
    }
    static func destructiveSolid(dark: Bool) -> NSColor {
        step(redLight, redDark, 9, dark: dark)
    }
    static func warning(dark: Bool) -> NSColor {
        step(amberLight, amberDark, 11, dark: dark)
    }
    static func warningSolid(dark: Bool) -> NSColor {
        step(amberLight, amberDark, 9, dark: dark)
    }
    /// 警示浅底（横幅背景，amber-3）
    static func warningSoft(dark: Bool) -> NSColor {
        step(amberLight, amberDark, 3, dark: dark)
    }
    /// 错误浅底（red-3）
    static func destructiveSoft(dark: Bool) -> NSColor {
        step(redLight, redDark, 3, dark: dark)
    }

    /// 搜索高亮（blue-8，唯一保留的彩色语义）
    static func searchHighlight(dark: Bool) -> NSColor {
        let base = dark
            ? step(blueLight, blueDark, 7, dark: true)
            : step(blueLight, blueDark, 8, dark: false)
        return base.withAlphaComponent(dark ? 0.35 : 0.30)
    }

    // ---- 几何（圆角仅 4 / 6 / 10 三档）----
    /// 嵌套控件（外框 6 内缩 2 → 4）
    static let radiusXS: CGFloat = 4
    /// 控件：按钮、输入框、分段控件（唯一常用圆角）
    static let radiusSM: CGFloat = 6
    /// 浮层：加载遮罩 / 弹出面板
    static let radiusMD: CGFloat = 10
    static let radiusLG: CGFloat = 10
    static let space: CGFloat = 4        // 栅格基元

    // ---- 阴影（只有浮层使用，单层极浅投影）----
    struct ShadowSpec {
        let color: NSColor
        let radius: CGFloat
        let offset: CGSize
    }

    /// 浮层投影：y=3、blur=10、黑 8%（深色下 28%）
    static func shadowMD() -> [ShadowSpec] {
        [ShadowSpec(color: NSColor.black.withAlphaComponent(0.08),
                    radius: 10, offset: CGSize(width: 0, height: 3))]
    }

    static func shadowLG() -> [ShadowSpec] { shadowMD() }

    // 兼容旧引用（单层阴影）
    static let shadowColor  = NSColor.black.withAlphaComponent(0.08)
    static let shadowRadius: CGFloat = 10
    static let shadowOffset: CGFloat = 3

    // ---- 字体（系统 SF Pro + 苹方；数据用 SF Mono）----
    /// 数据 / 代码等宽（保持 SF Mono）
    static func mono(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }

    // ---- 控制条底（工具栏 / 搜索栏 / 状态栏）----
    static func controlSurface(dark: Bool) -> NSColor {
        panel(dark: dark)
    }

    /// 空位单元格中性底色（gray-4 半透明，压在任意残基底色上都可辨认）
    static func gapTint(dark: Bool) -> NSColor {
        step(grayLight, grayDark, 4, dark: dark).withAlphaComponent(0.70)
    }

    /// 聚焦变暗遮罩
    static func dimOverlay(dark: Bool) -> NSColor {
        surface(dark: dark).withAlphaComponent(dark ? 0.65 : 0.62)
    }

    /// 导出背景：浅色为纸白；深色沿用 gray-1
    static func exportBackground(dark: Bool) -> NSColor { dark ? surface(dark: true) : .white }
    /// 导出前景：gray-12
    static func exportForeground(dark: Bool) -> NSColor { text(dark: dark) }

    // ---- 间距刻度（4 栅格）----
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    // ---- 字号刻度（仅 12 / 13 / 16 三档；12pt 为最小可用尺寸）----
    /// 12pt：标签、状态栏、辅助说明、分组标题
    static let fontXXS: CGFloat = 12
    static let fontXS2: CGFloat = 12
    static let fontXS:  CGFloat = 12
    /// 13pt：正文、侧栏、按钮
    static let fontSM:  CGFloat = 13
    static let fontBase: CGFloat = 13
    /// 16pt：页面与弹窗标题
    static let fontLG:  CGFloat = 16
    static let fontXL:  CGFloat = 16
    static let font2XL: CGFloat = 16

    // ---- 控件高度（统一按钮 / 输入）----
    static let controlSM: CGFloat = 22   // 分段控件内段
    static let controlH:  CGFloat = 28   // 按钮 / 输入框
    static let controlLG: CGFloat = 36   // 主按钮（空状态）

    // ---- 配色选择器宽度 ----
    static let schemePickerW: CGFloat = 260

    // ---- 分隔线 ----
    static let dividerOpacity: Double = 1.0

    // ---- 禁用态统一透明度 ----
    static let disabledOpacity: Double = 0.4

    // ---- 动效（默认不做动画；确需过渡时 250ms ease-out）----
    static let motionDuration: Double = 0.25

    static var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 唯一允许的过渡曲线。仅在状态切换会丢失位置感时使用（如面板展开）。
    static func smoothTransition<Result>(_ body: () -> Result) -> Result {
        if shouldReduceMotion {
            return body()
        }
        return withAnimation(.easeOut(duration: motionDuration), body)
    }
}

// MARK: - NSColor 十六进制构造

extension NSColor {
    /// 0xRRGGBB → sRGB 颜色（不依赖显示器色彩空间，保证 Radix 数值精确）
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
                green: CGFloat((value >> 8) & 0xFF) / 255.0,
                blue: CGFloat(value & 0xFF) / 255.0,
                alpha: 1.0)
    }
}

// MARK: - 统一深色判定
//
// 统一深色判定入口：不要散落混用 `NSApp.effectiveAppearance.name == .darkAqua`
// 与 `bestMatch(...)`。前者在「辅助功能 ▸ 显示 ▸ 提高对比度」下
// （NSAppearance.Name 为 .accessibilityHighContrastDarkAqua）误判为浅色，
// 导致同一窗口内明暗判定自相矛盾。统一走 bestMatch。
extension NSAppearance {
    /// 当前生效外观是否为深色（兼容 accessibilityHighContrast* 等派生外观）。
    static var isDarkNow: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    /// 指定外观实例的深色判定。
    func isDark() -> Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
