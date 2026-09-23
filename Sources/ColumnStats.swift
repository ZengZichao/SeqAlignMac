//  ColumnStats.swift
//  SeqAlignMac — 列统计与比对质量评估

import Foundation

// MARK: - 比对质量

struct AlignmentQuality {
    /// **位点加权池化一致度** = (Σ_ij m_ij) / (Σ_ij n_ij)，不是"平均成对一致度"
    /// mean_{i<j}(m_ij / n_ij)。两者只在各对可比位点数 n_ij 全相等（无缺失）时相同；
    /// 含缺失矩阵中前者会系统性偏向数据完整的那部分位点。旧字段名
    /// `meanPairwiseIdentity` 与 UI 文案"平均成对一致度"共同构成了一个不成立的断言，
    /// 故改名并在界面按"池化一致度（位点加权）"表述。
    /// 若需要真正的平均成对一致度，用 `meanPairwiseIdentityExact`（O(n²m)，仅在序列数
    /// 足够小时由界面显式请求）。
    let pooledPairwiseIdentity: Double
    let minColumnIdentity: Double
    let maxColumnIdentity: Double
    let gapColumns: UInt64
    let totalColumns: UInt64
    // 系统发育统计
    let variableSites: Int       // 变异位点：至少 2 种可判定状态
    let parsimonySites: Int      // 简约信息位点：至少 2 种状态且每种 ≥2 条序列
    let singletonSites: Int      // 单例位点：只有 1 条序列不同
    /// `sampled` 字段在列频次法下恒为 false，面板里那个"采样提示"
    /// 分支永不显示（僵尸 UI）。字段与 UI 分支一并删除。
    init(pooledPairwiseIdentity: Double, minColumnIdentity: Double, maxColumnIdentity: Double,
         gapColumns: UInt64, totalColumns: UInt64, variableSites: Int,
         parsimonySites: Int, singletonSites: Int) {
        self.pooledPairwiseIdentity = pooledPairwiseIdentity
        self.minColumnIdentity = minColumnIdentity
        self.maxColumnIdentity = maxColumnIdentity
        self.gapColumns = gapColumns
        self.totalColumns = totalColumns
        self.variableSites = variableSites
        self.parsimonySites = parsimonySites
        self.singletonSites = singletonSites
    }
}

// MARK: - 列统计

struct ColumnStats {
    let consensus: [UInt8]   // 每列共识残基
    let identity: [Double]   // 每列一致度 0.0..1.0
    let columnCount: Int
}

// MARK: - 共识模式

/// 共识行残基的计算策略。rawValue 与设置面板三选一直接对应。
/// 注意：模式仅改变「共识字符」，identity/quality（保守度轨道、配色、
/// NJ 树、平均一致度）恒为多数规则口径，与如何书写共识符号正交。
enum ConsensusMode: Int, CaseIterable {
    case majority = 0   // 频次最高；并列取字节较小者（历史默认）
    case iupac = 1      // 核酸：把该列出现的碱基集合折叠为 IUPAC 简并码
    case strict = 2     // 仅当非空位残基全一致时输出该残基，否则 N（核酸）/ X（蛋白）
}

// MARK: - 计算

enum AlignmentStatsCalculator {
    /// 融合单遍扫描的内部结果
    struct FusedScanResult {
        let consensus: [UInt8]
        let identities: [Double]
        let quality: AlignmentQuality
    }

    /// 单遍行主序融合遍历。
    /// 三套 API（computeQuality / computeColumnStats / columnIdentities）若各自
    /// 按列扫描：每列一次 NSLock 加解锁 + 2 个临时数组 + 字典（根源在
    /// Alignment.columnResidues 的列主序访问），10k 行 × 50k 列 = 5 万次锁操作 +
    /// 约 10 万个临时数组。现在一次 lockedSequences（只加锁一次）按行遍历全部残基，
    /// 为每列维护频次与聚合量，同时产出 consensus / identity / quality 三份结果；
    /// 各公开 API 保留为薄封装，行为（含频次并列打破规则）保持一致。
    /// - Parameter columns: 仅统计该闭区间内的列（导出局部范围时避免全表成本）；
    ///   返回数组仍按全表长度索引，区间外为默认值。
    static func fusedScan(_ alignment: Alignment, columns colRange: ClosedRange<Int>? = nil,
                          mode: ConsensusMode = .majority) -> FusedScanResult {
        let nCol = alignment.length
        let nSeq = alignment.seqCount
        let range = colRange ?? 0...max(0, nCol - 1)
        guard nSeq > 0 && nCol > 0 else {
            return FusedScanResult(
                consensus: [UInt8](repeating: 0x2D, count: max(0, nCol)),
                identities: [Double](repeating: 0.0, count: max(0, nCol)),
                quality: AlignmentQuality(pooledPairwiseIdentity: 0, minColumnIdentity: 0,
                                          maxColumnIdentity: 0, gapColumns: 0, totalColumns: 0,
                                          variableSites: 0, parsimonySites: 0, singletonSites: 0))
        }

        let isNucleotide: Bool = (alignment.datatype == .nucleicAcid)
        // 位点计量的"状态未知"集合按数据类型分叉：若不分数据类型地套用核酸 IUPAC
        // 简并码集合，蛋白比对里
        // D H K M N R S V Y 共 9 个标准氨基酸被当成"状态未知"剔除（B 确为歧义码），
        // 变异位点 / 简约信息位点 / 单例位点按"半个字母表"计算。
        let unassignable = ResidueAlphabet.unassignableStates(datatype: alignment.datatype)
        // 列一致度的分子分母只排除"完全无信息"的符号（N/X/?，蛋白另含 B/Z）。
        // 分母若只排除 '-'，全 N 列 bestCount == nonGap → identity = 1.0，
        // 会被画成"最高保守档"——多基因拼接/含大量缺类的矩阵里"全缺失 = 最保守"是
        // 彻底反向的信号。核酸简并码（R/Y/S/…）仍算作一致状态：一列全 R 表示
        // 所有序列一致判定为嘌呤，这是真实保守，不是缺失。
        let undetermined = ResidueAlphabet.undeterminedSymbols(datatype: alignment.datatype)

        var freqs = [[UInt8: Int]](repeating: [:], count: nCol)
        var informativeCounts = [Int](repeating: 0, count: nCol)   // 一致度分母：非空位且非"未判定"

        // 单次加锁、行主序遍历（缓存局部性与行存储一致）
        alignment.lockedSequences { seqs in
            for seq in seqs {
                let residues = seq.residues
                let rowLen = residues.count
                let upper = min(rowLen, nCol)
                for col in 0..<upper {
                    guard range.contains(col) else { continue }
                    let b = residues[col]
                    // '.' / '~' 也是空位（解析层已归一化为 '-'，这里兜住
                    // 用户手工输入与未经解析器规范化的构造路径）。
                    if ResidueAlphabet.isGap(b) { continue }
                    freqs[col][b, default: 0] += 1
                    if !undetermined.contains(b) { informativeCounts[col] += 1 }
                }
                // 序列短于全表长度的部分按空位计，无需累计
            }
        }

        var consensus = [UInt8](repeating: 0x2D, count: nCol)
        var identities = [Double](repeating: 0.0, count: nCol)
        var gapColumns: UInt64 = 0
        var variableSites = 0
        var parsimonySites = 0
        var singletonSites = 0
        var sumMatchPairs: Double = 0   // Σ_col Σ_k freq_k*(freq_k-1)
        var sumTotalPairs: Double = 0   // Σ_col n_c*(n_c-1)
        var minIdentity = 2.0
        var maxIdentity = 0.0

        for col in 0..<nCol {
            guard range.contains(col) else { continue }
            let freq = freqs[col]
            let informative = informativeCounts[col]
            if informative == 0 {
                // 全空位列，或整列都是"未判定"符号（全 N / 全 X / 全 ?）：
                // —— 两种情形同样记 identity = 0，共识为 '-'，不计入保守度。
                gapColumns += 1
                continue // consensus='-'、identity=0 即默认值
            }

            // 共识残基 = 频次最高；并列取字节值较小者（确定性规则）
            var bestByte: UInt8 = 0x2D
            var bestCount = 0
            for (b, c) in freq where c > bestCount || (c == bestCount && b < bestByte) {
                bestByte = b
                bestCount = c
            }
            consensus[col] = Self.resolveConsensusByte(mode: mode, isNucleotide: isNucleotide,
                                                       freq: freq, bestByte: bestByte, nonGap: informative)
            // 一致度只在"可判定状态"上计算，未判定符号同时剔出分子与分母。
            let identity = Double(bestCount) / Double(informative)
            identities[col] = identity
            if identity < minIdentity { minIdentity = identity }
            if identity > maxIdentity { maxIdentity = identity }

            // 列频次法累计池化一致度（这是位点加权池化值，不是平均成对一致度）
            if informative >= 2 {
                for c in freq.values {
                    sumMatchPairs += Double(c * (c - 1))
                }
                sumTotalPairs += Double(informative * (informative - 1))
            }

            // 系统发育统计（按数据类型剔除"状态未知"，蛋白侧不再误删标准氨基酸）
            var definedTotal = 0
            var definedMax = 0
            var definedDistinct = 0
            var definedMinTwo = 0
            for (b, c) in freq where !unassignable.contains(b) {
                definedTotal += c
                if c > definedMax { definedMax = c }
                definedDistinct += 1
                if c >= 2 { definedMinTwo += 1 }
            }
            if definedTotal > 0, definedDistinct >= 2 {
                variableSites += 1
                if definedMinTwo >= 2 {
                    parsimonySites += 1
                } else if definedMax == definedTotal - 1 {
                    singletonSites += 1
                }
            }
        }

        let pooledIdentity = sumTotalPairs > 0 ? sumMatchPairs / sumTotalPairs : 0
        let quality = AlignmentQuality(
            pooledPairwiseIdentity: pooledIdentity,
            minColumnIdentity: minIdentity == 2.0 ? 0 : minIdentity,
            maxColumnIdentity: maxIdentity,
            gapColumns: gapColumns,
            totalColumns: UInt64(nCol),
            variableSites: variableSites,
            parsimonySites: parsimonySites,
            singletonSites: singletonSites)
        return FusedScanResult(consensus: consensus, identities: identities, quality: quality)
    }

    /// 依共识模式给出该列共识残基。
    /// - majority：频次最高（并列打破由调用方算好后以 bestByte 传入）。
    /// - iupac（仅核酸）：把该列出现的 ACGT(U) 碱基集合折叠为 IUPAC 简并码；
    ///   若含任何非简单碱基（歧义码/缺失/终止）→ 回退 majority，避免臆造符号。
    /// - strict：该列非空位残基全部一致（distinct==1）时输出该残基，否则 N（核酸）/X（蛋白）。
    private static func resolveConsensusByte(mode: ConsensusMode, isNucleotide: Bool,
                                             freq: [UInt8: Int], bestByte: UInt8, nonGap _: Int) -> UInt8 {
        switch mode {
        case .majority:
            return bestByte
        case .iupac:
            guard isNucleotide else { return bestByte }
            var mask = 0
            for b in freq.keys {
                switch b {
                case 0x41: mask |= 1        // A
                case 0x43: mask |= 2        // C
                case 0x47: mask |= 4        // G
                case 0x54, 0x55: mask |= 8  // T / U
                default: return bestByte    // 含非简单碱基 → 回退多数规则
                }
            }
            return nucleotideIUPAC(mask) ?? bestByte
        case .strict:
            if freq.count == 1 { return bestByte }
            return isNucleotide ? 0x4E /* N */ : 0x58 /* X */
        }
    }

    /// 核酸碱基位掩码（A=1, C=2, G=4, T=8）对应的 IUPAC 码；空/异常掩码返回 nil。
    private static func nucleotideIUPAC(_ mask: Int) -> UInt8? {
        switch mask {
        case 1: return 0x41              // A
        case 2: return 0x43              // C
        case 4: return 0x47              // G
        case 8: return 0x54              // T
        case 1 | 4: return 0x52          // R = A/G
        case 2 | 8: return 0x59          // Y = C/T
        case 2 | 4: return 0x53          // S = C/G
        case 1 | 8: return 0x57          // W = A/T
        case 4 | 8: return 0x4B          // K = G/T
        case 1 | 2: return 0x4D          // M = A/C
        case 2 | 4 | 8: return 0x42      // B = C/G/T
        case 1 | 4 | 8: return 0x44      // D = A/G/T
        case 1 | 2 | 8: return 0x48      // H = A/C/T
        case 1 | 2 | 4: return 0x56      // V = A/C/G
        case 1 | 2 | 4 | 8: return 0x4E  // N = A/C/G/T
        default: return nil
        }
    }

    /// 成对一致度改用列频次法近似，复杂度从 O(n²×m) 降到 O(n×m)。
    /// 原理：对每列计算频次，匹配对数 = Σ C(freq_k, 2)，总对数 = C(nonGapCount, 2)。
    /// 此公式在无内部空位时精确等于成对一致度；有空位时为加权近似，误差可忽略。
    /// 同时消除了采样需求——不再需要 n>200 时采样，且结果不再标注 sampled=true。
    /// 内部改为单遍融合扫描。
    static func computeQuality(_ alignment: Alignment) -> AlignmentQuality {
        fusedScan(alignment).quality
    }

    /// 增量更新列统计。
    /// 传入 dirtyColumns 集合时，只重算受影响的列，其余列复用 prevStats 中的值。
    /// 对于同长度单字符编辑（仅影响 1 列），可将 O(n×m) 全量重算降为 O(n) 单列重算。
    /// dirtyColumns=nil 等价于全量重算（兼容原有调用）。
    static func computeColumnStats(_ alignment: Alignment,
                                   prevStats: ColumnStats? = nil,
                                   dirtyColumns: Set<Int>? = nil,
                                   mode: ConsensusMode = .majority) -> ColumnStats {
        // 无增量信息或无缓存 → 全量重算
        guard let prev = prevStats, let dirty = dirtyColumns, !dirty.isEmpty,
              prev.columnCount == alignment.length else {
            return computeColumnStats(alignment, mode: mode)
        }

        var consensus = prev.consensus
        var identity = prev.identity
        let isNucleotide: Bool = (alignment.datatype == .nucleicAcid)
        // 与全量路径同一口径：空位含 '.' / '~'，一致度分母再排除"完全无信息"符号
        let undetermined = ResidueAlphabet.undeterminedSymbols(datatype: alignment.datatype)

        for col in dirty.sorted() {
            guard col >= 0, col < consensus.count else { continue }
            let colRes = alignment.columnResidues(col: col)
            let nonGap = colRes.filter { !ResidueAlphabet.isGap($0) }
            let informative = nonGap.filter { !undetermined.contains($0) }
            if informative.isEmpty {
                consensus[col] = 0x2D
                identity[col] = 0.0
                continue
            }

            var freq: [UInt8: Int] = [:]
            for r in nonGap { freq[r, default: 0] += 1 }

            // 与全量路径同一确定性并列打破规则：频次并列取字节值较小者
            var bestByte: UInt8 = 0x2D
            var bestCount = 0
            for (b, c) in freq where c > bestCount || (c == bestCount && b < bestByte) {
                bestByte = b
                bestCount = c
            }
            consensus[col] = Self.resolveConsensusByte(mode: mode, isNucleotide: isNucleotide,
                                                       freq: freq, bestByte: bestByte, nonGap: informative.count)
            identity[col] = Double(bestCount) / Double(informative.count)
        }

        return ColumnStats(consensus: consensus, identity: identity, columnCount: alignment.length)
    }

    /// 计算列统计（共识残基 + 一致度）—— 全量计算
    /// 内部改为单遍融合扫描（一次加锁 + 行主序遍历）
    static func computeColumnStats(_ alignment: Alignment, mode: ConsensusMode = .majority) -> ColumnStats {
        let fused = fusedScan(alignment, mode: mode)
        return ColumnStats(consensus: fused.consensus,
                           identity: fused.identities,
                           columnCount: fused.identities.count)
    }

    /// 计算列统计（只统计 [lo, hi] 闭区间内的列；数组仍按全表长度索引）
    static func computeColumnStats(_ alignment: Alignment, columns range: ClosedRange<Int>,
                                   mode: ConsensusMode = .majority) -> ColumnStats {
        let fused = fusedScan(alignment, columns: range, mode: mode)
        return ColumnStats(consensus: fused.consensus,
                           identity: fused.identities,
                           columnCount: fused.identities.count)
    }

    /// 每列一致度（主频次残基占比 0.0..1.0）。
    /// 单一事实来源：ColorSchemes（ClustalX 保守阈值）与 ExportManager 均向此处取数，
    /// 避免三处各自累加频率导致语义漂移。
    /// 内部改为单遍融合扫描。
    static func columnIdentities(_ alignment: Alignment) -> [Double] {
        fusedScan(alignment).identities
    }

    /// 真正的"平均成对一致度" mean_{i<j}(m_ij / n_ij)，复杂度 O(n²·m)。
    /// 融合扫描给出的是位点加权池化值（pooledPairwiseIdentity），两者只在
    /// 各对可比位点数全相等（无缺失）时相同。含缺失矩阵里池化值偏向数据完整的
    /// 位点段，因此界面若要用"平均成对"这一名称，必须调用本函数；
    /// 序列数超过 `maxSequencesForExact` 时返回 nil，由界面改述为池化口径。
    static func meanPairwiseIdentityExact(_ alignment: Alignment,
                                          maxSequencesForExact: Int = 400) -> Double? {
        let seqs: [[UInt8]] = alignment.lockedSequences { $0.map { $0.residues } }
        let n = seqs.count
        guard n >= 2, n <= maxSequencesForExact else { return nil }
        var sum = 0.0
        var pairs = 0
        for i in 0..<(n - 1) {
            for j in (i + 1)..<n {
                let a = seqs[i], b = seqs[j]
                let len = min(a.count, b.count)
                var match = 0, total = 0
                for k in 0..<len {
                    let x = a[k], y = b[k]
                    if ResidueAlphabet.isGap(x) || ResidueAlphabet.isGap(y) { continue }
                    total += 1
                    if x == y { match += 1 }
                }
                guard total > 0 else { continue }   // 无可比位点的对不参与平均
                sum += Double(match) / Double(total)
                pairs += 1
            }
        }
        guard pairs > 0 else { return nil }
        return sum / Double(pairs)
    }
}

// MARK: - FASTQ 质量汇总（Q20/Q30 等）

struct FastqQualitySummary {
    let readCount: Int        // 含质量值的序列数
    let meanPhred: Double     // 全部碱基平均 Phred
    let minPhred: Int         // 最低 Phred
    let q20Ratio: Double      // ≥Q20 碱基占比
    let q30Ratio: Double      // ≥Q30 碱基占比
    var hasData: Bool { readCount > 0 }
}

extension AlignmentStatsCalculator {
    /// 汇总 FASTQ 质量值：非 FASTQ 来源（quality == nil）返回 hasData=false
    static func computeQualitySummary(_ alignment: Alignment) -> FastqQualitySummary {
        var total = 0
        var sum = 0.0
        var minQ = Int.max
        var q20 = 0
        var q30 = 0
        var reads = 0
        alignment.lockedSequences { seqs in
            for seq in seqs {
                guard let q = seq.quality, !q.isEmpty else { continue }
                reads += 1
                for v in q {
                    let val = Int(v)
                    total += 1
                    sum += Double(val)
                    if val < minQ { minQ = val }
                    if val >= 20 { q20 += 1 }
                    if val >= 30 { q30 += 1 }
                }
            }
        }
        guard total > 0 else {
            return FastqQualitySummary(readCount: 0, meanPhred: 0, minPhred: 0,
                                       q20Ratio: 0, q30Ratio: 0)
        }
        return FastqQualitySummary(readCount: reads,
                                   meanPhred: sum / Double(total),
                                   minPhred: minQ,
                                   q20Ratio: Double(q20) / Double(total),
                                   q30Ratio: Double(q30) / Double(total))
    }
}

// MARK: - 序列 Logo（Schneider & Stephens 1990 信息含量）

struct LogoColumn {
    let position: Int
    let totalBits: Double                  // 该列信息含量（bits）
    let stacks: [(residue: UInt8, fraction: Double)] // 各残基按占比排序（fraction 和为 1）
}

/// Logo 计算结果携带"算了多少列 / 比对共多少列"，让截断对界面可见。
/// 逐列调用 columnResidues 有 O(列×行) 成本，截断本身是合理的防御，
/// 截断必须对界面可见，不能藏起来：12 kb 的比对若显示"34 页"，用户会以为自己翻完了整条序列。
struct LogoComputation {
    let columns: [LogoColumn]
    let alignmentColumns: Int
    let maxColumns: Int
    var isTruncated: Bool { alignmentColumns > columns.count }
    var omittedColumns: Int { max(0, alignmentColumns - columns.count) }
}

enum LogoCalculator {
    /// 计算比对每列的信息含量与残基占比。
    /// R(l) = log2(K) − (H(l) + e(n))，K 为字母表大小（核酸 4 / 氨基酸 20），
    /// H 为香农熵，e(n)=(K−1)/(2·ln2·n) 为小样本校正；空位不计入频次。
    static func compute(_ alignment: Alignment, maxColumns: Int = 4000) -> LogoComputation {
        let nCol = min(alignment.length, maxColumns)
        let alphabetSize = alignment.datatype == .nucleicAcid ? 4.0 : 20.0
        // 过滤集按数据类型分叉：不得无条件套用核酸 IUPAC 简并集，
        // 否则蛋白 Logo 里 D H K M N R S V Y 这 9 种标准残基完全不出现，
        // 信息量在残缺样本上算出，且 n 变小 → 小样本校正 e 被放大 → 双重偏离。
        let unassignable = ResidueAlphabet.unassignableStates(datatype: alignment.datatype)
        var result: [LogoColumn] = []
        result.reserveCapacity(nCol)

        for col in 0..<nCol {
            // 歧义码按组成碱基分摊会改变信息量口径，与主流 Logo 实现一致：
            // 只统计可判定的标准残基（蛋白侧的标准氨基酸一律可判定）
            let colRes = alignment.columnResidues(col: col).filter {
                !ResidueAlphabet.isGap($0) && !unassignable.contains($0)
            }
            guard !colRes.isEmpty else {
                result.append(LogoColumn(position: col, totalBits: 0, stacks: []))
                continue
            }
            var freq: [UInt8: Int] = [:]
            for r in colRes { freq[r, default: 0] += 1 }
            let n = Double(colRes.count)

            var entropy = 0.0
            for c in freq.values {
                let p = Double(c) / n
                entropy -= p * log2(p)
            }
            let e = (alphabetSize - 1) / (2 * M_LN2 * n)
            let bits = max(0, log2(alphabetSize) - entropy - e)

            let stacks = freq
                .map { (residue: $0.key, fraction: Double($0.value) / n) }
                .sorted { $0.fraction > $1.fraction }
            result.append(LogoColumn(position: col, totalBits: bits, stacks: stacks))
        }
        return LogoComputation(columns: result, alignmentColumns: alignment.length,
                               maxColumns: maxColumns)
    }

    /// 兼容既有调用与测试：只取列数组。
    static func columns(_ alignment: Alignment, maxColumns: Int = 4000) -> [LogoColumn] {
        compute(alignment, maxColumns: maxColumns).columns
    }
}

// MARK: - NJ 系统发育树（p-distance）+ 滑动窗口一致度

/// 建树结果必须自带"用了多少条序列、抽了多少条、距离模型是什么、
/// 钳制了几条负分支"。未声明的抽样在系统发育学里比抽样本身危害大得多——
/// 1200 条序列的提交会得到一棵只有 200 个 tip 的树，用户复制走、贴进手稿，以为全类群都在。
struct PhyloTreeResult {
    let newick: String
    let sequencesTotal: Int
    let sequencesUsed: Int
    let clampedBranchLengths: Int
    /// 本树用的是未校正 p-distance。函数名与注释已诚实标注，但界面若只写"NJ 树"
    /// 用户会当成模型树使用，因此把模型串随结果一并返回，供界面/图注直接引用。
    let distanceModel: String
    var wasSampled: Bool { sequencesUsed < sequencesTotal }
    var samplingNote: String? {
        wasSampled ? "NJ tree built from \(sequencesUsed) of \(sequencesTotal) sequences (even sampling)" : nil
    }
}

enum PhyloBuilder {
    /// 等距抽样至多 maxSeqs 条（名称与距离矩阵共用同一次抽样结果）。
    /// 闭包内显式拷贝、锁外只持有独立副本，不得把内部数组引用带出锁。
    private static func sampledSequences(_ alignment: Alignment, maxSeqs: Int) -> [Sequence] {
        let allSeqs: [Sequence] = alignment.lockedSequences { seqs in
            seqs.map { Sequence(name: $0.name, description: $0.description,
                                residues: [UInt8]($0.residues),
                                quality: $0.quality.map { [UInt8]($0) }) }
        }
        guard maxSeqs > 0, allSeqs.count > maxSeqs else { return allSeqs }
        let step = Double(allSeqs.count) / Double(maxSeqs)
        return (0..<maxSeqs).map { allSeqs[min(allSeqs.count - 1, Int(Double($0) * step))] }
    }

    private static func pDistance(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var match = 0, total = 0
        let len = min(a.count, b.count)
        for k in 0..<len {
            let x = a[k], y = b[k]
            // 空位的任意写法（- . ~）都不参与比较；只认 '-' 会把两条全 '.' 的行判为
            // "10 个位点完全一致"，距离被系统性低估。
            if ResidueAlphabet.isGap(x) || ResidueAlphabet.isGap(y) { continue }
            // 未判定状态（核酸 N、蛋白 X）不参与距离：它表达的是"测到了但定不了"。
            if x == 0x4E || y == 0x4E || x == 0x58 || y == 0x58 { continue }
            total += 1
            if x == y { match += 1 }
        }
        return total > 0 ? 1.0 - Double(match) / Double(total) : 1.0
    }

    /// 未校正 p-distance 距离矩阵（成对比较仅计双方均可判定的位点）。
    /// 超过 maxSeqs 时按等距抽样选取（而非固定取前 maxSeqs 条，
    /// 避免用户无感知地得到「前 200 序列」的树）。
    /// 仍未做 Jukes-Cantor / Kimura 校正，界面必须注明"仅适用于低分化近缘序列"。
    static func pDistanceMatrix(_ alignment: Alignment, maxSeqs: Int = 200) -> [[Double]] {
        let seqs = sampledSequences(alignment, maxSeqs: maxSeqs).map { $0.residues }
        let n = seqs.count
        var d = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let dist = pDistance(seqs[i], seqs[j])
                d[i][j] = dist
                d[j][i] = dist
            }
        }
        return d
    }

    /// Neighbor-Joining（Saitou & Nei 1987）构建树并输出 Newick 串。
    /// 兼容旧签名：仅返回 Newick。需要抽样披露/钳制计数时用 `njTree`。
    static func njNewick(_ alignment: Alignment, maxSeqs: Int = 200) -> String {
        njTree(alignment, maxSeqs: maxSeqs).newick
    }

    /// 建树并返回全部披露信息。
    /// - Parameter provenanceComment: 是否在 Newick 根节点上附 NHX 风格注释
    ///   （`[&sampled=200_of_1200;model=p-distance]`），让被复制走的树串自身也带上抽样事实。
    ///   多数解析器（ete3 / iTOL / FigTree）忽略 `[...]` 注释；设为 false 可得到裸树串。
    static func njTree(_ alignment: Alignment, maxSeqs: Int = 200,
                       provenanceComment: Bool = true) -> PhyloTreeResult {
        let sampled = sampledSequences(alignment, maxSeqs: maxSeqs)
        let total = alignment.seqCount
        // 归一化后同名 tip 会让多数解析器报错（"Taxon A" 与 "Taxon_A" 都变成 Taxon_A），
        // 用与写出侧同一思路唯一化。
        let names = ResidueAlphabet.uniqueNewickNames(sampled.map { $0.name })
        let model = "uncorrected p-distance"
        var clamped = 0
        func clamp(_ v: Double) -> Double {
            if v < 0 { clamped += 1; return 0 }
            return v
        }

        func withProvenance(_ tree: String) -> String {
            guard provenanceComment else { return tree }
            let comment = "[&sampled=\(names.count)_of_\(total);model=p-distance;clamped=\(clamped)]"
            guard tree.hasSuffix(");") else { return tree + comment }
            return String(tree.dropLast(1)) + comment + ";"
        }

        // 两条序列时的正确无根表示是 (A:d/2,B:d/2)，必须保留距离信息
        guard names.count >= 2 else {
            let tree = names.first.map { "(\($0));" } ?? "();"
            return PhyloTreeResult(newick: withProvenance(tree), sequencesTotal: total,
                                   sequencesUsed: names.count, clampedBranchLengths: 0,
                                   distanceModel: model)
        }
        guard names.count >= 3 else {
            let d = pDistanceMatrix(alignment, maxSeqs: maxSeqs)
            let half = String(format: "%.5f", clamp(d[0][1] / 2))
            let tree = "(\(names[0]):\(half),\(names[1]):\(half));"
            return PhyloTreeResult(newick: withProvenance(tree), sequencesTotal: total,
                                   sequencesUsed: 2, clampedBranchLengths: clamped > 0 ? clamped : 0,
                                   distanceModel: model)
        }

        let n = names.count
        let totalNodes = 2 * n - 1
        let d = pDistanceMatrix(alignment, maxSeqs: maxSeqs)

        // 预分配 (2n-1)² 距离方阵
        var D = [[Double]](repeating: [Double](repeating: 0, count: totalNodes), count: totalNodes)
        for i in 0..<n {
            for j in 0..<n {
                D[i][j] = d[i][j]
            }
        }
        var labels: [String] = names
        var active = Array(0..<n)

        while active.count > 2 {
            let m = active.count
            var rowSum = [Int: Double]()
            for i in active {
                var sum = 0.0
                for j in active where j != i { sum += D[i][j] }
                rowSum[i] = sum
            }
            var bestQ = Double.infinity
            var bestI = -1, bestJ = -1
            for ai in 0..<m {
                for bj in (ai + 1)..<m {
                    let i = active[ai], j = active[bj]
                    let q = (Double(m) - 2) * D[i][j] - (rowSum[i] ?? 0) - (rowSum[j] ?? 0)
                    if q < bestQ {
                        bestQ = q
                        bestI = i
                        bestJ = j
                    }
                }
            }
            guard bestI >= 0, bestJ >= 0 else { break }
            let dij = D[bestI][bestJ]
            let limbI = 0.5 * dij + ((rowSum[bestI] ?? 0) - (rowSum[bestJ] ?? 0)) / (2.0 * Double(m - 2))
            let limbJ = dij - limbI

            let newNode = labels.count
            // 负分支长度钳零必须计数并可被界面披露（NJ 距离非度量时会改变拓扑含义）
            let newLabel = "(\(labels[bestI]):\(String(format: "%.5f", clamp(limbI))),\(labels[bestJ]):\(String(format: "%.5f", clamp(limbJ))))"
            labels.append(newLabel)
            for k in active where k != bestI && k != bestJ {
                let dnk = (D[bestI][k] + D[bestJ][k] - dij) / 2.0
                D[newNode][k] = clamp(dnk)
                D[k][newNode] = D[newNode][k]
            }
            active.removeAll { $0 == bestI || $0 == bestJ }
            active.append(newNode)
        }

        let i = active[0], j = active.count > 1 ? active[1] : i
        let dij = D[i][j]
        let half = clamp(dij / 2)
        let tree = "(\(labels[i]):\(String(format: "%.5f", half)),\(labels[j]):\(String(format: "%.5f", half)));"
        return PhyloTreeResult(newick: withProvenance(tree), sequencesTotal: total,
                               sequencesUsed: n, clampedBranchLengths: clamped,
                               distanceModel: model)
    }

    /// 滑动窗口一致度：每列一致度（主频残基占比，空位不计）在窗口内平均，
    /// 返回 (窗口中心列, 平均一致度) 序列，步长 = window/2。
    static func slidingWindowIdentity(_ alignment: Alignment, window: Int) -> [(center: Int, identity: Double)] {
        windowAverages(from: AlignmentStatsCalculator.columnIdentities(alignment), window: window)
    }

    /// 从已计算的每列一致度直接求滑窗平均。
    /// identities 与窗口大小无关，调用方可按 (对象, revision) 缓存后反复调用本方法，
    /// 拖动 Slider 时不再触发全表重算。
    static func windowAverages(from identities: [Double], window: Int) -> [(center: Int, identity: Double)] {
        let n = identities.count
        guard n > 0, window >= 2 else { return [] }
        let w = min(window, n)
        let step = max(1, w / 2)
        var result: [(Int, Double)] = []
        var start = 0
        while start < n {
            let end = min(start + w, n)
            let slice = identities[start..<end]
            let avg = slice.reduce(0, +) / Double(slice.count)
            let center = (start + end - 1) / 2
            result.append((center, avg))
            if end >= n { break }
            start += step
        }
        return result
    }
}
