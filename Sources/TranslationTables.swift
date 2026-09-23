//  TranslationTables.swift
//  SeqAlignMac — NCBI 遗传密码表（纯数据，codon→aa）
//  数据来源：NCBI 标准翻译表（公开数据）

import Foundation

// MARK: - 翻译显示模式（四种显示模式）

enum TranslationDisplayMode: Int32 {
    case codonOnly = 0       // 单密码子模式（显示密码子）
    case aminoAcidOnly = 1   // 氨基酸码模式（显示翻译后的氨基酸）
    case both = 2            // 两者模式（同时显示密码子和氨基酸）
    case ignoreGaps = 3      // 忽略空位模式（先移除空位再翻译）
}

enum TranslationTables {
    /// NCBI 标准表 1（标准遗传密码）
    static let standardTable: [String: Character] = {
        var table: [String: Character] = [:]
        // 密码子 → 氨基酸（NCBI Table 1）
        let codonData: [(String, Character)] = [
            // Phe
            ("TTT", "F"), ("TTC", "F"),
            // Leu
            ("TTA", "L"), ("TTG", "L"),
            ("CTT", "L"), ("CTC", "L"), ("CTA", "L"), ("CTG", "L"),
            // Ile
            ("ATT", "I"), ("ATC", "I"), ("ATA", "I"),
            // Met
            ("ATG", "M"),
            // Val
            ("GTT", "V"), ("GTC", "V"), ("GTA", "V"), ("GTG", "V"),
            // Ser
            ("TCT", "S"), ("TCC", "S"), ("TCA", "S"), ("TCG", "S"),
            // Pro
            ("CCT", "P"), ("CCC", "P"), ("CCA", "P"), ("CCG", "P"),
            // Thr
            ("ACT", "T"), ("ACC", "T"), ("ACA", "T"), ("ACG", "T"),
            // Ala
            ("GCT", "A"), ("GCC", "A"), ("GCA", "A"), ("GCG", "A"),
            // Tyr
            ("TAT", "Y"), ("TAC", "Y"),
            // Stop
            ("TAA", "*"), ("TAG", "*"),
            // His
            ("CAT", "H"), ("CAC", "H"),
            // Gln
            ("CAA", "Q"), ("CAG", "Q"),
            // Asn
            ("AAT", "N"), ("AAC", "N"),
            // Lys
            ("AAA", "K"), ("AAG", "K"),
            // Asp
            ("GAT", "D"), ("GAC", "D"),
            // Glu
            ("GAA", "E"), ("GAG", "E"),
            // Cys
            ("TGT", "C"), ("TGC", "C"),
            // Stop / Trp
            ("TGA", "*"), ("TGG", "W"),
            // Arg
            ("CGT", "R"), ("CGC", "R"), ("CGA", "R"), ("CGG", "R"),
            ("AGA", "R"), ("AGG", "R"),
            // Ser
            ("AGT", "S"), ("AGC", "S"),
            // Gly
            ("GGT", "G"), ("GGC", "G"), ("GGA", "G"), ("GGG", "G"),
        ]
        for (codon, aa) in codonData {
            table[codon] = aa
        }
        return table
    }()

    /// NCBI 表 2（脊椎动物线粒体）
    static let vertebrateMitoTable: [String: Character] = {
        var table = standardTable
        table["ATA"] = "M" // Met (not Ile)
        table["TGA"] = "W" // Trp (not Stop)
        table["AGA"] = "*" // Stop (not Arg)
        table["AGG"] = "*" // Stop (not Arg)
        return table
    }()

    /// NCBI 表 3（酵母线粒体）
    /// 官方差异（NCBI gc.prt）：ATA→M；CTT/CTC/CTA/CTG→T；TGA→W（共 6 处偏离）
    static let yeastTable: [String: Character] = {
        var table = standardTable
        table["ATA"] = "M"
        table["CTT"] = "T"
        table["CTC"] = "T"
        table["CTA"] = "T"
        table["CTG"] = "T"
        table["TGA"] = "W"
        return table
    }()

    /// NCBI 表 4（霉菌/原生动物线粒体）
    static let moldProtozoanMitoTable: [String: Character] = {
        var table = standardTable
        table["TGA"] = "W"
        return table
    }()

    /// NCBI 表 5（无脊椎动物线粒体）
    static let invertebrateMitoTable: [String: Character] = {
        var table = standardTable
        table["ATA"] = "M"
        table["TGA"] = "W"
        table["AGA"] = "S"
        table["AGG"] = "S"
        return table
    }()

    /// NCBI 表 6（纤毛虫）
    static let ciliateTable: [String: Character] = {
        var table = standardTable
        table["TAA"] = "Q"
        table["TAG"] = "Q"
        return table
    }()

    /// NCBI 表 9（棘皮动物/扁形动物线粒体）
    /// 官方差异：AAA→N；AGA/AGG→S；TGA→W（ATA 保持 Ile）
    static let echinodermMitoTable: [String: Character] = {
        var table = standardTable
        table["AAA"] = "N"
        table["AGA"] = "S"
        table["AGG"] = "S"
        table["TGA"] = "W"
        return table
    }()

    /// NCBI 表 11（细菌/古菌/植物质体）：密码子→氨基酸赋值与标准表完全相同
    /// （差异仅在起始密码子，不在翻译表本身）
    static let bacterialTable: [String: Character] = {
        standardTable
    }()

    /// NCBI 表 12（替代酵母）
    static let altYeastTable: [String: Character] = {
        var table = standardTable
        table["CTG"] = "S"
        return table
    }()

    /// NCBI 表 13（海鞘线粒体）
    static let ascidianMitoTable: [String: Character] = {
        var table = standardTable
        table["ATA"] = "M"
        table["TGA"] = "W"
        table["AGA"] = "G"
        table["AGG"] = "G"
        return table
    }()

    /// NCBI 表 14（替代扁形动物线粒体）
    /// 官方差异：AAA→N；AGA/AGG→S；TAA→Y；TGA→W（ATA 保持 Ile）
    static let flatwormMitoTable: [String: Character] = {
        var table = standardTable
        table["AAA"] = "N"
        table["AGA"] = "S"
        table["AGG"] = "S"
        table["TAA"] = "Y"
        table["TGA"] = "W"
        return table
    }()

    /// NCBI 表 15（_Blepharisma_ 大核）
    static let blepharismaMitoTable: [String: Character] = {
        var table = standardTable
        table["TAG"] = "Q"
        return table
    }()

    /// NCBI 表 10（Euplotid 核码）：UGA→C（半胱氨酸），UAA/UAG 仍为终止
    static let euplotidTable: [String: Character] = {
        var table = standardTable
        table["TGA"] = "C"
        return table
    }()

    /// NCBI 表 16（绿藻 Chlorophycean 线粒体码）：UAG→L
    static let chlorophyceanTable: [String: Character] = {
        var table = standardTable
        table["TAG"] = "L"
        return table
    }()

    /// NCBI 表 24（羽腮动物线粒体）：UGA→W、AGA→S、AGG→K
    static let pterobranchMitoTable: [String: Character] = {
        var table = standardTable
        table["TGA"] = "W"
        table["AGA"] = "S"
        table["AGG"] = "K"
        return table
    }()

    /// NCBI 表 25（Candidate division SR1）：UGA→G
    static let sr1Table: [String: Character] = {
        var table = standardTable
        table["TGA"] = "G"
        return table
    }()

    /// NCBI 表 30（Peritrich 核码）：UAA/UAG→E（谷氨酸）
    static let peritrichTable: [String: Character] = {
        var table = standardTable
        table["TAA"] = "E"
        table["TAG"] = "E"
        return table
    }()

    static func table(for code: GeneticCodeTable) -> [String: Character] {
        switch code {
        case .standard: return standardTable
        case .vertebrateMito: return vertebrateMitoTable
        case .yeast: return yeastTable
        case .moldProtozoanMito: return moldProtozoanMitoTable
        case .invertebrateMito: return invertebrateMitoTable
        case .ciliate: return ciliateTable
        case .echinodermMito: return echinodermMitoTable
        case .bacterial: return bacterialTable
        case .altYeast: return altYeastTable
        case .ascidianMito: return ascidianMitoTable
        case .flatwormMito: return flatwormMitoTable
        case .blepharismaMito: return blepharismaMitoTable
        case .euplotid: return euplotidTable
        case .chlorophycean: return chlorophyceanTable
        case .pterobranchMito: return pterobranchMitoTable
        case .sr1: return sr1Table
        case .peritrichNuclear: return peritrichTable
        }
    }
}

// MARK: - 翻译对齐

/// 翻译过程中检出的、会让结果失去生物学含义的情形。
enum TranslationWarning: Equatable {
    /// 某序列存在非 3 倍数的内部缺失：该缺失之后的密码子相位与序列自身读框不符。
    /// 现在这些位置一律输出 'X'（不再编造氨基酸），并在此点名序列与首个越相位列。
    case frameshift(name: String, column: Int)
    /// 比对总长不是 3 的倍数（末尾补空位后再翻译）
    case lengthNotMultipleOfThree(Int)
    /// `.both` 模式产出"3 碱基 + 1 氨基酸"混排轨，不能参与任何定量分析
    case mixedCodonTrack
    /// `.ignoreGaps` 模式产出行长参差、与源比对列脱钩
    case raggedOutput
    /// 输入不是核酸比对
    case notNucleotideInput
}

/// 翻译结果 + 披露信息。除产物比对外还携带警告列表，用于向界面披露
/// "含单/双列 indel 的序列其翻译结果不可用于系统发育"等失去生物学含义的情形。
struct TranslationResult {
    let alignment: Alignment
    let warnings: [TranslationWarning]
    var isSafeForPhylogenetics: Bool {
        !warnings.contains { switch $0 {
            case .mixedCodonTrack, .raggedOutput, .frameshift, .notNucleotideInput: return true
            default: return false
        } }
    }
}

enum AlignmentTranslator {
    /// 元数据键：标注该比对是"密码子 + 氨基酸"混排轨。
    static let mixedTrackMetadataKey = "seqalign.translation.mixedTrack"

    /// 翻译入口的数据类型闸门：仅接受核酸比对。
    /// 蛋白比对若被当作核酸翻译，密码子如 `LMF` 查不到表 → 兜底返回 `X` →
    /// 会产出一条全 `X`、宽度为原长 1/3 的伪"蛋白比对"，还可能被赋
    /// datatype = .aminoAcid 后正常保存/导出/建树。而含 '.' 空位或 '*' 终止的
    /// 核酸比对会被判型器误判为蛋白，因此这条路径可能在用户未做任何设置时被走进，
    /// 必须先行拦截。
    static func translate(_ alignment: Alignment, table: GeneticCodeTable = .standard,
                          frame: Int = 0, displayMode: TranslationDisplayMode = .aminoAcidOnly) throws -> Alignment {
        let result = translateChecked(alignment, table: table, frame: frame, displayMode: displayMode)
        guard alignment.datatype == .nucleicAcid else { throw CoreError.format(String(localized: "translation.inputNotNucleotide")) }
        return result.alignment
    }

    /// 将核酸对齐翻译为氨基酸对齐，并返回全部披露信息（不抛异常，由界面决定如何提示）。
    /// - Parameters:
    ///   - table: NCBI 遗传密码表
    ///   - frame: 阅读框 (-3…-1, +1…+3；0 = 参考读框)
    ///   - displayMode: 显示模式（单密码子/氨基酸码/两者/忽略空位）
    static func translateChecked(_ alignment: Alignment, table: GeneticCodeTable = .standard,
                                 frame: Int = 0,
                                 displayMode: TranslationDisplayMode = .aminoAcidOnly) -> TranslationResult {
        let codonTable = TranslationTables.table(for: table)
        var aaSequences: [Sequence] = []
        var warnings: [TranslationWarning] = []

        guard alignment.datatype == .nucleicAcid else {
            // 蛋白比对"翻译"= 直接拒绝产出内容，原样返回并标记
            warnings.append(.notNucleotideInput)
            return TranslationResult(alignment: alignment, warnings: warnings)
        }

        if alignment.length % 3 != 0 { warnings.append(.lengthNotMultipleOfThree(alignment.length)) }
        if displayMode == .both { warnings.append(.mixedCodonTrack) }
        if displayMode == .ignoreGaps { warnings.append(.raggedOutput) }

        // 闭包内逐元素深拷贝，锁外只持有独立副本：AlignmentCore 的契约要求
        // lockedSequences 的返回值不得把内部数组引用带出锁。当前调用方传入的是
        // snapshot() 故无实际竞争，但 CLI / 批处理一旦把活 Alignment 直接传进来
        // 就会产生跨锁共享的可变状态，因此按契约写法收口。
        let sourceSequences = alignment.lockedSequences { seqs in
            seqs.map { Sequence(name: $0.name, description: $0.description,
                                residues: [UInt8]($0.residues),
                                quality: $0.quality.map { [UInt8]($0) }) }
        }
        for seq in sourceSequences {
            var work = seq.residues
            // 阅读框处理：正框 = 跳过前 frame 个碱基；负框 = 先取反向互补，再按 |frame|-1 偏移。
            if frame < 0 {
                work = SequenceUtils.reverseComplement(work)
                // 负框 = 取反向互补后从偏移 (|frame|-1) 开始读码：
                // frame -1 → 偏移 0（RC 首碱基），-2 → 偏移 1，-3 → 偏移 2（标准 6 框语义）。
                // 偏移必须是 |frame|-1 而不是 |frame|，否则 -1 框会被错读成 -2 框。
                let off = min(-frame - 1, work.count)
                if off > 0 { work = Array(work[off...]) }
            } else if frame > 0 {
                let off = min(frame, work.count)
                if off > 0 { work = Array(work[off...]) }
            }

            let result: [UInt8]
            switch displayMode {
            case .codonOnly:
                // 单密码子模式：显示（阅读框调整后的）密码子序列
                result = work
            case .aminoAcidOnly:
                // 氨基酸码模式：按密码子列翻译，非 3 倍数缺失之后的相位一律 X
                let (translated, shiftCol) = translateFrameAware(Self.padToCodon(work), codonTable: codonTable)
                if let shiftCol = shiftCol { warnings.append(.frameshift(name: seq.name, column: shiftCol)) }
                result = translated
            case .both:
                // 两者模式：交替显示密码子和氨基酸（氨基酸在密码子后）
                let (translated, shiftCol) = translateFrameAware(Self.padToCodon(work), codonTable: codonTable, both: true)
                if let c = shiftCol { warnings.append(.frameshift(name: seq.name, column: c)) }
                result = translated
            case .ignoreGaps:
                // 忽略空位模式：先移除空位再翻译（读框正确，但输出与源比对列脱钩）
                let noGaps = work.filter { !ResidueAlphabet.isGap($0) }
                result = translateWithGaps(Self.padToCodon(noGaps), codonTable: codonTable)
            }

            // 名称策略交给调用方：核心翻译不追加 "_AA" 后缀，
            // 由 UI 依据「保留原名 / 添加后缀」决定是否追加，避免 "Seq1_AA_AA"。
            aaSequences.append(Sequence(name: seq.name, description: seq.description, residues: result))
        }

        // codonOnly 模式输出的是（阅读框调整后的）核苷酸密码子，必须按核酸着色/统计；
        // 若标为 .aminoAcid 会让下游按蛋白语义处理 DNA 内容。
        // `.both` 输出宽度为输入的 4/3，其中 75% 是 A/C/G/T 字母，若按氨基酸解释，
        // A 会被当丙氨酸、C 当半胱氨酸、G 当甘氨酸、T 当苏氨酸参与
        // 着色 / 列一致度 / 变异位点 / NJ 树。因此标为核酸（多数派字母表）+ 打混排标记，
        // 并由 isSafeForPhylogenetics / metadata 阻止下游把它当作可比对数据分析。
        let outDatatype: Datatype
        switch displayMode {
        case .codonOnly, .both: outDatatype = .nucleicAcid
        case .aminoAcidOnly, .ignoreGaps: outDatatype = .aminoAcid
        }
        var meta: [String: String] = [:]
        if displayMode == .both { meta[mixedTrackMetadataKey] = "codon3+aa1" }
        let out = Alignment(sequences: aaSequences, datatype: outDatatype, metadata: meta)
        // `.both` / `.ignoreGaps` 的产物不是"与源比对逐列同源的氨基酸比对"
        if displayMode == .ignoreGaps { out.provenance = .unknown }
        return TranslationResult(alignment: out, warnings: warnings)
    }

    /// 该比对是否为"密码子 + 氨基酸"混排轨：导出/建树/统计入口据此拦截。
    static func isMixedCodonTrack(_ alignment: Alignment) -> Bool {
        alignment.metadata[mixedTrackMetadataKey] != nil
    }

    /// 补齐到 3 的倍数（右侧补 '-'），避免尾部不完整密码子被静默丢弃
    private static func padToCodon(_ residues: [UInt8]) -> [UInt8] {
        let pad = (3 - residues.count % 3) % 3
        if pad > 0 {
            return residues + [UInt8](repeating: 0x2D, count: pad)
        }
        return residues
    }

    /// 单密码子查表（三处翻译模式共用，消除复制漂移）；未知/含空位一律返回 'X'
    static func translateCodon(_ codon: [UInt8], codonTable: [String: Character]) -> UInt8 {
        guard !codon.contains(where: { ResidueAlphabet.isGap($0) }) else { return 0x58 }
        let codonStr = String(bytes: codon, encoding: .ascii) ?? "XXX"
        guard let aa = codonTable[codonStr] else { return 0x58 }
        // asciiValue 兜底：防止向表中加入非 ASCII 字符时 trap
        return aa.asciiValue.map { UInt8($0) } ?? 0x58
    }

    /// 相位感知的按列翻译。
    ///
    /// 背景：三三分组是在**比对列**上进行的，因此只要比对按密码子结构构建，空位本身
    /// 不会造成移位。真正的失效模式是"某序列含长度非 3 倍数的内部缺失"（单/双列 indel）：
    /// 该序列自身的读框从那一列起整体偏移，按比对列读出的三联体不再是它的真实密码子，
    /// 直接翻译会**静默产出一串假氨基酸**（多数为 X，但也可能是假终止 '*'）。
    ///
    /// 处理方式：从越相位的那一列起，该序列一律输出 'X'（不编造残基），并通过返回值
    /// 告知首个越相位列，由界面明示"此序列的翻译不可用于系统发育"。
    /// - Returns: (翻译结果, 首个越相位密码子列；无则 nil)
    static func translateFrameAware(_ residues: [UInt8], codonTable: [String: Character],
                                    both: Bool = false) -> ([UInt8], Int?) {
        // 1) 找出第一个"长度非 3 倍数的内部空位游程"（尾部补齐出来的游程不算越相位）
        var firstBadColumn = -1
        var run = 0
        var runStart = -1
        for i in 0..<residues.count {
            if ResidueAlphabet.isGap(residues[i]) {
                if runStart < 0 { runStart = i }
                run += 1
            } else if run > 0 {
                if runStart > 0, run % 3 != 0 { firstBadColumn = runStart; break }   // 起始处的缺失只是截短，不改变读框
                run = 0
                runStart = -1
            }
        }
        // 2) 按比对列三三分组；越相位之后一律 X
        var result: [UInt8] = []
        result.reserveCapacity(residues.count / 3 * (both ? 4 : 1))
        var firstBadCodon: Int? = nil
        var i = 0
        var codonIndex = 0
        while i + 2 < residues.count {
            let codon = [residues[i], residues[i + 1], residues[i + 2]]
            let aa: UInt8
            if firstBadColumn >= 0, i >= firstBadColumn {
                firstBadCodon = firstBadCodon ?? codonIndex
                aa = 0x58                       // X：读框已错，拒绝编造残基
            } else {
                aa = translateCodon(codon, codonTable: codonTable)
            }
            if both {
                result.append(contentsOf: codon)
                result.append(aa)
            } else {
                result.append(aa)
            }
            i += 3
            codonIndex += 1
        }
        return (result, firstBadCodon)
    }

    static func translateWithGaps(_ residues: [UInt8], codonTable: [String: Character]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(residues.count / 3)
        var i = 0
        while i + 2 < residues.count {
            result.append(translateCodon([residues[i], residues[i + 1], residues[i + 2]], codonTable: codonTable))
            i += 3
        }
        return result
    }

    private static func translateNoGaps(_ residues: [UInt8], codonTable: [String: Character]) -> [UInt8] {
        translateWithGaps(residues, codonTable: codonTable)
    }

    /// 两者模式：密码子和氨基酸交替排列（不包含相位检测）
    private static func translateBoth(_ residues: [UInt8], codonTable: [String: Character]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(residues.count / 3 * 4)
        var i = 0
        while i + 2 < residues.count {
            let codon = [residues[i], residues[i + 1], residues[i + 2]]
            result.append(contentsOf: codon)
            result.append(translateCodon(codon, codonTable: codonTable))
            i += 3
        }
        return result
    }
}
