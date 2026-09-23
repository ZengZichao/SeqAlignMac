//  ColorLogic.swift
//  SeqAlignMac — 配色索引纯逻辑层（领域/渲染解耦 + 单一事实来源去重）
//
//  本文件只包含「残基字节 → 配色类别索引」与「视口索引矩阵」的纯计算，
//  不依赖 AppKit / SwiftUI，因此可以被 SwiftPM 核心库（SeqAlignCore）编译，
//  并由单元测试直接覆盖。NSColor 映射（索引 → 实际颜色）留在 ColorSchemes.swift
//  的 ColorResolver 中，作为渲染层。两套代码通过本文件的单一事实来源保持一致。

import Foundation

// MARK: - 配色索引计算（单一事实来源）

enum ColorComputer {
    /// 只对蛋白比对有意义的配色方案（按氨基酸理化基团分组）。
    /// 这三个方案只按蛋白理化类别分组，若套用到核酸比对会得到
    /// "A=疏水红、T=不着色"的荒谬图例，而 ColorSchemes 的图例只写蛋白类别，
    /// 用户无从察觉。因此核酸比对上它们一律回退到核酸默认轨道（索引 0–7 的碱基语义），
    /// 图例同步换词（见 ColorSchemes.legendEntries）。
    static func isProteinOnlyScheme(_ scheme: ColorScheme) -> Bool {
        switch scheme {
        case .clustalX, .zappo, .seaView: return true
        case .minimal, .defaultNucleotide, .transitionTransversion, .okabeIto: return false
        }
    }

    /// 依数据类型把"蛋白专用"方案折算为该数据下真正有效的方案。
    /// 核酸比对 + 蛋白方案 → .defaultNucleotide；其余原样返回。
    static func effectiveScheme(_ scheme: ColorScheme, datatype: Datatype) -> ColorScheme {
        if datatype == .nucleicAcid && isProteinOnlyScheme(scheme) { return .defaultNucleotide }
        if datatype == .aminoAcid && scheme == .transitionTransversion {
            // 转换/颠换只对核酸成立；蛋白比对退回核酸默认轨道同样无意义 → 用极简保守度
            return .minimal
        }
        return scheme
    }

    /// 残基 → 配色类别索引（单一事实来源）。
    /// 画布（computeViewport）与导出（ExportManager.computeColorIndex）统一调用本函数，
    /// 杜绝两套映射漂移。
    static func colorIndex(for b: UInt8, scheme: ColorScheme, datatype: Datatype = .aminoAcid) -> UInt8 {
        switch effectiveScheme(scheme, datatype: datatype) {
        case .minimal: return ResidueAlphabet.isGap(b) ? 0 : 3  // 单字节场景无法获得列一致度，非 Gap 取中性灰兜底
        case .defaultNucleotide: return residueToDefaultIndex(b)
        case .clustalX: return residueToClustalXIndex(b)
        case .zappo: return residueToZappoIndex(b)
        case .seaView: return residueToSeaViewIndex(b)
        case .transitionTransversion: return residueToDefaultIndex(b)  // Ti/Tv 方案用与 Default 相同的索引
        case .okabeIto: return residueToDefaultIndex(b)               // Okabe-Ito 用相同索引，仅色板不同
        }
    }

    /// ClustalX 保守度阈值（可由界面调整，持久化到 UserDefaults）。
    /// 图例文案由 `clustalXLegendText(threshold:)` 依当前阈值生成，
    /// 保证文案数值与本默认值始终一致、不漂移。
    static let clustalXThresholdDefault: Double = 0.3
    static var clustalXThreshold: Double {
        get {
            let v = UserDefaults.standard.double(forKey: "SeqAlignMac.clustalXThreshold")
            return v > 0 ? v : clustalXThresholdDefault
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "SeqAlignMac.clustalXThreshold")
        }
    }

    /// 供图例使用的一句话（数值随阈值变化，杜绝文案/实现矛盾）。
    static func clustalXLegendText(threshold: Double? = nil) -> String {
        let t = threshold ?? clustalXThresholdDefault
        let percent = Int((t * 100).rounded())
        return "Conserved columns (identity ≥ \(percent)%) are coloured by residue property; columns below \(percent)% are left uncoloured."
    }

    /// 依数据类型给出 ClustalX 图例（核酸比对不再展示蛋白理化类别）。
    static func clustalXLegendText(threshold: Double? = nil, datatype: Datatype) -> String {
        guard datatype == .nucleicAcid else { return clustalXLegendText(threshold: threshold) }
        let t = threshold ?? clustalXThresholdDefault
        let percent = Int((t * 100).rounded())
        return "Nucleotide alignment: the protein property groups of ClustalX / Zappo / SeaView do not apply, so bases are coloured with the nucleotide track. Conserved columns (identity ≥ \(percent)%)."
    }

    /// 计算视口范围的颜色索引矩阵
    /// 返回 row_count * col_count 的 u8 数组（行主序），0=背景
    static func computeViewport(_ alignment: Alignment, scheme: ColorScheme,
                                rowStart: Int, rowCount: Int,
                                colStart: Int, colCount: Int,
                                identities precomputed: [Double]? = nil,
                                clustalXThresholdOverride: Double? = nil) -> [UInt8] {
        let rCount = max(0, rowCount)
        let cCount = max(0, colCount)
        var matrix = [UInt8](repeating: 0, count: rCount * cCount)

        guard rCount > 0 && cCount > 0 else { return matrix }
        let alignLen = alignment.length
        // 按数据类型折算实际生效的方案（核酸比对上的蛋白理化方案回退到核酸轨道）
        let scheme = effectiveScheme(scheme, datatype: alignment.datatype)

        // 列一致度（单一来源：AlignmentStatsCalculator）。仅 minimal/clustalX 需要；
        // 调用方（画布 ensureStats / 导出）有按 revision 缓存的 identity 时必须传入，
        // 否则每帧绘制都会对整个比对做 O(rows×cols) 全量重算 —— 大文件卡顿的根源。
        let identities: [Double]
        switch scheme {
        case .minimal, .clustalX:
            identities = precomputed ?? AlignmentStatsCalculator.columnIdentities(alignment)
        default:
            identities = []
        }

        switch scheme {
        case .minimal:
            // 极简：不按碱基上色，仅按列保守度映射灰阶索引 1–5（identity 0→1，1.0→5），Gap=0
            for c in 0..<cCount {
                let col = colStart + c
                guard col < alignLen else { continue }
                let identity = (col < identities.count) ? identities[col] : 0
                let idx = UInt8(max(1, min(5, Int((identity * 4).rounded()) + 1)))
                for r in 0..<rCount {
                    let row = rowStart + r
                    guard row < alignment.seqCount else { continue }
                    let seq = alignment.sequences[row]
                    guard col < seq.residues.count else { continue }
                    matrix[r * cCount + c] = ResidueAlphabet.isGap(seq.residues[col]) ? 0 : idx
                }
            }
        case .defaultNucleotide, .zappo, .seaView, .transitionTransversion, .okabeIto:
            for r in 0..<rCount {
                let row = rowStart + r
                guard row < alignment.seqCount else { continue }
                let seq = alignment.sequences[row]
                for c in 0..<cCount {
                    let col = colStart + c
                    guard col < alignLen && col < seq.residues.count else { continue }
                    matrix[r * cCount + c] = colorIndex(for: seq.residues[col], scheme: scheme)
                }
            }
        case .clustalX:
            // ClustalX：仅在「保守列」按理化类别上色；低一致度列不着色（中性白底）。
            // 列一致度 = 主频次残基占比；阈值可由界面调整（默认 0.3）。
            // 阈值可注入（单测不受全局 UserDefaults 漂移影响），默认读用户偏好
            let threshold = clustalXThresholdOverride ?? clustalXThreshold
            for c in 0..<cCount {
                let col = colStart + c
                guard col < alignLen else { continue }
                let identity = (col < identities.count) ? identities[col] : 0
                let colored = identity >= threshold
                for r in 0..<rCount {
                    let row = rowStart + r
                    guard row < alignment.seqCount else { continue }
                    let seq = alignment.sequences[row]
                    guard col < seq.residues.count else { continue }
                    let res = seq.residues[col]
                    // 低一致度列：索引 7（ClustalX「其他/白底」），即不着色
                    matrix[r * cCount + c] = colored ? colorIndex(for: res, scheme: .clustalX) : 7
                }
            }
        }
        return matrix
    }

    // Default Nucleotide 索引
    private static func residueToDefaultIndex(_ b: UInt8) -> UInt8 {
        switch b {
        case 0x41: return 1 // A
        case 0x43: return 2 // C
        case 0x47: return 3 // G
        case 0x54, 0x55: return 4 // T/U
        case 0x4E: return 5 // N
        case 0x2D, 0x2E, 0x7E: return 6 // Gap（'-' 及空位写法 '.' '~'）
        default:
            // IUPAC 简并码 R/Y/S/W/K/M/B/D/H/V
            if [0x52, 0x59, 0x53, 0x57, 0x4B, 0x4D, 0x42, 0x44, 0x48, 0x56].contains(b) {
                return 7
            }
            return 7 // 其他
        }
    }

    // ClustalX 索引
    private static func residueToClustalXIndex(_ b: UInt8) -> UInt8 {
        switch b {
        case 0x41, 0x56, 0x4C, 0x49, 0x4D, 0x46, 0x57: return 1 // AVLIMFW
        case 0x4B, 0x52, 0x48: return 2 // KRH
        case 0x44, 0x45: return 3 // DE
        case 0x4E, 0x51, 0x53, 0x54: return 4 // NQST
        case 0x43, 0x47, 0x50: return 5 // CGP
        case 0x59: return 6 // Y
        case 0x2D, 0x2E, 0x7E: return 0 // Gap（含空位写法 '.' '~'）
        default: return 7 // 其他
        }
    }

    // Zappo 索引
    private static func residueToZappoIndex(_ b: UInt8) -> UInt8 {
        switch b {
        case 0x41, 0x56, 0x4C, 0x49, 0x4D, 0x43: return 1 // AVLIMC
        case 0x46, 0x57, 0x59: return 2 // FWY
        case 0x4B, 0x52, 0x48: return 3 // KRH
        case 0x44, 0x45: return 4 // DE
        case 0x53, 0x54, 0x4E, 0x51: return 5 // STNQ
        case 0x47, 0x50: return 6 // GP
        case 0x2D, 0x2E, 0x7E: return 0 // Gap（含空位写法 '.' '~'）
        default: return 7 // 其他
        }
    }

    // SeaView 索引
    private static func residueToSeaViewIndex(_ b: UInt8) -> UInt8 {
        switch b {
        case 0x41, 0x49, 0x4C, 0x4D, 0x56, 0x46, 0x57, 0x43: return 1 // AILMVFWC
        case 0x4B, 0x52: return 2 // KR
        case 0x53, 0x54, 0x4E, 0x44, 0x45, 0x51, 0x47, 0x50: return 3 // STNDEQGP
        case 0x48, 0x59: return 4 // HY
        case 0x2D, 0x2E, 0x7E: return 0 // Gap（含空位写法 '.' '~'）
        default: return 7 // 其他
        }
    }
}
