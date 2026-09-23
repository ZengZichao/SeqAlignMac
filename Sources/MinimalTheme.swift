//  MinimalTheme.swift
//  SeqAlignMac — 设计令牌（中性灰极简）
//
//  依据 落地。所有界面只消费本结构中的语义变量，
//  禁止在视图层散落硬编码色值。双主题通过 effectiveAppearance / AppearanceManager
//  切换：语义函数接收 dark 参数，浅色 / 深色各返回一套。

import AppKit
import SwiftUI

enum Minimal {
    // ---- 颜色：语义层（浅色 / 深色）----
    /// 表面（窗口 / 弹窗底）
    static func surface(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.094, green: 0.094, blue: 0.105, alpha: 1)  // #18181b
             : .white
    }
    /// 卡片（hover 填充 / 分组卡）
    /// 浅色需与 controlSurface(#f7f7f8) 拉开可感知差 → #f1f1f2
    static func card(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.153, green: 0.153, blue: 0.165, alpha: 1)  // #27272a
             : NSColor(calibratedRed: 0.945, green: 0.945, blue: 0.949, alpha: 1)  // #f1f1f2（悬停）
    }
    /// 主文字
    static func text(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.980, green: 0.980, blue: 0.980, alpha: 1)  // #fafafa
             : NSColor(calibratedRed: 0.094, green: 0.094, blue: 0.105, alpha: 1)  // #18181b
    }
    /// 次要文字
    static func textMuted(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.631, green: 0.631, blue: 0.651, alpha: 1)  // #a1a1aa
             : NSColor(calibratedRed: 0.443, green: 0.443, blue: 0.459, alpha: 1)  // #71717a
    }
    /// 主色（近黑）——替代原青色，用于选区 / 激活 / 强调 / 主按钮
    static func primary(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.980, green: 0.980, blue: 0.980, alpha: 1)
             : NSColor(calibratedRed: 0.094, green: 0.094, blue: 0.105, alpha: 1)
    }
    /// 强调色：改用 primary 系（近黑/近白），不再使用蓝色
    static func accent(dark: Bool) -> NSColor {
        primary(dark: dark)
    }
    /// 强调色浅底（选中态背景）
    /// 浅色：选中比悬停再深一档 → #e7e7e9（hierarchy: controlSurface > card(#f1f1f2) > accentSoft(#e7e7e9)）
    static func accentSoft(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.153, green: 0.153, blue: 0.165, alpha: 1)  // #27272a (card)
             : NSColor(calibratedRed: 0.906, green: 0.906, blue: 0.914, alpha: 1)  // #e7e7e9（选中）
    }
    /// 强调色文字：与 text 一致
    static func accentText(dark: Bool) -> NSColor {
        text(dark: dark)
    }
    /// 搜索高亮专用色（唯一蓝色例外，仅限画布搜索命中标记，）
    static func searchHighlight(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.376, green: 0.647, blue: 0.980, alpha: 0.25)
             : NSColor(calibratedRed: 0.098, green: 0.463, blue: 0.824, alpha: 0.18)
    }

    // 边框（结构性中性）
    static func border(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.247, green: 0.247, blue: 0.275, alpha: 1)  // #3f3f46
             : NSColor(calibratedRed: 0.894, green: 0.894, blue: 0.906, alpha: 1)  // #e4e4e7
    }
    static func borderStrong(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.322, green: 0.322, blue: 0.357, alpha: 1)  // #52525b
             : NSColor(calibratedRed: 0.831, green: 0.831, blue: 0.847, alpha: 1)  // #d4d4d8
    }

    // 单色灰阶（图表 / 保守度轨道 / 极简残基）——浅色 200→900，深色翻转
    static let chart: [(light: NSColor, dark: NSColor)] = [
        (NSColor(calibratedRed: 0.894, green: 0.894, blue: 0.906, alpha: 1),
         NSColor(calibratedRed: 0.247, green: 0.247, blue: 0.275, alpha: 1)), // chart-1
        (NSColor(calibratedRed: 0.631, green: 0.631, blue: 0.651, alpha: 1),
         NSColor(calibratedRed: 0.631, green: 0.631, blue: 0.651, alpha: 1)), // chart-2
        (NSColor(calibratedRed: 0.322, green: 0.322, blue: 0.357, alpha: 1),
         NSColor(calibratedRed: 0.831, green: 0.831, blue: 0.847, alpha: 1)), // chart-3
        (NSColor(calibratedRed: 0.153, green: 0.153, blue: 0.165, alpha: 1),
         NSColor(calibratedRed: 0.894, green: 0.894, blue: 0.906, alpha: 1)), // chart-4
        (NSColor(calibratedRed: 0.094, green: 0.094, blue: 0.105, alpha: 1),
         NSColor(calibratedRed: 0.980, green: 0.980, blue: 0.980, alpha: 1)), // chart-5
    ]

    /// 渐变图表色（保守度分布柱状图）——改为灰阶，与 Minimal.chart 一致
    static func chartGradient(dark: Bool, index: Int) -> NSColor {
        let colors = dark ? [
            NSColor(calibratedRed: 0.247, green: 0.247, blue: 0.275, alpha: 1),  // chart-1 dark
            NSColor(calibratedRed: 0.443, green: 0.443, blue: 0.459, alpha: 1),  // 介于 chart-1/2
            NSColor(calibratedRed: 0.631, green: 0.631, blue: 0.651, alpha: 1),  // chart-2
            NSColor(calibratedRed: 0.831, green: 0.831, blue: 0.847, alpha: 1),  // chart-3 dark
            NSColor(calibratedRed: 0.980, green: 0.980, blue: 0.980, alpha: 1),  // chart-5 dark
        ] : [
            NSColor(calibratedRed: 0.894, green: 0.894, blue: 0.906, alpha: 1),  // chart-1 light
            NSColor(calibratedRed: 0.631, green: 0.631, blue: 0.651, alpha: 1),  // 介于 chart-1/2
            NSColor(calibratedRed: 0.322, green: 0.322, blue: 0.357, alpha: 1),  // chart-3 light
            NSColor(calibratedRed: 0.153, green: 0.153, blue: 0.165, alpha: 1),  // chart-4 light
            NSColor(calibratedRed: 0.094, green: 0.094, blue: 0.105, alpha: 1),  // chart-5 light
        ]
        return colors[max(0, min(4, index))]
    }

    /// 灰阶取色（identity 0→chart[0]，1→chart[4]）
    static func chartColor(identity: Double, dark: Bool) -> NSColor {
        let clamped = max(0, min(1, identity))
        let idx = min(4, Int((clamped * 4).rounded()))
        return dark ? chart[idx].dark : chart[idx].light
    }

    // 功能色（仅保留，非装饰）——随主题变化，深色下提亮以满足 WCAG AA
    static func success(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.290, green: 0.800, blue: 0.443, alpha: 1)  // #4acc71
             : NSColor(calibratedRed: 0.086, green: 0.639, blue: 0.290, alpha: 1)  // #16a34a
    }
    static func destructive(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.980, green: 0.400, blue: 0.400, alpha: 1)  // #fa6666
             : NSColor(calibratedRed: 0.863, green: 0.149, blue: 0.149, alpha: 1)  // #dc2626
    }
    /// 警示色（Toast warning / 引物风险标记等）——随主题变化
    static func warning(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.984, green: 0.729, blue: 0.196, alpha: 1)  // #fbba32
             : NSColor(calibratedRed: 0.851, green: 0.545, blue: 0.067, alpha: 1)  // #d98b11
    }

    // ---- 几何（圆角仅 4 / 6 / 12 / 16 四档；间距 4 栅格）----
    static let radiusXS: CGFloat = 4     // 极小控件（关闭按钮 / 色块标记，）
    static let radiusSM: CGFloat = 6     // 小控件（工具栏按钮、输入框）
    static let radiusMD: CGFloat = 12    // 卡片 / 表单 / 弹窗（基础）
    static let radiusLG: CGFloat = 16    // 大容器（如有）
    static let space: CGFloat = 4        // 栅格基元

    // ---- 阴影（多层分层体系，）----
    // 零消费的 shadow2xs / shadowXS / shadowSM 已删除；
    // shadowMD（卡片/覆盖层）与 shadowLG（弹窗容器）保留并被消费
    struct ShadowSpec {
        let color: NSColor
        let radius: CGFloat
        let offset: CGSize
    }

    static func shadowMD() -> [ShadowSpec] {
        [
            ShadowSpec(color: NSColor.black.withAlphaComponent(0.07),
                       radius: 8, offset: CGSize(width: 0, height: 4)),
            ShadowSpec(color: NSColor.black.withAlphaComponent(0.04),
                       radius: 4, offset: CGSize(width: 0, height: 2)),
        ]
    }

    static func shadowLG() -> [ShadowSpec] {
        [
            ShadowSpec(color: NSColor.black.withAlphaComponent(0.08),
                       radius: 20, offset: CGSize(width: 0, height: 12)),
            ShadowSpec(color: NSColor.black.withAlphaComponent(0.04),
                       radius: 8, offset: CGSize(width: 0, height: 4)),
        ]
    }

    // 兼容旧引用（单层阴影）
    static let shadowColor  = NSColor.black.withAlphaComponent(0.07)
    static let shadowRadius: CGFloat = 8
    static let shadowOffset: CGFloat = 4   // y 方向

    // ---- 字体（设计系统指定 Geist，但 macOS 原生应用优先使用 SF Pro：
    //   1. SF Pro 在 Retina 上渲染清晰度优于 Geist
    //   2. 中文回退到苹方（PingFang SC），与系统一致
    //   3. 无需嵌入字体文件，减小应用体积
    //   等宽字体使用 SF Mono，与 Geist Mono 度量接近）
    // ui/uiMed/uiSemi 三个零消费令牌已删除
    /// 数据 / 代码等宽（保持 SF Mono）
    static func mono(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }

    // ---- 控制条底（工具栏 / 搜索栏 / 状态栏）——略深/略浅于 surface 形成「带」----
    // 深色值调整为 #27272a（与 card 一致），与 surface(#18181b) 有约 6% 亮度差
    static func controlSurface(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.153, green: 0.153, blue: 0.165, alpha: 1) // #27272a（与 card 一致）
             : NSColor(calibratedRed: 0.969, green: 0.969, blue: 0.971, alpha: 1) // #f7f7f7
    }
    /// 三级弱化文字（行号等）——满足 WCAG AA ≥4.5:1（浅色 #6b6b74≈4.6:1，深色 #8b8b94≈4.9:1）
    static func textFaint(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.545, green: 0.545, blue: 0.580, alpha: 1) // #8b8b94
             : NSColor(calibratedRed: 0.420, green: 0.420, blue: 0.455, alpha: 1) // #6b6b74
    }
    /// 空位单元格中性底色（统一透明度为 0.16）
    static func gapTint(dark: Bool) -> NSColor {
        border(dark: dark).withAlphaComponent(0.16)
    }
    /// 聚焦变暗遮罩（深色模式提高到 0.65）
    static func dimOverlay(dark: Bool) -> NSColor {
        surface(dark: dark).withAlphaComponent(dark ? 0.65 : 0.62)
    }
    /// 导出背景：浅色 = 白；深色可扩展为 surface
    static func exportBackground(dark: Bool) -> NSColor { dark ? surface(dark: true) : .white }
    /// 导出前景：近黑字（text）
    static func exportForeground(dark: Bool) -> NSColor { text(dark: dark) }

    // ---- 间距刻度（4 栅格，统一 G5 魔法数字）----
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    // ---- 字号刻度（补充缺失字号令牌）----
    static let fontXXS: CGFloat = 9    // 分组标题 / 极小标注
    static let fontXS2: CGFloat = 10   // 统计面板标签 / 提示
    static let fontXS:  CGFloat = 11   // 状态栏 / 辅助文字
    static let fontSM:  CGFloat = 12   // 按钮文字 / 侧栏文字
    static let fontBase:CGFloat = 13   // 正文 / 标题
    static let fontLG:  CGFloat = 14   // 大按钮 / 命令面板
    static let fontXL:  CGFloat = 16   // 弹窗标题
    static let font2XL: CGFloat = 20   // 空状态标题

    // ---- 控件高度（统一按钮 / 输入）----
    static let controlSM: CGFloat = 22   // pill / 紧凑型控件
    static let controlH:  CGFloat = 28   // ToolbarButton 现行 minHeight
    static let controlLG: CGFloat = 36   // .controlSize(.large) 主按钮

    // ---- 配色选择器宽度（268 魔法数字沉淀）----
    static let schemePickerW: CGFloat = 268

    // ---- 分隔线透明度（结构性弱化）----
    static let dividerOpacity: Double = 0.6

    // ---- 禁用态统一透明度----
    static let disabledOpacity: Double = 0.4

    // ---- 减弱动效全局封装（G7 + 统一动效封装）----
    static var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 统一动效封装：减弱动效时无动画，否则 easeOut 0.2s
    static func smoothTransition<Result>(_ body: () -> Result) -> Result {
        if shouldReduceMotion {
            return body()
        } else {
            return withAnimation(.easeOut(duration: 0.2), body)
        }
    }
}

// MARK: - 统一深色判定
//
// 统一深色判定入口：不要散落混用 `NSApp.effectiveAppearance.name == .darkAqua`（此前 14 处）与
// `bestMatch(...)`（2 处）。前者在「辅助功能 ▸ 显示 ▸ 提高对比度」下
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
