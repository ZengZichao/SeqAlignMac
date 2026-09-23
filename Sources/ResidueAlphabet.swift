//  ResidueAlphabet.swift
//  SeqAlignMac — 残基字符语义的单一事实来源
//
//  为什么需要本文件：
//  同一个字节（尤其是 '.'）在 6 种解析器里曾有 3 种行为（保留为残基 / 静默删除 /
//  判为非法），而所有分析代码只把 '-' 当空位，导致：
//    · PHYLIP 输入里的 '.' 被删 → 残基整体左移 → 列同源性被打断；
//    · 位点统计与 Seq Logo 用「核酸 IUPAC 简并集」过滤蛋白比对，把 D H K M N R S V Y
//      等标准氨基酸当成"状态未知"剔除；
//    · 全 N / 全 X 列的一致度算成 1.0，即"完全缺失 = 最保守"；
//    · 数据类型检测的核酸白名单不含 '.' '*' 0-9，把核酸比对误判为蛋白。
//  本文件把「什么算空位」「什么算状态未知」「什么算核酸合法字符」收敛为一处，
//  并按数据类型分叉，所有消费点（解析器、列统计、Logo、配色、判型）只向此处取数。

import Foundation

enum ResidueAlphabet {

    // MARK: - 空位（gap）

    /// 规范空位字节：模型内部一律以 '-' 存储空位。
    static let gap: UInt8 = 0x2D

    /// 各种"空位写法"：'-'（通用）、'.'（PHYLIP / seqboot / Gblocks / HMMER 插入列、
    /// 部分 Clustal 变体）、'~'（某些 Pfam Stockholm 输出）。
    /// 解析层统一把它们归一化为 '-'，因此下游只需判断规范空位。
    static func isGap(_ b: UInt8) -> Bool {
        b == 0x2D || b == 0x2E || b == 0x7E
    }

    /// 归一化：把任意空位写法折叠为规范空位 '-'（解析层统一处理）。
    static func normalize(_ b: UInt8) -> UInt8 { isGap(b) ? 0x2D : b }

    /// 残基串的规范空位字节数（列统计口径用）。
    static func gapCount(_ residues: [UInt8]) -> Int { residues.filter { isGap($0) }.count }

    // MARK: - 状态未知（不参与位点计量）

    /// 「无法判定性状」的符号集，按数据类型分叉。
    ///
    /// 核酸的"状态未知"集合按 IUPAC 简并码设计
    /// （N R Y S W K M B D H V X ? *），而位点计量与 Logo 不分数据类型地使用它，
    /// 于是蛋白比对里 20 种标准氨基酸中的 9 种（D H K M N R S V Y）被当成未知剔除，
    /// 变异位点 / 简约信息位点 / 单例位点与 Logo 信息量全部按"半个字母表"计算。
    ///
    /// - 核酸：简并码代表"尚不能确定是哪种碱基"，按惯例不计入性状（保持既有口径）。
    /// - 蛋白：B(Asx)/Z(Glx)/X(unknown)/?/`*`（终止，非氨基酸性状）为未知；
    ///   其余 20 种标准氨基酸一律是真实性状。
    static func unassignableStates(datatype: Datatype) -> Set<UInt8> {
        switch datatype {
        case .nucleicAcid:
            return nucleotideUnassignable
        case .aminoAcid:
            return aminoAcidUnassignable
        }
    }

    /// 核酸：N R Y S W K M B D H V X ? *
    static let nucleotideUnassignable: Set<UInt8> = [
        0x4E, 0x52, 0x59, 0x53, 0x57, 0x4B, 0x4D, 0x42, 0x44, 0x48, 0x56, 0x58, 0x3F, 0x2A
    ]

    /// 蛋白：B Z X ? *（含终止符；不含任何标准氨基酸单字母码）
    static let aminoAcidUnassignable: Set<UInt8> = [0x42, 0x5A, 0x58, 0x3F, 0x2A]

    /// 「完全无信息」的符号集：用于列一致度。
    /// 与 unassignableStates 的区别是刻意的：核酸简并码 R/Y/S/… 仍携带部分信息
    /// （一列全是 R 表示所有序列一致地判定为"嘌呤"），因此列一致度只把
    /// N / X / ?（以及蛋白的 B / Z）视为未判定，而 `*` 对核酸是真实的终止性状。
    static func undeterminedSymbols(datatype: Datatype) -> Set<UInt8> {
        switch datatype {
        case .nucleicAcid: return [0x4E, 0x58, 0x3F]           // N X ?
        case .aminoAcid:   return [0x58, 0x3F, 0x42, 0x5A]     // X ? B Z
        }
    }

    // MARK: - 核酸合法字符（数据类型判定）

    /// IUPAC 核酸码 + 空位写法 + 终止密码子 + 数字简并码（GCG 习惯）。
    /// 解析器明确接受 '.' '*' 0-9（`AlignmentParsers` 的 FASTA 白名单），
    /// 因此判型白名单必须同样包含它们，否则
    ///  · 用 '.' 作空位的核酸比对、
    ///  · 含终止密码子 '*' 的 CDS 比对、
    ///  · 含数字简并码的比对
    /// 都会在第一个越界字符处被判为蛋白，进而启用蛋白着色/蛋白歧义集、禁用 GC 与翻译。
    static let nucleotideCharacters: Set<UInt8> = {
        var set = Set("ACGTUNRYSWKMBDHV-.*".utf8)
        for b in UInt8(0x30)...UInt8(0x39) { set.insert(b) }   // 0-9（GCG 数字简并码）
        set.insert(0x3F)                                        // ? 缺失
        set.insert(0x7E)                                        // ~ 空位写法
        return set
    }()

    static func isNucleotideCharacter(_ b: UInt8) -> Bool { nucleotideCharacters.contains(b) }

    // MARK: - 缺失数据字符（解析层接受但语义为"未判定"）

    /// 解析器允许出现、且必须保留为"真实字节"的缺失/歧义记号
    /// （'?' 缺失；'.' 与 '~' 已在 normalize 里归一化为空位）。
    static let missingDataSymbols: Set<UInt8> = [0x3F]

    // MARK: - 序列名与 Newick 唯一名

    /// Newick 叶名安全化：空格、括号、冒号、逗号、分号一律换成下划线。
    static func newickSafeName(_ name: String) -> String {
        String(name.map { c in " (),:;".contains(c) ? "_" : c })
    }

    /// Newick 叶名唯一化：同名 tip 会让多数树解析器报错。
    /// 归一化后仍冲突时追加 "_2"、"_3" …
    static func uniqueNewickNames(_ names: [String]) -> [String] {
        var used = Set<String>()
        var out: [String] = []
        out.reserveCapacity(names.count)
        for raw in names {
            var base = newickSafeName(raw)
            if base.isEmpty { base = "seq" }
            var candidate = base
            var n = 2
            while used.contains(candidate) {
                candidate = "\(base)_\(n)"
                n += 1
            }
            used.insert(candidate)
            out.append(candidate)
        }
        return out
    }
}

// MARK: - 按块聚合的残基收集器

/// Clustal / MSF / Stockholm 都是"交错分块"布局：每个块内每条记录出现一次，
/// 块与块之间以空行分隔。不能用 `[名称: 残基]` 字典聚合——**同名序列会被首尾
/// 拼接成一条双倍长度的假序列**，再由 padToMaxLength 与 alignment.length 掩藏矛盾，
/// 全程无警告。读入侧与写出侧（唯一化）做同等检测。
///
/// 本收集器先按名称归属；当一个块里的行数与已有记录数相等时改按**行序**归属，
/// 这样同名重复记录也能各自拿到自己那一行。
struct BlockAwareResidueCollector {
    private struct Record { var name: String; var residues: [UInt8] }
    private var records: [Record] = []
    private var pendingBlock: [(name: String, residues: [UInt8])] = []

    /// 空行 = 块边界：先把攒下的这一行块归属完毕。
    mutating func beginBlock() { flush() }

    mutating func add(name: String, residues: [UInt8]) {
        pendingBlock.append((name, residues))
    }

    /// 收尾并返回结果（顺序 = 首次出现顺序）。
    mutating func finish() -> [(name: String, residues: [UInt8])] {
        flush()
        return records.map { ($0.name, $0.residues) }
    }

    private mutating func flush() {
        guard !pendingBlock.isEmpty else { return }
        if !records.isEmpty, pendingBlock.count == records.count {
            // 行序与记录序一致：按位置归属，同名记录各自拿到自己那一行
            for (i, line) in pendingBlock.enumerated() {
                records[i].residues.append(contentsOf: line.residues)
            }
        } else {
            var claimed = Set<Int>()
            for line in pendingBlock {
                var target: Int? = nil
                for i in records.indices where records[i].name == line.name && !claimed.contains(i) {
                    target = i
                    break
                }
                if let t = target {
                    records[t].residues.append(contentsOf: line.residues)
                    claimed.insert(t)
                } else {
                    // 同名重复出现：另起一条记录，而不是拼接
                    records.append(Record(name: line.name, residues: line.residues))
                    claimed.insert(records.count - 1)   // 本块内该名字已占用，再次出现仍是新记录
                }
            }
        }
        pendingBlock.removeAll()
    }
}

// MARK: - NEXUS 分区坐标重映射

/// CharsetInfo.ranges 是 1-based 闭区间，来自 NEXUS `BEGIN SETS`，并由写出器原样回写。
/// 任何改变列结构的操作（去除空位列、裁剪区间）都必须同步平移这些区间，
/// 否则导出的 CHARSET 会指向错误的列 —— 下游 MrBayes / RAxML / IQ-TREE 照单全收，
/// 结果看起来完全正常却建立在错误分区上。
enum CharsetRemapper {
    /// 删除若干列后，把区间平移/拆分到新的坐标系（removedColumns 为 0-based）。
    static func shift(_ charsets: [CharsetInfo], removedColumns: Set<Int>) -> [CharsetInfo] {
        guard !removedColumns.isEmpty else { return charsets }
        let removedSorted = removedColumns.sorted()
        func newIndex(_ oneBased: UInt32) -> UInt32? {
            let zero = Int(oneBased) - 1
            if removedColumns.contains(zero) { return nil }          // 该列已被删除
            let shifted = zero - removedSorted.filter { $0 < zero }.count
            return shifted < 0 ? nil : UInt32(shifted + 1)
        }
        return charsets.map { cs in
            var out: [(start: UInt32, end: UInt32)] = []
            for r in cs.ranges {
                var run: (start: UInt32, end: UInt32)? = nil
                for col in r.start...r.end {
                    guard let n = newIndex(col) else {
                        if let s = run { out.append(s); run = nil }
                        continue
                    }
                    if let s = run, s.end + 1 == n { run = (s.start, n) }
                    else { if let s = run { out.append(s) }; run = (n, n) }
                }
                if let s = run { out.append(s) }
            }
            var merged = out
            merged.sort { $0.start < $1.start }
            // 区间一旦平移，原始步长表达（1-60\3）不再等价，丢弃以免回写错坐标
            return CharsetInfo(name: cs.name, ranges: merged, originalSpec: nil)
        }
    }

    /// 裁剪出 [startCol, endCol]（0-based 闭区间）后重新平移到 1-based 新区间（CLI --start/--end 亦用）。
    static func crop(_ charsets: [CharsetInfo], startCol: Int, endCol: Int) -> [CharsetInfo] {
        guard !charsets.isEmpty else { return charsets }
        return charsets.map { cs in
            var out: [(start: UInt32, end: UInt32)] = []
            for r in cs.ranges {
                for col in Int(r.start)...Int(r.end) {
                    guard col >= startCol, col <= endCol else { continue }
                    let n = UInt32(col - startCol + 1)
                    if let last = out.last, last.end + 1 == n {
                        out[out.count - 1] = (last.start, n)
                    } else {
                        out.append((n, n))
                    }
                }
            }
            return CharsetInfo(name: cs.name, ranges: out, originalSpec: nil)
        }
    }
}

// MARK: - 比对来源是否"已比对"

/// 未比对序列被静默右补空位、当成已比对呈现，是本工具最容易产出错误结论的路径：
/// FASTA 是交换未比对序列的事实标准格式，打开一组长度不同的 FASTA 后，
/// 程序把它们左对齐右补 '-' 呈现为"比对"，随即在列同源性不成立的坐标上
/// 给出一致度、变异位点与 NJ 树，且界面毫无提示。
/// 这里记录解析期的判据（不改变模型，只让界面与下游能够明示这一状态）：
/// · 各序列长度不全等 → 一定不是已比对（比对要求等长）；
/// · 等长且没有任何内部空位 → 无法区分"未比对"与"恰好保守"，记为 unknown；
/// · 等长且含内部空位 → 与已比对特征一致，记为 true。
enum AlignmentProvenance {
    enum Status: String {
        case aligned = "aligned"                 // 等长且含内部空位：与已比对特征一致
        case unknown = "unknown"                 // 等长且无内部空位：无法判定
        case notAligned = "not-aligned"          // 长度不等：确定未比对（补齐前）
    }

    /// 依据原始（补齐前）序列长度与内部空位判定来源状态。
    static func status(ofRaggedSequences sequences: [Sequence]) -> Status {
        guard !sequences.isEmpty else { return .unknown }
        let lengths = sequences.map { $0.residues.count }
        guard let first = lengths.first, lengths.allSatisfy({ $0 == first }) else { return .notAligned }
        // 内部空位（不含首尾）是"比对插入/缺失"的特征
        let hasInternalGap = sequences.contains { seq in
            let r = seq.residues
            guard r.count > 2 else { return false }
            return r[1..<(r.count - 1)].contains(where: { ResidueAlphabet.isGap($0) })
        }
        return hasInternalGap ? .aligned : .unknown
    }
}
