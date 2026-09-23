//  ColorSchemes.swift
//  SeqAlignMac — 配色映射（视口式，依据附录 A 标准色板）
//  依据  / 附录 A 实现
//
//  渲染层：索引 → 实际 NSColor 映射。纯「残基字节 → 类别索引」逻辑已抽到
//  SeqAlignCore 的 ColorComputer（见 ColorLogic.swift，Foundation-only、可单测），
//  本文件只负责把索引换成屏幕上真实的颜色（领域/渲染解耦）。

import AppKit

// MARK: - 颜色索引 → RGB 映射

struct ColorPalette {
    let fg: NSColor
    let bg: NSColor

    init(fgHex: UInt32, bgHex: UInt32) {
        self.fg = NSColor(red: CGFloat((fgHex >> 16) & 0xFF) / 255.0,
                          green: CGFloat((fgHex >> 8) & 0xFF) / 255.0,
                          blue: CGFloat(fgHex & 0xFF) / 255.0,
                          alpha: 1.0)
        self.bg = NSColor(red: CGFloat((bgHex >> 16) & 0xFF) / 255.0,
                          green: CGFloat((bgHex >> 8) & 0xFF) / 255.0,
                          blue: CGFloat(bgHex & 0xFF) / 255.0,
                          alpha: 1.0)
    }

    /// 直接以 NSColor 构造（用于透明确认色 / 深色变体复用）
    init(fgColor: NSColor, bgColor: NSColor) {
        self.fg = fgColor
        self.bg = bgColor
    }
}

enum ColorPalettes {
    // A.1 Default Nucleotide
    static let defaultNucleotide: [Int: ColorPalette] = [
        0: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFFFF), // 背景
        1: ColorPalette(fgHex: 0x000000, bgHex: 0xC8E6C9), // A 浅绿
        2: ColorPalette(fgHex: 0x000000, bgHex: 0xBBDEFB), // C 浅蓝
        3: ColorPalette(fgHex: 0x000000, bgHex: 0xFFE0B2), // G 浅橙
        4: ColorPalette(fgHex: 0x000000, bgHex: 0xFFCDD2), // T/U 浅红
        5: ColorPalette(fgHex: 0x000000, bgHex: 0xE0E0E0), // N 灰
        6: ColorPalette(fgHex: 0x9E9E9E, bgHex: 0xFFFFFF), // Gap
        7: ColorPalette(fgHex: 0x000000, bgHex: 0xF3E5F5), // IUPAC 简并
    ]

    // A.1b Default Nucleotide 深色变体（Manifest ）
    // 保持色相身份：深底 + 亮前景，避免在深色界面上整体发灰消失。
    // 索引 0（背景）设为透明确认色，让语义底透出，不再回填白色块。
    static let defaultNucleotideDark: [Int: ColorPalette] = [
        0: ColorPalette(fgColor: .labelColor, bgColor: .clear),               // 背景（透出语义底）
        1: ColorPalette(fgHex: 0xA8E6B8, bgHex: 0x1E3A2A), // A
        2: ColorPalette(fgHex: 0xA9D4FF, bgHex: 0x1C3252), // C
        3: ColorPalette(fgHex: 0xFFD28A, bgHex: 0x3E2F15), // G
        4: ColorPalette(fgHex: 0xFFB3B8, bgHex: 0x3A2026), // T/U
        5: ColorPalette(fgHex: 0xC8CDD3, bgHex: 0x2A2E33), // N
        6: ColorPalette(fgHex: 0x6B7686, bgHex: 0x10151E), // Gap
        7: ColorPalette(fgHex: 0xE0B8F0, bgHex: 0x2E2336), // IUPAC 简并
    ]

    // A.2 ClustalX
    static let clustalX: [Int: ColorPalette] = [
        0: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFFFF),
        1: ColorPalette(fgHex: 0x000000, bgHex: 0xFF5050), // 疏水/脂肪族 AVLIMFW
        2: ColorPalette(fgHex: 0x000000, bgHex: 0x5050FF), // 碱性 KRH
        3: ColorPalette(fgHex: 0x000000, bgHex: 0xFF50FF), // 酸性 DE
        4: ColorPalette(fgHex: 0x000000, bgHex: 0x50FF50), // 极性 NQST
        5: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFF50), // 特殊/小 CGP
        6: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFF50), // 芳香 Y
        7: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFFFF), // 其他
    ]

    // A.3 Zappo
    static let zappo: [Int: ColorPalette] = [
        0: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFFFF),
        1: ColorPalette(fgHex: 0x000000, bgHex: 0x50C050), // 脂肪族 AVLIMC
        2: ColorPalette(fgHex: 0x000000, bgHex: 0x5050FF), // 芳香 FWY
        3: ColorPalette(fgHex: 0x000000, bgHex: 0xFF5050), // 正电 KRH
        4: ColorPalette(fgHex: 0x000000, bgHex: 0xFF50FF), // 负电 DE
        5: ColorPalette(fgHex: 0x000000, bgHex: 0x50C8C8), // 极性 STNQ
        6: ColorPalette(fgHex: 0x000000, bgHex: 0xFFA050), // 小/特殊 GP
        7: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFFFF), // 其他
    ]

    // A.4 SeaView
    static let seaView: [Int: ColorPalette] = [
        0: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFFFF),
        1: ColorPalette(fgHex: 0x000000, bgHex: 0xFF0000), // 疏水/埋藏 AILMVFWC
        2: ColorPalette(fgHex: 0x000000, bgHex: 0x0000FF), // 碱性 KR
        3: ColorPalette(fgHex: 0x000000, bgHex: 0x00C000), // 小/极性/酸性 STNDEQGP
        4: ColorPalette(fgHex: 0x000000, bgHex: 0xC000C0), // 芳香/碱性 HY
        7: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFFFF), // 其他
    ]

    // A.5 Transition/Transversion (Ti/Tv) — 嘌呤(A,G)用蓝系，嘧啶(C,T)用红系
    // 转换(A↔G, C↔T)同色系内变化，颠换(A↔C, A↔T, G↔C, G↔T)跨色系变化，一目了然
    static let transitionTransversion: [Int: ColorPalette] = [
        0: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFFFF),
        1: ColorPalette(fgHex: 0x000000, bgHex: 0x6BAED6), // A 嘌呤 蓝
        2: ColorPalette(fgHex: 0x000000, bgHex: 0xFD8D3C), // C 嘧啶 橙
        3: ColorPalette(fgHex: 0x000000, bgHex: 0x2171B5), // G 嘌呤 深蓝
        4: ColorPalette(fgHex: 0x000000, bgHex: 0xE6550D), // T/U 嘧啶 深橙
        5: ColorPalette(fgHex: 0x000000, bgHex: 0xE0E0E0), // N 灰
        6: ColorPalette(fgHex: 0x9E9E9E, bgHex: 0xFFFFFF), // Gap
        7: ColorPalette(fgHex: 0x000000, bgHex: 0xF3E5F5), // IUPAC 简并
    ]

    // A.5b Ti/Tv 深色变体
    static let transitionTransversionDark: [Int: ColorPalette] = [
        0: ColorPalette(fgColor: .labelColor, bgColor: .clear),
        1: ColorPalette(fgHex: 0x6BAED6, bgHex: 0x1A3A5C), // A
        2: ColorPalette(fgHex: 0xFD8D3C, bgHex: 0x3A2510), // C
        3: ColorPalette(fgHex: 0x4292C6, bgHex: 0x0D2845), // G
        4: ColorPalette(fgHex: 0xE6550D, bgHex: 0x2E1808), // T/U
        5: ColorPalette(fgHex: 0xC8CDD3, bgHex: 0x2A2E33), // N
        6: ColorPalette(fgHex: 0x6B7686, bgHex: 0x10151E), // Gap
        7: ColorPalette(fgHex: 0xE0B8F0, bgHex: 0x2E2336), // IUPAC
    ]

    // A.0 Minimal（极简 · 应用默认）——不按碱基上色，仅按列保守度映射灰阶底纹。
    // 底纹为 Minimal.chart 对应灰阶的低透明度（0.18），文字用近黑/近白纯文本；
    // Gap 索引 0 为透明（画布对空位单独走中性底 + 下划线路径）。
    static let minimalLight: [Int: ColorPalette] = makeMinimal(dark: false)
    static let minimalDark:  [Int: ColorPalette] = makeMinimal(dark: true)

    private static func makeMinimal(dark: Bool) -> [Int: ColorPalette] {
        let fg = Minimal.text(dark: dark)
        var pal: [Int: ColorPalette] = [:]
        pal[0] = ColorPalette(fgColor: .clear, bgColor: .clear) // Gap
        for i in 1...5 {
            let base = dark ? Minimal.chart[i - 1].dark : Minimal.chart[i - 1].light
            pal[i] = ColorPalette(fgColor: fg, bgColor: base.withAlphaComponent(0.18))
        }
        return pal
    }

    // A.6 Okabe-Ito 色觉无障碍色板（Wong 2011, Nature Methods）
    // 全部 8 色对红绿色盲（deuteranopia/protanopia）可区分；此处取 4 碱基 + N/Gap
    static let okabeIto: [Int: ColorPalette] = [
        0: ColorPalette(fgHex: 0x000000, bgHex: 0xFFFFFF),
        1: ColorPalette(fgHex: 0x000000, bgHex: 0xE69F00), // A 橙
        2: ColorPalette(fgHex: 0xFFFFFF, bgHex: 0x009E73), // C 蓝绿
        3: ColorPalette(fgHex: 0xFFFFFF, bgHex: 0x0072B2), // G 蓝
        4: ColorPalette(fgHex: 0x000000, bgHex: 0xD55E00), // T/U 朱红
        5: ColorPalette(fgHex: 0x000000, bgHex: 0xE0E0E0), // N 灰
        6: ColorPalette(fgHex: 0x9E9E9E, bgHex: 0xFFFFFF), // Gap
        7: ColorPalette(fgHex: 0x000000, bgHex: 0xF0E442), // IUPAC 简并 黄
    ]

    // A.6b Okabe-Ito 深色变体（亮字深底）
    static let okabeItoDark: [Int: ColorPalette] = [
        0: ColorPalette(fgColor: .labelColor, bgColor: .clear),
        1: ColorPalette(fgHex: 0xFFB739, bgHex: 0x3A2A0B), // A
        2: ColorPalette(fgHex: 0x4CD9A8, bgHex: 0x0B3327), // C
        3: ColorPalette(fgHex: 0x5BB4E8, bgHex: 0x0B2637), // G
        4: ColorPalette(fgHex: 0xFF9257, bgHex: 0x3A1B08), // T/U
        5: ColorPalette(fgHex: 0xC8CDD3, bgHex: 0x2A2E33), // N
        6: ColorPalette(fgHex: 0x6B7686, bgHex: 0x10151E), // Gap
        7: ColorPalette(fgHex: 0xF6EC6E, bgHex: 0x35310B), // IUPAC
    ]

}

// MARK: - 配色渲染（渲染层）
//  品牌强调色统一由 MinimalTheme.swift（Minimal 令牌）提供，
//  不保留独立的 SeqAlignAccent 青色（#0EA5B7 / #34D2E6），避免散落的强调色调用点。

/// 把「索引」换成屏幕上的真实 NSColor。纯索引计算见 SeqAlignCore.ColorComputer。
enum ColorResolver {
    /// 根据配色方案和索引获取颜色
    /// - Parameter dark: 是否使用深色外观下的数据色板（仅 defaultNucleotide 提供深色变体，
    ///   ClustalX/Zappo/SeaView 为分类饱和色，深浅外观下保持同一套以保证科研可比性）。
    static func palette(_ scheme: ColorScheme, index: Int, dark: Bool = false) -> ColorPalette {
        switch scheme {
        case .minimal:
            return dark ? (ColorPalettes.minimalDark[index] ?? ColorPalettes.minimalDark[0]!)
                        : (ColorPalettes.minimalLight[index] ?? ColorPalettes.minimalLight[0]!)
        case .defaultNucleotide:
            return dark ? (ColorPalettes.defaultNucleotideDark[index] ?? ColorPalettes.defaultNucleotideDark[0]!)
                        : (ColorPalettes.defaultNucleotide[index] ?? ColorPalettes.defaultNucleotide[0]!)
        case .clustalX: return ColorPalettes.clustalX[index] ?? ColorPalettes.clustalX[0]!
        case .zappo: return ColorPalettes.zappo[index] ?? ColorPalettes.zappo[0]!
        case .seaView: return ColorPalettes.seaView[index] ?? ColorPalettes.seaView[0]!
        case .transitionTransversion:
            return dark ? (ColorPalettes.transitionTransversionDark[index] ?? ColorPalettes.transitionTransversionDark[0]!)
                        : (ColorPalettes.transitionTransversion[index] ?? ColorPalettes.transitionTransversion[0]!)
        case .okabeIto:
            return dark ? (ColorPalettes.okabeItoDark[index] ?? ColorPalettes.okabeItoDark[0]!)
                        : (ColorPalettes.okabeIto[index] ?? ColorPalettes.okabeIto[0]!)
        }
    }
}

extension ColorResolver {
    /// 序列 Logo 堆叠字母的着色：极简方案（无按碱基色板）借用默认核酸色板
    static func logoColor(_ residue: UInt8, scheme: ColorScheme, dark: Bool) -> NSColor {
        let effective: ColorScheme = scheme == .minimal ? .defaultNucleotide : scheme
        let idx = Int(ColorComputer.colorIndex(for: residue, scheme: effective))
        return palette(effective, index: idx, dark: dark).bg
    }
}

// MARK: - 配色图例（供 UI 图例弹窗使用）

struct LegendEntry {
    let symbol: String
    let color: NSColor
    let note: String
}

enum ColorSchemeLegend {
    /// 返回当前配色方案的图例条目（类别符号 / 颜色 / 说明）
    static func entries(for scheme: ColorScheme, dark: Bool) -> [LegendEntry] {
        let defs: [(String, Int, String)]
        switch scheme {
        case .minimal:
            defs = [
                ("保守", 5, "高保守列（一致度 ≥80%）"),
                ("较保守", 4, "一致度 60–79%"),
                ("中度", 3, "一致度 40–59%"),
                ("低度", 2, "一致度 20–39%"),
                ("多变", 1, "低一致度列（<20%）"),
                ("−", 0, "空位（不着色）"),
            ]
        case .defaultNucleotide:
            defs = [
                ("A", 1, "腺嘌呤"), ("C", 2, "胞嘧啶"), ("G", 3, "鸟嘌呤"),
                ("T/U", 4, "胸腺/尿嘧啶"), ("N", 5, "任意碱基"), ("−", 6, "空位"),
                ("简并", 7, "IUPAC 简并码")
            ]
        case .clustalX:
            defs = [
                ("AVLIMFW", 1, "疏水/脂肪族"), ("KRH", 2, "碱性"), ("DE", 3, "酸性"),
                ("NQST", 4, "极性"), ("CGP", 5, "小/特殊"), ("Y", 6, "芳香"),
                ("其他", 7, ColorComputer.clustalXLegendText())
            ]
        case .zappo:
            defs = [
                ("AVLIMC", 1, "脂肪族"), ("FWY", 2, "芳香"), ("KRH", 3, "正电"),
                ("DE", 4, "负电"), ("STNQ", 5, "极性"), ("GP", 6, "小/特殊"),
                ("其他", 7, "其他")
            ]
        case .seaView:
            defs = [
                ("AILMVFWC", 1, "疏水/埋藏"), ("KR", 2, "碱性"),
                ("STNDEQGP", 3, "小/极性/酸性"), ("HY", 4, "芳香/碱性"),
                ("其他", 7, "其他")
            ]
        case .transitionTransversion:
            defs = [
                ("A", 1, "嘌呤（转换）"), ("G", 3, "嘌呤（转换）"),
                ("C", 2, "嘧啶（转换）"), ("T/U", 4, "嘧啶（转换）"),
                ("N", 5, "任意碱基"), ("−", 6, "空位"),
                ("简并", 7, "IUPAC 简并码")
            ]
        case .okabeIto:
            defs = [
                ("A", 1, "腺嘌呤（橙）"), ("C", 2, "胞嘧啶（蓝绿）"),
                ("G", 3, "鸟嘌呤（蓝）"), ("T/U", 4, "胸腺/尿嘧啶（朱红）"),
                ("N", 5, "任意碱基"), ("−", 6, "空位"),
                ("简并", 7, "IUPAC 简并码（黄）")
            ]
        }
        return defs.map { LegendEntry(symbol: $0.0,
                                      color: ColorResolver.palette(scheme, index: $0.1, dark: dark).bg,
                                      note: $0.2) }
    }
}
