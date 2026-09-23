//  AlignmentWriters.swift
//  SeqAlignMac — 格式写出器

import Foundation

struct AlignmentWriter {
    /// ASCII 解码：解析器只产出 ASCII 残基，但作为公共 API 不应静默丢整条序列；
    /// String(decoding:) 对越界字节产出替换字符而非返回 nil
    private static func asciiString(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// 残基串写出前归一化空位写法。模型内部应只存规范 '-'，但 Alignment 可由
    /// 调用方直接构造（含 '.' / '~'），若原样写进 NEXUS 会撞上 `MISSING=? GAP=-` 的声明，
    /// 写进 FASTA/PHYLIP 则读回时依赖解析器再归一化。写出侧同样归一化，两侧对称。
    private static func asciiResidues(_ bytes: [UInt8]) -> String {
        asciiString(bytes.map { ResidueAlphabet.normalize($0) })
    }

    /// 参差序列安全切片：Alignment.length 定义为各序列长度的最大值，模型层不保证
    /// 等长（padToMaxLength 需显式调用）。blockStart 越过行尾时不得构造
    /// `60..<30` 形式的非法区间（会 fatalError），不足处以 '-' 补齐到对齐长度。
    private static func paddedSlice(_ residues: [UInt8], from start: Int, to end: Int) -> [UInt8] {
        guard start < end else { return [] }
        if start < residues.count {
            let realEnd = min(end, residues.count)
            var out = Array(residues[start..<realEnd])
            if out.count < end - start {
                out.append(contentsOf: [UInt8](repeating: 0x2D, count: end - start - out.count))
            }
            return out
        }
        return [UInt8](repeating: 0x2D, count: end - start)
    }

    // MARK: - FASTA
    static func writeFasta(_ alignment: Alignment, wrapWidth: Int = 0) -> Data {
        var output = ""
        output.reserveCapacity(alignment.sequences.reduce(0) { $0 + $1.residues.count + 32 })
        for seq in alignment.sequences {
            let header = seq.description.isEmpty ? ">\(seq.name)\n" : ">\(seq.name) \(seq.description)\n"
            output += header
            let residues = asciiResidues(seq.residues)
            if wrapWidth > 0 {
                var idx = residues.startIndex
                while idx < residues.endIndex {
                    let end = residues.index(idx, offsetBy: wrapWidth, limitedBy: residues.endIndex) ?? residues.endIndex
                    output += String(residues[idx..<end]) + "\n"
                    idx = end
                }
            } else {
                output += residues + "\n"
            }
        }
        return output.data(using: .utf8) ?? Data()
    }

    // MARK: - NEXUS
    /// NEXUS 名称安全化：含标点/空白的名称按规范用单引号包裹（转义内部单引号），
    /// 否则 TAXLABELS/MATRIX 产出非法 NEXUS。
    private static func nexusSafeName(_ name: String) -> String {
        let needsQuote = name.isEmpty
            || name.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))) == nil
            || name.rangeOfCharacter(from: CharacterSet(charactersIn: " \t'\"()[]{},;:=")) != nil
        if needsQuote {
            return "'" + name.replacingOccurrences(of: "'", with: "''") + "'"
        }
        return name
    }

    static func writeNexus(_ alignment: Alignment, includeMetadata: Bool = true) -> Data {
        var output = "#NEXUS\n\n"
        let ntax = alignment.seqCount
        let nchar = alignment.length
        let dtypeStr = alignment.datatype == .nucleicAcid ? "DNA" : "PROTEIN"
        let safeNames = alignment.sequences.map { nexusSafeName($0.name) }
        // 名称列宽只做补齐不做截断：截断会与 TAXLABELS 全名失配，
        // 两条序列前 20 字符相同时 MATRIX 行不可区分（PAUP/MrBayes 静默错位关联）
        let nameWidth = max(20, safeNames.map { $0.count }.max() ?? 20)

        output += "BEGIN TAXA;\n"
        output += "  DIMENSIONS NTAX=\(ntax);\n"
        output += "  TAXLABELS \(safeNames.joined(separator: " "));\n"
        output += "END;\n\n"

        output += "BEGIN CHARACTERS;\n"
        output += "  DIMENSIONS NCHAR=\(nchar);\n"
        output += "  FORMAT DATATYPE=\(dtypeStr) MISSING=? GAP=-;\n"
        output += "  MATRIX\n"
        for (safeName, seq) in zip(safeNames, alignment.sequences) {
            let padded = safeName.count < nameWidth ? safeName + String(repeating: " ", count: nameWidth - safeName.count) : safeName
            // 矩阵行必须与 DIMENSIONS NCHAR 声明一致：参差比对（正是翻译 ignoreGaps
            // 模式的产物）行长短不一，若直写 seq.residues，
            // 产出的 NEXUS 会被 Mesquite/MrBayes/PAUP 判为维度不符或按缺失解读。
            output += "    \(padded)\(asciiResidues(paddedSlice(seq.residues, from: 0, to: nchar)))\n"
        }
        output += "  ;\n"
        output += "END;\n"

        if includeMetadata && !alignment.charsets.isEmpty {
            output += "\nBEGIN SETS;\n"
            for cs in alignment.charsets {
                // 未发生列重映射时原样回写 `1-60\3` 这类步长定义，
                // 不把它展开成语法有效但丢失步长的 "1-1 4-4 7-7 …"
                let body = cs.originalSpec ?? cs.ranges.map { "\($0.start)-\($0.end)" }.joined(separator: " ")
                output += "  CHARSET \(cs.name) = \(body);\n"
            }
            output += "END;\n"
        }
        return output.data(using: .utf8) ?? Data()
    }

    /// PHYLIP 名称字段：截断到 `nameColumns` 字符并补齐，保证唯一。
    ///
    /// strict10Char / sequential 变体改用 `nameColumns = 9`，即在名称字段之后
    /// 恒定写出一个空格作为分隔列：若把名称补齐到"恰好 10 字符后紧接残基"，
    /// 名称满 10 字符时第 10 列就是名称最后一个字符、没有任何分隔符
    /// （GenBank accession `AF123456.1` 正好 10 字符），于是本软件自己写出的文件
    /// 无法被本软件自己的解析器读回：整行被当成名称、残基为空，随后 padToMaxLength
    /// 把每条序列补齐成整行空位 —— 一棵比对被静默替换为全空位。
    private static func phylipUniqueName(_ name: String, used: inout Set<String>,
                                         nameColumns: Int = 10) -> String {
        let trimmed = String(name.prefix(nameColumns))
        let base = trimmed.padding(toLength: nameColumns, withPad: " ", startingAt: 0)
        if !used.contains(base) {
            used.insert(base)
            return base
        }
        var n = 1
        while true {
            let suffix = ".\(n)"
            let cand = (String(name.prefix(max(0, nameColumns - suffix.count))) + suffix)
                .padding(toLength: nameColumns, withPad: " ", startingAt: 0)
            if !used.contains(cand) {
                used.insert(cand)
                return cand
            }
            n += 1
        }
    }

    /// MSF 名称唯一化——不截断名称，但同名序列追加后缀避免往返合并。
    /// MSF 解析器按名称聚合（nameToSeq[name]?.append），同名序列会被合并。
    private static func msfUniqueName(_ name: String, used: inout Set<String>) -> String {
        if !used.contains(name) {
            used.insert(name)
            return name
        }
        var n = 1
        while true {
            let candidate = "\(name)_\(n)"
            if !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
            n += 1
        }
    }

    // MARK: - PHYLIP
    static func writePhylip(_ alignment: Alignment, variant: PhylipVariant = .interleaved) -> Data {
        let ntax = alignment.seqCount
        let nchar = alignment.length
        var output = "\(ntax) \(nchar)\n"

        switch variant {
        case .fullnamePadded:
            // 全名变体：名称 + 2 空格 + 全序列单行（名称 > 10 字符时下游需按空白解析）
            for seq in alignment.sequences {
                // 同样按声明的 nchar 写满，参差行会让 NCHAR 与实际残基数不符
                output += "\(seq.name)  \(asciiResidues(paddedSlice(seq.residues, from: 0, to: nchar)))\n"
            }
        case .sequential:
            // 真正的 sequential 变体：名称占前 9 列 + 第 10 列为分隔空格，序列按 60/行换行续写，
            // 续行顶格 10 个空格后接残基（不带名称）。
            var used: Set<String> = []
            for seq in alignment.sequences {
                let name = phylipUniqueName(seq.name, used: &used, nameColumns: 9)
                // 残基串按声明长度取，短行补 '-'，保证 nchar 与实写残基一致
                let residues = asciiResidues(paddedSlice(seq.residues, from: 0, to: nchar))
                var idx = residues.startIndex
                var firstLine = true
                while idx < residues.endIndex || firstLine {
                    // 首行 = 9 列名称 + 1 列分隔空格；续行 = 10 列空白（真正的 sequential 布局：
                    // 续行不带名称，仅靠列位对齐）
                    output += firstLine ? (name + " ") : String(repeating: " ", count: 10)
                    firstLine = false
                    let end = residues.index(idx, offsetBy: 60, limitedBy: residues.endIndex) ?? residues.endIndex
                    output += String(residues[idx..<end]) + "\n"
                    idx = end
                    if idx >= residues.endIndex { break }
                }
            }
        case .strict10Char:
            var used: Set<String> = []
            for seq in alignment.sequences {
                let name = phylipUniqueName(seq.name, used: &used, nameColumns: 9)
                // 名称字段 9 列 + 1 列空格分隔，再紧跟残基（仍严格等宽 10 列头部）
                output += "\(name) \(asciiResidues(paddedSlice(seq.residues, from: 0, to: nchar)))\n"
            }
        case .interleaved:
            var used: Set<String> = []
            let names = alignment.sequences.map { phylipUniqueName($0.name, used: &used) }
            let blockSize = 60
            for blockStart in stride(from: 0, to: nchar, by: blockSize) {
                let blockEnd = min(blockStart + blockSize, nchar)
                for (name, seq) in zip(names, alignment.sequences) {
                    let slice = paddedSlice(seq.residues, from: blockStart, to: blockEnd)
                    let residues = asciiResidues(slice)
                    if blockStart == 0 {
                        output += "\(name)  \(residues)\n"
                    } else {
                        output += String(repeating: " ", count: 12) + residues + "\n"
                    }
                }
                output += "\n"
            }
        }
        return output.data(using: .utf8) ?? Data()
    }

    // MARK: - CLUSTAL
    /// ClustalX 标准保守组：'*' 全同，':' 强保守组，'.' 弱保守组。
    ///
    /// 本组表只对**蛋白**有意义，不得用于核酸比对：核酸比对里
    /// 一列只有 A 和 T（A/T 颠换，最不保守的情形之一）会因为蛋白弱保守组 ["A","T","V"]
    /// 而被标成 '.'（半保守）——导出的保守行是假的。现在核酸列走核酸判据。
    ///
    /// 同时修掉抄录错误：旧强保守表里 ["M","I","L","M"] 重复 M 缺 V（应为 IVL），
    /// ["F","Y","N"] 应为 FYW。以下强/弱组采用 Clustal X 文档化的保守判据：
    /// 强保守 STA / EQD / ARK / IVL / CM / GY / FYW；
    /// 弱保守 LA / LQ / KR / AC / AT / DKT / EG / FY / ND / NEQ / NGR / QRT / RQ / SAG。
    private static let clustalStrongGroups: [[Character]] = [
        ["S", "T", "A"], ["E", "Q", "D"], ["A", "R", "K"], ["I", "V", "L"],
        ["C", "M"], ["G", "Y"], ["F", "Y", "W"],
    ]
    private static let clustalWeakGroups: [[Character]] = [
        ["L", "A"], ["L", "Q"], ["K", "R"], ["A", "C"], ["A", "T"], ["D", "K", "T"],
        ["E", "G"], ["F", "Y"], ["N", "D"], ["N", "E", "Q"], ["N", "G", "R"],
        ["Q", "R", "T"], ["R", "Q"], ["S", "A", "G"],
    ]
    /// 核酸强保守组：嘌呤之间、嘧啶之间（转换类替换在 Clustal 的核酸模式下视为半保守）
    private static let clustalNucleotideStrongGroups: [[Character]] = [
        ["C", "T", "U"], ["A", "G"],
    ]

    private static func clustalConsensusSymbol(_ colRes: [UInt8], datatype: Datatype) -> Character {
        let nonGap = colRes.filter { !ResidueAlphabet.isGap($0) }
        if nonGap.isEmpty { return " " }
        let chars = nonGap.map { Character(UnicodeScalar($0)) }
        if chars.allSatisfy({ $0 == chars[0] }) { return "*" }
        if datatype == .nucleicAcid {
            // 核酸：只有"全为嘌呤 / 全为嘧啶"这类真实替代关系记 ':'；
            // 同一半可判定残基占多数时记 '.'；否则空白（不再借用蛋白理化基团）。
            if clustalNucleotideStrongGroups.contains(where: { grp in chars.allSatisfy { grp.contains($0) } }) { return ":" }
            // 不再给核酸列打 '.'：'.': 半保守在 Clustal 的蛋白表里含义是"同基团内替换"，
            // 核酸侧若按"多数相同"打点，会让 A/T 颠换列（最不保守的情形之一）得到保守点，
            // 那是假信号。核酸保守行只保留 '*'（全同）与 ':'（嘌呤/嘧啶类内）。
            return " "
        }
        if clustalStrongGroups.contains(where: { grp in chars.allSatisfy { grp.contains($0) } }) { return ":" }
        if clustalWeakGroups.contains(where: { grp in chars.allSatisfy { grp.contains($0) } }) { return "." }
        return " "
    }

    static func writeClustal(_ alignment: Alignment, withConsensus: Bool = false) -> Data {
        var output = "CLUSTAL W (1.0) multiple sequence alignment\n\n"
        let blockSize = 60
        let nameWidth = max(20, alignment.sequences.map { $0.name.count }.max() ?? 20)

        for blockStart in stride(from: 0, to: alignment.length, by: blockSize) {
            let blockEnd = min(blockStart + blockSize, alignment.length)
            for seq in alignment.sequences {
                let name = seq.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
                let slice = paddedSlice(seq.residues, from: blockStart, to: blockEnd)
                let residues = asciiResidues(slice)
                output += "\(name) \(residues)\n"
            }
            if withConsensus {
                var cons = ""
                for col in blockStart..<blockEnd {
                    cons.append(clustalConsensusSymbol(alignment.columnResidues(col: col),
                                                       datatype: alignment.datatype))
                }
                output += String(repeating: " ", count: nameWidth + 1) + cons + "\n"
            }
            output += "\n"
        }
        return output.data(using: .utf8) ?? Data()
    }

    // MARK: - MSF
    /// GCG 校验和：Σ (i % 57 + 1) × ASCII(残基)，对 10000 取模
    private static func gcgChecksum(_ residues: [UInt8]) -> Int {
        var sum = 0
        for (i, b) in residues.enumerated() {
            sum += ((i % 57) + 1) * Int(b)
        }
        return sum % 10000
    }

    static func writeMsf(_ alignment: Alignment, msfType: MsfType? = nil) -> Data {
        let type = msfType ?? (alignment.datatype == .aminoAcid ? MsfType.aa : MsfType.na)
        let header = type == .aa ? "!!AA_MULTIPLE_ALIGNMENT" : "!!NA_MULTIPLE_ALIGNMENT"
        let typeStr = type == .aa ? "P" : "N"
        let nchar = alignment.length
        // GCG 规范：MSF: 字段为校验和（全序列校验和之和 mod 10000），
        // 写成序列数会被严格工具拒绝
        let totalChecksum = alignment.sequences.reduce(0) { $0 + gcgChecksum($1.residues) } % 10000

        // MSF 名称安全化——padding(toLength:20) 对超长名称做截断，
        // 往返后同名序列合并、残基首尾拼接。改为不截断 + 唯一化（复用 phylipUniqueName 思路）
        var msfUsedNames: Set<String> = []
        let safeNames = alignment.sequences.map { seq -> String in
            msfUniqueName(seq.name, used: &msfUsedNames)
        }
        // MSF 名称列宽取 max(20, 最长名)，对齐保持但不截断
        let msfNameWidth = max(20, safeNames.map { $0.count }.max() ?? 20)

        var output = "\(header)\n\n"
        output += "  MSF: \(totalChecksum)  Type: \(typeStr)  Len: \(nchar)  Check: \(totalChecksum)  ..\n\n"

        for (i, seq) in alignment.sequences.enumerated() {
            let name = safeNames[i].padding(toLength: msfNameWidth, withPad: " ", startingAt: 0)
            output += " Name: \(name) Len: \(seq.residues.count)  Check: \(String(format: "%4d", gcgChecksum(seq.residues)))  Weight: 1.00\n"
        }
        output += "\n//\n\n"

        let blockSize = 10
        for blockStart in stride(from: 0, to: nchar, by: 50) {
            let blockEnd = min(blockStart + 50, nchar)
            for (i, seq) in alignment.sequences.enumerated() {
                let name = safeNames[i].padding(toLength: msfNameWidth, withPad: " ", startingAt: 0)
                var resStr = ""
                for j in stride(from: blockStart, to: blockEnd, by: blockSize) {
                    let segEnd = min(j + blockSize, blockEnd)
                    let slice = paddedSlice(seq.residues, from: j, to: segEnd)
                    if !resStr.isEmpty { resStr += " " }
                    resStr += asciiResidues(slice)
                }
                output += "\(name) \(resStr)\n"
            }
            output += "\n"
        }
        return output.data(using: .utf8) ?? Data()
    }

    // MARK: - Stockholm（Pfam/Rfam/HMMER 标准）
    static func writeStockholm(_ alignment: Alignment, accession: String? = nil) -> Data {
        var output = "# STOCKHOLM 1.0\n\n"
        if let ac = accession ?? alignment.metadata["AC"] {
            output += "#=GF AC \(ac)\n"
        }
        if let id = alignment.metadata["ID"] {
            output += "#=GF ID \(id)\n"
        }
        output += "#=GF SQ \(alignment.seqCount)\n\n"

        let blockSize = 80
        for blockStart in stride(from: 0, to: alignment.length, by: blockSize) {
            let blockEnd = min(blockStart + blockSize, alignment.length)
            for seq in alignment.sequences {
                let slice = paddedSlice(seq.residues, from: blockStart, to: blockEnd)
                let residues = asciiResidues(slice)
                output += "\(seq.name.replacingOccurrences(of: " ", with: "_")) \(residues)\n"
            }
            output += "\n"
        }
        output += "//\n"
        return output.data(using: .utf8) ?? Data()
    }

    // MARK: - FASTQ
    /// 真正的 FASTQ 写出（Phred+33）。FASTQ 来源保存不再降级为 FASTA、
    /// 丢弃质量值。质量行按残基长度对齐：缺失/不足补 '!'（Q0），越界钳制到 93，
    /// 保证记录四行结构与「残基长度 == 质量长度」这一 FASTQ 硬约束。
    static func writeFastq(_ alignment: Alignment) -> Data {
        var output = ""
        output.reserveCapacity(alignment.sequences.reduce(0) { $0 + $1.residues.count * 2 + 32 })
        for seq in alignment.sequences {
            let header = seq.description.isEmpty ? "@\(seq.name)\n" : "@\(seq.name) \(seq.description)\n"
            output += header
            output += asciiResidues(seq.residues) + "\n+\n"
            let n = seq.residues.count
            let q = seq.quality ?? []
            var qChars = [UInt8](repeating: 0x21, count: n)   // 默认 '!' = Q0
            for i in 0..<min(n, q.count) {
                qChars[i] = 0x21 + min(q[i], 93)              // Phred+33，上限 93
            }
            output += asciiString(qChars) + "\n"
        }
        return output.data(using: .utf8) ?? Data()
    }
}
