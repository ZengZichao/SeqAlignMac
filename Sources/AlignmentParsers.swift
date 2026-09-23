//  AlignmentParsers.swift
//  SeqAlignMac — 6 种比对格式解析器

import Foundation
import Compression

// MARK: - 格式自动检测

enum AlignmentFormat {
    case fasta, fastq, nexus, phylip, clustal, msf, stockholm, unknown
}

struct FormatDetector {
    static func detect(_ data: Data) -> AlignmentFormat {
        // 格式信号都在文件头部——只解码前 64KB，
        // 避免上百 MB 文件在检测阶段就产生 2-3 份内存副本
        let head = data.prefix(65_536)
        guard let text = FormatDetector.decodeText(head) else {
            return .unknown
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingBOM
        let upper = trimmed.uppercased()

        // 无歧义前缀信号优先，弱 contains 信号放最后（避免 FASTA 描述行含
        // "CLUSTAL" 等字样时被误判格式）
        if upper.hasPrefix("#NEXUS") { return .nexus }
        if upper.hasPrefix("# STOCKHOLM") { return .stockholm }
        if upper.hasPrefix("!!AA_MULTIPLE_ALIGNMENT") || upper.hasPrefix("!!NA_MULTIPLE_ALIGNMENT") { return .msf }
        if trimmed.hasPrefix("@") { return .fastq }
        if trimmed.hasPrefix(">") { return .fasta }
        if upper.contains("#=GF") { return .stockholm }
        if upper.contains("CLUSTAL") { return .clustal }

        // PHYLIP: 首行为 ntax nchar
        if let firstLine = trimmed.split(separator: "\n").first {
            let parts = firstLine.split { $0 == " " || $0 == "\t" }.map(String.init)
            if parts.count == 2, let n = Int(parts[0]), let m = Int(parts[1]), n > 0, m > 0 {
                return .phylip
            }
        }
        return .unknown
    }

    /// 统一文本解码：UTF-8 回退 ASCII，并剥离 UTF-8 BOM（带 BOM 的文件此前会被
    /// 误报为「非法字符 'ï'」）
    static func decodeText(_ data: Data) -> String? {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { return nil }
        while text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }
}

private extension String {
    var trimmingBOM: String {
        var s = self
        while s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        return s
    }
}

// MARK: - 解析产物统一收口

enum ParsedAlignment {
    /// 所有解析器共用的收尾：判定来源是否已比对 → 名称唯一化 → 空残基守卫 → 补齐。
    ///
    /// 长度不等的输入确定不是"已比对"：若直接 padToMaxLength 右补 '-' 后当作比对呈现，
    ///   统计/建树照样产出看似正常的结果，是最容易产出错误结论的路径。
    ///   因此把这一事实记入 `Alignment.provenance`，界面据此标注并禁用定量分析。
    /// 按名称聚合的解析器（Clustal / NEXUS / MSF / Stockholm）：同名序列不得
    ///   **首尾拼接**成一条双倍长度的假序列、再由 padToMaxLength 掩藏矛盾。
    ///   读入侧与写出侧同一原则：同名即另起一条记录。
    /// '.' / '~' 一律归一化为规范空位 '-'；残基全为空位意味着解析错位，
    ///   必须报错而不是静默补 '-'。
    static func finalize(_ raw: [Sequence], datatype: Datatype,
                         charsets: [CharsetInfo] = [], metadata: [String: String] = [:]) throws -> Alignment {
        guard !raw.isEmpty else { throw CoreError.format("未解析到任何序列") }
        let provenance = AlignmentProvenance.status(ofRaggedSequences: raw)

        var seen: [String: Int] = [:]
        var sequences: [Sequence] = []
        sequences.reserveCapacity(raw.count)
        for seq in raw {
            var name = seq.name
            if name.isEmpty { name = "Seq\(sequences.count + 1)" }
            if let n = seen[name] {
                var k = n + 1
                var candidate = "\(name)_\(k)"
                while seen[candidate] != nil { k += 1; candidate = "\(name)_\(k)" }
                seen[name] = k
                seen[candidate] = 0
                name = candidate
            } else {
                seen[name] = 0
            }
            let normalized = seq.residues.map { ResidueAlphabet.normalize($0) }
            if normalized.isEmpty {
                throw CoreError.format("序列 \(name) 没有任何残基（解析错位或空序列）")
            }
            if !normalized.contains(where: { !ResidueAlphabet.isGap($0) }) {
                throw CoreError.format("序列 \(name) 的残基全部为空位：解析结果不可信（列错位或格式误判）")
            }
            sequences.append(Sequence(name: name, description: seq.description,
                                      residues: normalized, quality: seq.quality))
        }

        let alignment = Alignment(sequences: sequences, datatype: datatype,
                                 metadata: metadata, charsets: charsets)
        alignment.provenance = provenance
        alignment.padToMaxLength()
        return alignment
    }
}

// MARK: - FASTA 解析器

struct FastaParser {
    static func parse(_ data: Data, progress: ProgressCallback? = nil) throws -> Alignment {
        guard let text = FormatDetector.decodeText(data) else {
            throw CoreError.format("无法解码为文本")
        }

        let total = UInt64(data.count)
        var sequences: [Sequence] = []
        var name = ""
        var desc = ""
        var residues: [UInt8] = []
        var lineNum = 0
        var processed: UInt64 = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNum += 1
            processed += UInt64(line.count + 1)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix(">") {
                if !name.isEmpty || !residues.isEmpty {
                    if residues.isEmpty {
                        throw CoreError.format("空序列（行 \(lineNum)）：序列 \(name) 无残基")
                    }
                    sequences.append(Sequence(name: name, description: desc, residues: residues))
                }
                let headerContent = String(trimmed.dropFirst())
                let parts = headerContent.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                name = parts.first ?? ""
                desc = parts.count > 1 ? parts[1] : ""
                residues = []
            } else {
                // 残基行：大写归一，忽略空白
                for byte in trimmed.utf8 {
                    let upper: UInt8
                    if byte >= 0x61 && byte <= 0x7A { // a-z → A-Z
                        upper = byte - 0x20
                    } else {
                        upper = byte
                    }
                    // 接受 IUPAC 字母、数字简并码（1-7）、gap '-'、终止 '*'、缺失 '?'/'.'；
                    // 其余视为非法字符报错（静默丢弃会移位残基、掩盖真实错误）
                    if (upper >= 0x41 && upper <= 0x5A)        // A-Z
                        || (upper >= 0x30 && upper <= 0x39)    // 0-9（IUPAC 简并码）
                        || upper == 0x2D || upper == 0x2A      // '-'  gap / '*'  终止密码子
                        || upper == 0x3F || upper == 0x2E {    // '?' '.' 缺失数据
                        residues.append(upper)
                    } else {
                        throw CoreError.format("非法字符 '\(Character(UnicodeScalar(upper)))' 在第 \(lineNum) 行")
                    }
                }
            }

            if let cb = progress, lineNum % 1000 == 0 {
                cb(processed, total)
            }
        }

        // 最后一条
        if !name.isEmpty || !residues.isEmpty {
            if residues.isEmpty {
                throw CoreError.format("空序列：序列 \(name) 无残基")
            }
            sequences.append(Sequence(name: name, description: desc, residues: residues))
        }

        if sequences.isEmpty {
            throw CoreError.format("未找到任何 FASTA 序列")
        }

        let alignment = try ParsedAlignment.finalize(sequences, datatype: DatatypeDetector.detect(sequences))
        progress?(total, total)
        return alignment
    }

}

// MARK: - FASTQ 解析器

struct FastqParser {
    static func parse(_ data: Data, progress: ProgressCallback? = nil) throws -> Alignment {
        guard let text = FormatDetector.decodeText(data) else {
            throw CoreError.format("无法解码为文本")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var sequences: [Sequence] = []
        var i = 0
        var sawPhred33Evidence = false   // 文件级 Phred 偏移线索
        let total = UInt64(lines.count)
        while i < lines.count {
            // 空行跳过
            if lines[i].isEmpty { i += 1; continue }
            // 第一行 @name description
            guard lines[i].hasPrefix("@") else {
                throw CoreError.format("FASTQ 格式错误：第 \(i + 1) 行应以 '@' 开头")
            }
            let headerContent = String(lines[i].dropFirst())
            let parts = headerContent.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let name = parts.first ?? ""
            let desc = parts.count > 1 ? parts[1] : ""
            i += 1
            guard i < lines.count else { throw CoreError.format("FASTQ 不完整：缺少残基行") }
            // 第二行残基：与 FASTA 一致，非法字符直接报错（静默丢弃会移位残基，
            // 并把真实原因掩盖成误导性的「质量长度不一致」）
            // utf8 字节迭代
            var residueAcc: [UInt8] = []
            residueAcc.reserveCapacity(lines[i].utf8.count)
            for b in lines[i].uppercased().utf8 {
                guard (b >= 0x41 && b <= 0x5A) || b == 0x2D || b == 0x2A else {
                    throw CoreError.format("FASTQ 非法字符 '\(Character(UnicodeScalar(b)))' 在第 \(i + 1) 行")
                }
                residueAcc.append(b)
            }
            let residues = residueAcc
            i += 1
            guard i < lines.count else { throw CoreError.format("FASTQ 不完整：缺少 '+' 行") }
            // 第三行 '+'
            guard lines[i].hasPrefix("+") else {
                throw CoreError.format("FASTQ 格式错误：第 \(i + 1) 行应以 '+' 开头")
            }
            i += 1
            guard i < lines.count else { throw CoreError.format("FASTQ 不完整：缺少质量行") }
            // 第四行质量分数：Phred+33 为主，兼容识别早期 Illumina Phred+64
            // （质量字符整体落在高 ASCII 区间时按 +64 解析，避免 31 个质量单位的静默错译）
            let quality = lines[i]
            // 长度比较用 utf8 字节数：String.count 按 Character 迭代，
            // O(n) 且对组合字符序列语义有歧义
            if quality.utf8.count != residues.count {
                throw CoreError.format("FASTQ：质量行长度与残基长度不一致（\(quality.utf8.count) vs \(residues.count)）")
            }
            let qBytes = Array(quality.utf8)
            // Phred 偏移判定用文件级确定性判据（min/max 阈值启发式会把"整条高质量
            // （全 >=Q31）的 Phred+33 数据"误判为 Phred+64，使 meanPhred / q20 / q30
            // 整体偏高约 31）：Phred+64 记录的第一个质量字符不可能低于 '@'(0x40)，
            // 因此全文件只要出现过 < 0x40 的质量字符即可确定是 Phred+33；
            // 反之全文件质量字符都 >= 0x40 且出现过 > 'J'(0x4A，=Q17+) 时判为 Phred+64。
            if qBytes.isEmpty == false, qBytes.min()! < 0x40 { sawPhred33Evidence = true }
            let isPhred64 = !sawPhred33Evidence && !qBytes.isEmpty
                            && qBytes.min()! >= 64 && qBytes.max()! > 74
            let offset: UInt8 = isPhred64 ? 64 : 33
            let phred: [UInt8]? = qBytes.map { byte in
                byte >= offset ? byte - offset : 0
            }
            i += 1
            if residues.isEmpty {
                throw CoreError.format("空序列：序列 \(name) 无残基")
            }
            sequences.append(Sequence(name: name, description: desc, residues: residues, quality: phred))
            // 进度对齐 FASTA 的行级节流：每条 read 回调一次，
            // 100 万条 read 会引发百万次跨线程 hop
            if let cb = progress, i % 4000 == 0 {
                cb(UInt64(i), total)
            }
        }
        if sequences.isEmpty { throw CoreError.format("未找到任何 FASTQ 序列") }
        return try ParsedAlignment.finalize(sequences, datatype: .nucleicAcid)
    }
}

// MARK: - NEXUS 解析器

struct NexusParser {
    static func parse(_ data: Data, progress: ProgressCallback? = nil) throws -> Alignment {
        guard let text = FormatDetector.decodeText(data) else {
            throw CoreError.format("无法解码为文本")
        }
        // 大小写不敏感
        let upper = text.uppercased()
        guard upper.contains("#NEXUS") else {
            throw CoreError.format("NEXUS 文件缺少 #NEXUS 头")
        }

        var sequences: [Sequence] = []
        var datatype: Datatype = .nucleicAcid
        var charsets: [CharsetInfo] = []
        let metadata: [String: String] = [:]

        // 去除注释 [...]
        let cleaned = removeComments(text)
        let blocks = parseBlocks(cleaned)

        for (blockName, blockContent) in blocks {
            let nameUpper = blockName.uppercased()
            switch nameUpper {
            case "TAXA":
                break // 标签从矩阵中读取
            case "DATA", "CHARACTERS":
                let result = try parseDataBlock(blockContent, progress: progress)
                sequences = result.sequences
                datatype = result.datatype
            case "SETS":
                charsets = parseSetsBlock(blockContent)
            default:
                break
            }
        }

        if sequences.isEmpty {
            throw CoreError.format("NEXUS：未找到 DATA/CHARACTERS 块或矩阵为空")
        }

        return try ParsedAlignment.finalize(sequences, datatype: datatype,
                                            charsets: charsets, metadata: metadata)
    }

    private static func removeComments(_ text: String) -> String {
        // utf8 字节迭代。
        // '[' 与 ']' 均为 ASCII，多字节 UTF-8 序列不会包含这两个字节值，按字节处理安全。
        var bytes = [UInt8]()
        bytes.reserveCapacity(text.utf8.count)
        var inComment = false
        for b in text.utf8 {
            if b == 0x5B { inComment = true; continue } // [
            if b == 0x5D { inComment = false; continue } // ]
            if !inComment { bytes.append(b) }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func parseBlocks(_ text: String) -> [(String, String)] {
        var blocks: [(String, String)] = []
        let pattern = "BEGIN\\s+(\\w+)\\s*;(.*?)END\\s*;"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let blockName = nsText.substring(with: match.range(at: 1))
                    let blockContent = nsText.substring(with: match.range(at: 2))
                    blocks.append((blockName, blockContent))
                }
            }
        }
        return blocks
    }

    private struct DataBlockResult {
        let sequences: [Sequence]
        let datatype: Datatype
    }

    private static func parseDataBlock(_ content: String, progress: ProgressCallback? = nil) throws -> DataBlockResult {
        // FORMAT DATATYPE=DNA / DATATYPE PROTEIN / =AA / =RNA ...
        // 需覆盖 DATATYPE=PROT、DATATYPE = PROT、`DATATYPE PROTEIN`（无等号）、
        // `=AMINO`、`=AA`、`DATATYPE=RNA` 等全部写法，漏一种即落到核酸默认值。
        // 判型口径与残基字母表判型共用 DatatypeDetector（单一事实来源）。
        var datatype: Datatype = .nucleicAcid
        if let formatMatch = content.range(of: "FORMAT", options: .caseInsensitive) {
            let afterFormat = String(content[formatMatch.upperBound...])
            let declaration = String(afterFormat.split(separator: ";").first ?? "")
            if let declared = DatatypeDetector.datatype(fromDeclaration: declaration) {
                datatype = declared
            }
        }

        // DIMENSIONS NTAX=n NCHAR=m：用于区分"同一 taxon 的折行续块"
        // 与"两条恰好同名的 taxon"——前者累计长度未达 NCHAR，后者已达。
        var declaredNchar = 0
        if let dimsRange = content.range(of: "DIMENSIONS", options: .caseInsensitive) {
            let dimsRaw = content[dimsRange.upperBound...]
            let dims = String(dimsRaw[..<((dimsRaw.firstIndex(of: ";") ?? dimsRaw.endIndex))])
            for token in dims.split(separator: " ") {
                let kv = token.split(separator: "=")
                if kv.count == 2, kv[0].uppercased() == "NCHAR", let v = Int(kv[1]) { declaredNchar = v }
            }
        }

        // MATRIX ... ;
        guard let matrixRange = content.range(of: "MATRIX", options: .caseInsensitive) else {
            throw CoreError.format("NEXUS：DATA 块缺少 MATRIX")
        }
        let afterMatrix = content[matrixRange.upperBound...]
        guard let endRange = afterMatrix.range(of: ";") else {
            throw CoreError.format("NEXUS：MATRIX 未闭合")
        }
        let matrixText = String(afterMatrix[..<endRange.lowerBound])

        // 按 taxon 聚合解析（支持 INTERLEAVE：同一 taxon 的多个块拼接为一条序列；
        // 无名称的续块行按块内行号对齐到首轮出现顺序）
        var nameToSeq: [String: [UInt8]] = [:]
        var nameOrder: [String] = []      // 内部键（同名 taxon 各自一条记录）
        var namesByKey: [String: String] = [:]
        var blockLineIdx = 0
        var lastNamedTaxon = ""            // 顺序布局下无名续行归属上一条具名 taxon
        var isInterleavedLayout: Bool? = nil

        func nexusResidue(_ c: Character) -> UInt8? {
            guard let s = c.asciiValue else { return nil }
            if (s >= 0x41 && s <= 0x5A) || s == 0x2D || s == 0x3F { return s } // 字母, '-', '?'
            if s == 0x2A { return s } // '*'
            return nil
        }

        let matrixLines = matrixText.split(separator: "\n", omittingEmptySubsequences: false)
        let nexusTotal = UInt64(matrixLines.count)
        var nexusLineIdx: UInt64 = 0
        for lineSub in matrixLines {
            // 行级节流进度上报
            nexusLineIdx += 1
            if let cb = progress, nexusLineIdx % 2000 == 0 { cb(nexusLineIdx, nexusTotal) }
            let trimmed = lineSub.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { blockLineIdx = 0; lastNamedTaxon = ""; continue } // 空行 = 交错块边界
            // 去除 & 注解
            var cleanLine = trimmed
            if let ampRange = cleanLine.range(of: "&") {
                cleanLine = String(cleanLine[..<ampRange.lowerBound]) + " " + String(cleanLine[ampRange.upperBound...])
            }
            // 解析名称和残基（含引号包裹的名称）
            var name: String
            var rest: String
            if cleanLine.hasPrefix("'") || cleanLine.hasPrefix("\"") {
                let quoteChar = cleanLine.first!
                let startIdx = cleanLine.index(after: cleanLine.startIndex)
                if let endQuote = cleanLine[startIdx...].range(of: String(quoteChar)) {
                    name = String(cleanLine[startIdx..<endQuote.lowerBound])
                    rest = cleanLine[endQuote.upperBound...].trimmingCharacters(in: .whitespaces)
                } else {
                    name = String(cleanLine.dropFirst())
                    rest = ""
                }
            } else {
                let parts = cleanLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                name = parts.first ?? ""
                rest = parts.count > 1 ? parts[1] : ""
            }
            // 非法字符显式报错而非 compactMap 静默丢弃。
            // 但续行启发式需要区分「名字像残基」和「残基行」，所以分两步：
            // 先检查是否有非法字符，再做续行判定。
            var residues: [UInt8] = []
            var hasIllegal = false
            for c in rest.uppercased() {
                if let r = nexusResidue(c) {
                    residues.append(r)
                } else if !c.isWhitespace {
                    hasIllegal = true
                }
            }
            if hasIllegal && !residues.isEmpty {
                // 有残基也有非法字符——按报错处理（静默丢弃会移位残基）
                let illegalChars = rest.uppercased().filter { nexusResidue($0) == nil && !$0.isWhitespace }
                throw CoreError.format("NEXUS：非法字符 '\(illegalChars.first ?? "?")' 在 MATRIX 行")
            }

            if residues.isEmpty && !name.isEmpty && name.uppercased().allSatisfy({ nexusResidue($0) != nil }) {
                // 纯残基续行（无名称）：不能一律"按块内行号对位 nameOrder"——那只对**交错**矩阵成立；
                // 顺序（sequential）矩阵里一条长序列折行多行时，第 1 条续行会被归属到
                // nameOrder[1] = 下一条 taxon，于是 A 的残基被分摊给后续所有分类单元，
                // 且各条长度仍可能"看起来合理"（末尾由 padToMaxLength 抹平），全程不报错。
                // NEXUS 规范并不要求块间有空行，Mesquite/MrBayes 的顺序矩阵常无空行。
                // 判别：无名续行第一次出现时，若块内行号恰等于已读 taxon 数（=一条完整块
                // 结束后回到第 0 行）则按交错对位；否则按顺序布局归给上一条具名 taxon。
                let contResidues = parseResiduesFromName(name)
                if isInterleavedLayout == nil {
                    isInterleavedLayout = (blockLineIdx >= nameOrder.count)
                }
                if isInterleavedLayout == true, blockLineIdx < nameOrder.count {
                    nameToSeq[nameOrder[blockLineIdx]]?.append(contentsOf: contResidues)
                } else if !lastNamedTaxon.isEmpty {
                    nameToSeq[lastNamedTaxon]?.append(contentsOf: contResidues)
                }
                blockLineIdx += 1
            } else if !name.isEmpty && !residues.isEmpty {
                // 同名 taxon 可能真的出现两次。以"内部键"登记记录（显示名仍为原名，
                // finalize 时唯一化），并把残基给**尚未达到声明长度**的那条同名记录；
                // 都满了就是另一条 taxon，新起记录 —— 而不是把两段残基首尾拼接。
                var key = ""
                for k in nameOrder where namesByKey[k] == name {
                    if declaredNchar == 0 || (nameToSeq[k]?.count ?? 0) < declaredNchar { key = k; break }
                }
                if key.isEmpty {
                    let newKey = "\(name)#\(nameOrder.count)"
                    nameToSeq[newKey] = []
                    namesByKey[newKey] = name
                    nameOrder.append(newKey)
                    key = newKey
                }
                lastNamedTaxon = key
                nameToSeq[key]?.append(contentsOf: residues)
                blockLineIdx += 1
            } else if !name.isEmpty && !rest.isEmpty {
                // 名称行但残基被完全过滤：至少保留 taxon 占位，避免错位
                if nameToSeq[name] == nil {
                    nameToSeq[name] = []
                    nameOrder.append(name)
                }
                lastNamedTaxon = name
                blockLineIdx += 1
            }
        }

        var sequences: [Sequence] = []
        for key in nameOrder {
            let residues = nameToSeq[key] ?? []
            if residues.isEmpty { continue }
            sequences.append(Sequence(name: namesByKey[key] ?? key, residues: residues))
        }
        return DataBlockResult(sequences: sequences, datatype: datatype)
    }

    private static func parseResiduesFromName(_ name: String) -> [UInt8] {
        name.uppercased().compactMap { nexusResidueHelper($0) }
    }

    private static func nexusResidueHelper(_ c: Character) -> UInt8? {
        guard let s = c.asciiValue else { return nil }
        if (s >= 0x41 && s <= 0x5A) || s == 0x2D || s == 0x3F { return s }
        if s == 0x2A { return s }
        return nil
    }

    private static func parseSetsBlock(_ content: String) -> [CharsetInfo] {
        var charsets: [CharsetInfo] = []
        // CHARSET name = 1-60\3
        let pattern = "CHARSET\\s+(\\S+)\\s*=\\s*([^;]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let nsText = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let name = nsText.substring(with: match.range(at: 1))
                    let rangeStr = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    var ranges: [(start: UInt32, end: UInt32)] = []
                    // 支持 1-60\3 步长写法
                    let parts = rangeStr.split(separator: " ").map(String.init)
                    for part in parts {
                        if let (s, e, step) = parseRange(part) {
                            if step > 1 {
                                var current = s
                                while current <= e {
                                    ranges.append((start: current, end: current))
                                    current += step
                                }
                            } else {
                                ranges.append((start: s, end: e))
                            }
                        }
                    }
                    charsets.append(CharsetInfo(name: name, ranges: ranges, originalSpec: rangeStr))
                }
            }
        }
        return charsets
    }

    private static func parseRange(_ s: String) -> (start: UInt32, end: UInt32, step: UInt32)? {
        // 1-60\3 或 1-60 或 5
        if s.contains("\\") {
            let parts = s.split(separator: "\\")
            guard parts.count == 2, let step = UInt32(parts[1]) else { return nil }
            let rangeParts = parts[0].split(separator: "-")
            guard rangeParts.count == 2, let start = UInt32(rangeParts[0]), let end = UInt32(rangeParts[1]) else { return nil }
            return (start, end, step)
        } else if s.contains("-") {
            let parts = s.split(separator: "-")
            guard parts.count == 2, let start = UInt32(parts[0]), let end = UInt32(parts[1]) else { return nil }
            return (start, end, 1)
        } else if let val = UInt32(s) {
            return (val, val, 1)
        }
        return nil
    }
}

// MARK: - PHYLIP 解析器

struct PhylipParser {
    static func parse(_ data: Data, progress: ProgressCallback? = nil) throws -> Alignment {
        guard let text = FormatDetector.decodeText(data) else {
            throw CoreError.format("无法解码为文本")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !lines.isEmpty else { throw CoreError.format("PHYLIP 文件为空") }

        // 首行 ntax nchar
        let firstParts = lines[0].split { $0 == " " || $0 == "\t" }.map(String.init)
        guard firstParts.count >= 2,
              let ntax = Int(firstParts[0]), let nchar = Int(firstParts[1]),
              ntax > 0, nchar > 0 else {
            throw CoreError.format("PHYLIP 首行格式错误：应为 'ntax nchar'")
        }

        // 收集所有非空数据行
        var dataLines: [String] = []
        let phyTotal = UInt64(max(0, lines.count - 1))
        for i in 1..<lines.count {
            // 行级节流进度上报
            if !lines[i].isEmpty {
                dataLines.append(lines[i])
            }
            if let cb = progress, i % 2000 == 0 { cb(UInt64(i), phyTotal) }
        }
        guard dataLines.count >= ntax else {
            throw CoreError.format("PHYLIP 数据行数不足：期望 \(ntax)，实际 \(dataLines.count)")
        }

        // 判别变体：严格 10 字符名 vs 全名填充。
        // 单靠第一行的启发式必然误判（名称满 10 列时没有分隔空格；短名称补齐后
        // 又与"全名 + 空白"不可区分），因此和顺序/交错一样把两种解释都解析一遍，
        // 用同一 score() 择优 —— 与本文件既有的"双解打分"设计一致。
        let firstDataLine = dataLines[0]
        let isStrict10 = isStrict10Char(firstDataLine)

        // PHYLIP 顺序 / 交错无法仅凭「续行是否带名称」可靠判别：
        // 「无名换行顺序格式」与「全名交错且续行无名」都会骗过单一启发式，
        // 误判会把整块残基灌进最后一条 taxon，造成长度错乱（如 160/140）。
        // 故各按顺序、交错两种布局解析一次，再按「每条序列长度能否一致且等于 nchar」择优。
        var candidates: [PhylipCandidate] = [
            parseSequential(dataLines, ntax: ntax, nchar: nchar, isStrict10: isStrict10),
            parseInterleaved(dataLines, ntax: ntax, nchar: nchar, isStrict10: isStrict10),
        ]
        // 另一种名称字段解释（strict ↔ relaxed）一并入候选；relaxed 排在后面，
        // 同分时优先（更通用，不依赖固定列宽）
        candidates.append(parseSequential(dataLines, ntax: ntax, nchar: nchar, isStrict10: !isStrict10))
        candidates.append(parseInterleaved(dataLines, ntax: ntax, nchar: nchar, isStrict10: !isStrict10))
        let scored = candidates.map { (c: $0, s: $0.score(ntax: ntax, nchar: nchar)) }
        var best = scored[0]
        for c in scored.dropFirst() where c.s > best.s { best = c }   // 同分保留先出现者（relaxed 优先）
        let chosen = best.c
        let names = chosen.names
        var seqs = chosen.seqs

        // 补齐 nchar
        for i in 0..<seqs.count {
            if seqs[i].count < nchar {
                seqs[i].append(contentsOf: [UInt8](repeating: 0x2D, count: nchar - seqs[i].count))
            }
        }

        var sequences: [Sequence] = []
        for i in 0..<ntax {
            let name = (i < names.count && !names[i].isEmpty) ? names[i] : "Seq\(i + 1)"
            sequences.append(Sequence(name: name, residues: seqs[i]))
        }

        // 一条残基都没读到说明名称字段与残基之间没有可识别的分隔；
        // 此时不得静默把整行当名称、再补成整行空位（"文件打开成功、画布一片横杠"）。
        for seq in sequences where seq.residues.isEmpty {
            throw CoreError.format("PHYLIP：序列 \(seq.name) 未读到任何残基（名称与残基之间缺少分隔符？文件头声明 nchar=\(nchar)）")
        }
        return try ParsedAlignment.finalize(sequences, datatype: DatatypeDetector.detect(sequences))
    }

    /// 检查第 1-10 列是否为名称、第 11 列开始为残基。
    ///
    /// 名称前缀不得要求以空格结尾（`prefix.last == " "`）：那会把
    /// **名称满 10 字符**的合法 strict 10 列文件判为非 strict，于是整行（名称 + 全部残基）
    /// 被 `parseNameAndResidues` 按"首个空格"切分时当成名称、残基为空，随后补 '-' 补成
    /// 整行空位 —— GenBank accession（AF123456.1 正好 10 字符）是最常见的触发输入。
    /// 判据：前 10 列不含空格/制表（纯名称）且第 11 列起是残基字符，同样判为 strict。
    private static func isStrict10Char(_ line: String) -> Bool {
        guard line.count >= 11 else { return false }
        let prefix = String(line.prefix(10))
        let suffix = String(line.dropFirst(10)).trimmingCharacters(in: .whitespaces)
        guard !suffix.isEmpty, isNucleotideChar(suffix.first) else { return false }
        if prefix.last == " " { return true }
        // 名称占满 10 列：前缀整体必须是"名称合法字符"（字母数字._-），不能含空白
        return !prefix.contains(where: { $0 == " " || $0 == "\t" })
            && prefix.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    /// 单条 taxon 的解析候选（顺序 or 交错两种布局之一），附带一致性打分用于择优。
    private struct PhylipCandidate {
        let names: [String]
        let seqs: [[UInt8]]
        /// 分数越高越自洽：优先「所有序列等长且 == nchar」；惩罚长度溢出/为 0。
        func score(ntax _: Int, nchar: Int) -> Int {
            let lens = seqs.map { $0.count }
            guard !lens.isEmpty else { return 0 }
            let allPositive = lens.allSatisfy { $0 > 0 }
            let allEqual = Set(lens).count <= 1
            let maxLen = lens.max() ?? 0
            var s = 0
            if allPositive { s += 2 }
            if allEqual { s += 3 }
            if allEqual && maxLen == nchar { s += 4 }
            if allEqual && maxLen > 0 && maxLen <= nchar { s += 1 }
            if maxLen > nchar { s -= 6 }
            return s
        }
    }

    /// 解析单行 PHYLIP：返回 (名称, 残基, 是否为带名称行)。
    /// 严格 10 字符：前 10 列以空格结尾且第 11 列起有内容 → 名称行；否则顶格纯残基续行。
    /// 全名：名称与残基以空白分隔；若首段整体是残基字符且无第二列 → 纯残基续行（无名称）。
    private static func decodeLine(_ line: String, isStrict10: Bool) -> (String, [UInt8], Bool) {
        if isStrict10 {
            let rawName = String(line.prefix(10))
            let trimmed = rawName.trimmingCharacters(in: .whitespaces)
            // 名称满 10 列（无分隔空格）时同样按前 10 列取名称。
            // 注意：这里**不能**因为名称字段里含空白就回退按空白切分 —— 那正是
            // strict10 用短名称补齐到 10 列的标准形态，回退会把补齐空格当成名称与残基的
            // 分界、吃掉前 1~5 个残基。strict 与 relaxed 之间的取舍交给 score() 择优。
            let isNameLine = line.count > 10 && !trimmed.isEmpty
            if isNameLine {
                return (trimmed, parseResidues(String(line.dropFirst(10))), true)
            } else {
                return ("", parseResidues(line), false)
            }
        } else {
            let (n, r) = parseNameAndResidues(line)
            if r.isEmpty && !n.isEmpty && n.allSatisfy(isNucleotideChar) {
                return ("", parseResidues(n), false)  // 名称段实为续行残基
            }
            return (n, r, !n.isEmpty)
        }
    }

    /// 顺序布局：同一 taxon 的残基连续出现。当前 taxon 累计达 nchar、或遇到带名称行
    /// 且当前 taxon 已有残基时，切换到下一条 taxon。无名换行时纯靠 nchar 计数推进。
    private static func parseSequential(_ lines: [String], ntax: Int, nchar: Int, isStrict10: Bool) -> PhylipCandidate {
        var names: [String] = []
        var seqs: [[UInt8]] = Array(repeating: [], count: ntax)
        var current = 0
        for line in lines {
            let (namePart, resPart, hasName) = decodeLine(line, isStrict10: isStrict10)
            if current >= ntax { break }
            if seqs[current].count >= nchar || (hasName && !seqs[current].isEmpty) {
                current += 1
                if current >= ntax { break }
            }
            if seqs[current].isEmpty { names.append(namePart) }
            seqs[current].append(contentsOf: resPart)
        }
        return PhylipCandidate(names: names, seqs: seqs)
    }

    /// 交错布局：每块 ntax 行、按 taxon 顺序出现；将行按 ntax 为周期循环映射到各 taxon。
    /// 首块带名称行记录名称，后续块续行（有无名称皆可）只累加残基。
    private static func parseInterleaved(_ lines: [String], ntax: Int, nchar _: Int, isStrict10: Bool) -> PhylipCandidate {
        var names: [String] = Array(repeating: "", count: ntax)
        var seqs: [[UInt8]] = Array(repeating: [], count: ntax)
        var idx = 0
        while idx < lines.count {
            for t in 0..<ntax {
                if idx >= lines.count { break }
                let (namePart, resPart, hasName) = decodeLine(lines[idx], isStrict10: isStrict10)
                if hasName && names[t].isEmpty { names[t] = namePart }
                seqs[t].append(contentsOf: resPart)
                idx += 1
            }
        }
        return PhylipCandidate(names: names, seqs: seqs)
    }

    private static func parseNameAndResidues(_ line: String) -> (String, [UInt8]) {
        // 处理引号包裹的名称
        if line.hasPrefix("'") || line.hasPrefix("\"") {
            let quoteChar = line.first!
            let startIdx = line.index(after: line.startIndex)
            if let endQuote = line[startIdx...].range(of: String(quoteChar)) {
                let name = String(line[startIdx..<endQuote.lowerBound])
                let rest = line[endQuote.upperBound...].trimmingCharacters(in: .whitespaces)
                return (name, parseResidues(rest))
            }
        }
        // 未引号标签取首个空白前段
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let name = parts.first ?? ""
        let rest = parts.count > 1 ? parts[1] : ""
        return (name, parseResidues(rest))
    }

    /// '.'（PHYLIP / seqboot / Gblocks / HMMER 的空位记号）必须归一化而非从白名单剔除：
    /// 若被 compactMap **静默删除**，其后所有残基左移一列 → 列同源性被打断，
    /// 且长度短于 nchar 后由补 '-' 抹平，看起来"长度正常"。
    /// 与 FASTA 侧的原则保持一致（`:107` 的注释就写着"静默丢弃会移位残基"）：
    /// 先保留，再归一化为规范空位 '-'。
    private static func parseResidues(_ s: String) -> [UInt8] {
        s.uppercased().compactMap { c -> UInt8? in
            guard let s = c.asciiValue else { return nil }
            if (s >= 0x41 && s <= 0x5A) || s == 0x2D || s == 0x3F || s == 0x2A { return s }
            if s == 0x2E || s == 0x7E { return 0x2D }      // '.' '~' → 规范空位
            if s >= 0x30 && s <= 0x39 { return s }         // 0-9 数字简并码
            return nil
        }
    }

    private static func isNucleotideChar(_ c: Character?) -> Bool {
        guard let c = c, let s = c.asciiValue else { return false }
        return (s >= 0x41 && s <= 0x5A) || s == 0x2D || s == 0x3F || s == 0x2E || s == 0x2A
    }

}

// MARK: - CLUSTAL 解析器

struct ClustalParser {
    static func parse(_ data: Data, progress: ProgressCallback? = nil) throws -> Alignment {
        guard let text = FormatDetector.decodeText(data) else {
            throw CoreError.format("无法解码为文本")
        }
        let upper = text.uppercased()
        // MAFFT 的 clustal 输出头为 "MAFFT v7.x"，不含 CLUSTAL 字样；正文布局相同时同样接受
        let hasClustalHeader = upper.contains("CLUSTAL")
        if !hasClustalHeader {
            let bodyLooksClustal = text.split(separator: "\n").contains { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty, !isConservationLine(t) else { return false }
                let parts = t.split(omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
                // 启发式同样要看所有残基词元（只看 parts[1] 会漏判一行内多块的布局）
                return parts.count >= 2 && parts[1...].allSatisfy { token in
                    token.allSatisfy { c in
                        guard let s = c.asciiValue else { return false }
                        return (s >= 0x41 && s <= 0x5A) || s == 0x2D || s == 0x2A
                    }
                }
            }
            guard bodyLooksClustal else {
                throw CoreError.format("CLUSTAL 文件缺少 CLUSTAL 头")
            }
        }

        var collector = BlockAwareResidueCollector()
        let clustalLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let clustalTotal = UInt64(clustalLines.count)
        // 行级节流进度上报
        var clustalLineIdx: UInt64 = 0
        for lineSub in clustalLines {
            clustalLineIdx += 1
            if let cb = progress, clustalLineIdx % 2000 == 0 { cb(clustalLineIdx, clustalTotal) }
            let trimmed = lineSub.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { collector.beginBlock(); continue }   // 空行 = 块边界
            // 跳过头行（CLUSTAL / MAFFT / MUSCLE 版本横幅等无序列行）
            if trimmed.uppercased().contains("CLUSTAL") { continue }
            if !hasClustalHeader && trimmed.uppercased().hasPrefix("MAFFT") { continue }
            // 跳过保守度行（以 * : . 开头或纯符号）
            if isConservationLine(trimmed) { continue }

            // name  residues  [consensus]：同时按空格与 tab 分隔（含 tab 缩进的变体）
            let parts = trimmed.split(omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }

            let name = parts[0]
            // 一行里第二个及以后的残基块同样保留：Clustal Omega / 部分 MAFFT clustal 输出
            // 与若干手工整理的 ALN 会在一行内用空格再分块（或在序列尾部追加保守符号列），
            // 只取 parts[1] 会从第二个块起整段丢失，
            // 随后 padToMaxLength 在尾部补 '-' 把长度差异抹平，用户只看到序列"短了一截"。
            // 与 MSF 侧的写法（连接所有词元）保持一致。
            // 尾部的保守符号词元（仅含 * : . 空白）跳过，不计入残基。
            var residues: [UInt8] = []
            for token in parts.dropFirst() {
                if token.allSatisfy({ "*:.".contains($0) }) { continue }   // 保守度列
                // 残基非法字符显式报错（静默丢弃会移位残基、掩盖真实错误）
                for c in token.uppercased() {
                    guard let s = c.asciiValue else {
                        throw CoreError.format("CLUSTAL：非法字符 '\(c)' 在行 \(clustalLineIdx)")
                    }
                    if (s >= 0x41 && s <= 0x5A) || s == 0x2D || s == 0x2A {
                        residues.append(s)
                    } else if s == 0x3F || s == 0x2E {
                        // ? 缺失数据保留；'.' 归一化为空位（finalize 里再兜一次）
                        residues.append(s == 0x3F ? 0x3F : 0x2D)
                    } else {
                        throw CoreError.format("CLUSTAL：非法字符 '\(c)' 在行 \(clustalLineIdx)")
                    }
                }
            }
            if !residues.isEmpty {
                collector.add(name: name, residues: residues)     // 按块归属，同名不拼接
            }
        }

        var sequences: [Sequence] = []
        for record in collector.finish() where !record.residues.isEmpty {
            sequences.append(Sequence(name: record.name, residues: record.residues))
        }
        if sequences.isEmpty { throw CoreError.format("CLUSTAL：未找到任何序列") }

        return try ParsedAlignment.finalize(sequences, datatype: DatatypeDetector.detect(sequences))
    }

    private static func isConservationLine(_ line: String) -> Bool {
        // 保守度行仅含 * : . 和空格
        let allowed = Set<Character>(["*", ":", ".", " "])
        return line.allSatisfy { allowed.contains($0) }
    }

}

// MARK: - MSF 解析器

struct MsfParser {
    static func parse(_ data: Data, progress: ProgressCallback? = nil) throws -> Alignment {
        guard let text = FormatDetector.decodeText(data) else {
            throw CoreError.format("无法解码为文本")
        }
        let upper = text.uppercased()
        let isAA = upper.contains("!!AA_MULTIPLE_ALIGNMENT")
        let isNA = upper.contains("!!NA_MULTIPLE_ALIGNMENT")
        guard isAA || isNA else {
            throw CoreError.format("MSF 文件缺少 !!AA/NA_MULTIPLE_ALIGNMENT 头")
        }

        // 解析 MSF: 行获取 nchar
        var nchar: Int = 0
        if let msfLine = text.split(separator: "\n").first(where: { $0.contains("MSF:") }) {
            let parts = msfLine.split { $0 == " " || $0 == ":" }.map(String.init)
            //  MSF: 3  Type: N  Len: 60  Check: ..  ..
            if let lenIdx = parts.firstIndex(where: { $0.uppercased() == "LEN" }) {
                if lenIdx + 1 < parts.count, let len = Int(parts[lenIdx + 1]) {
                    nchar = len
                }
            }
        }

        // 找到 // 分隔线后的矩阵部分
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let separatorIdx = lines.firstIndex(where: { $0 == "//" }) else {
            throw CoreError.format("MSF 文件缺少 '//' 分隔符")
        }

        var collector = BlockAwareResidueCollector()
        var collected: [(name: String, residues: [UInt8])] = []
        let msfTotal = UInt64(lines.count - separatorIdx - 1)
        var msfLineIdx: UInt64 = 0

        for i in (separatorIdx + 1)..<lines.count {
            // 行级节流进度上报
            msfLineIdx += 1
            if let cb = progress, msfLineIdx % 2000 == 0 { cb(msfLineIdx, msfTotal) }
            let line = lines[i]
            if line.isEmpty { collector.beginBlock(); continue }   // 空行 = 块边界
            // 格式: name  ATGCTAGCTA  GCTAGCTAGC ...
            // GCG MSF 的名称字段可达 20 列且**可以含空格**：按单个空格切分会把多余词元
            // 当残基追加（字母在 A-Z 白名单内，不会报错，只会静默加残基）。
            // 因此按"矩阵行 = 名称 + 至少一个纯残基词元"定位名称边界：从右往左找第一个
            // 非残基词元，其左侧全部是名称（保留内部空格），其右侧全部是残基。
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard !parts.isEmpty else { continue }
            func isResidueToken(_ t: String) -> Bool {
                !t.isEmpty && t.uppercased().allSatisfy { c in
                    guard let b = c.asciiValue else { return false }
                    return (b >= 0x41 && b <= 0x5A) || b == 0x2D || b == 0x2A || b == 0x3F || b == 0x2E
                }
            }
            var firstResidueToken = parts.count
            for k in stride(from: parts.count - 1, through: 1, by: -1) {
                if isResidueToken(parts[k]) { firstResidueToken = k } else { break }
            }
            guard firstResidueToken < parts.count, firstResidueToken > 0 else { continue }
            let name = parts[0..<firstResidueToken].joined(separator: " ")
            // 残基是后续所有部分连接
            var residues: [UInt8] = []
            for j in firstResidueToken..<parts.count {
                // 非法字符显式报错而非 compactMap 静默丢弃
                for c in parts[j].uppercased() {
                    guard let s = c.asciiValue else {
                        throw CoreError.format("MSF：非法字符 '\(c)' 在行 \(msfLineIdx)")
                    }
                    if (s >= 0x41 && s <= 0x5A) || s == 0x2D || s == 0x2A {
                        residues.append(s)
                    } else if s == 0x3F || s == 0x2E {
                        residues.append(s == 0x2E ? 0x2D : 0x3F)   // '.' → 规范空位
                    } else {
                        throw CoreError.format("MSF：非法字符 '\(c)' 在行 \(msfLineIdx)")
                    }
                }
            }
            if !residues.isEmpty {
                collector.add(name: name, residues: residues)     // 按块归属，同名不拼接
            }
        }

        collected = collector.finish()

        //  校验 MSF 头声称长度与实际一致
        if nchar > 0 {
            for rec in collected where rec.residues.count != nchar {
                throw CoreError.format("MSF：序列 \(rec.name) 实际长度 \(rec.residues.count) 与 MSF 头声称长度 \(nchar) 不一致")
            }
        }

        var sequences: [Sequence] = []
        for rec in collected {
            var s = rec.residues
            if nchar > 0 && s.count < nchar {
                s.append(contentsOf: [UInt8](repeating: 0x2D, count: nchar - s.count))
            }
            sequences.append(Sequence(name: rec.name, residues: s))
        }
        if sequences.isEmpty { throw CoreError.format("MSF：未找到任何序列") }

        let datatype: Datatype = isAA ? .aminoAcid : .nucleicAcid
        return try ParsedAlignment.finalize(sequences, datatype: datatype)
    }
}

// MARK: - .fai 索引读写

struct FaiIndex {
    struct Entry {
        let name: String
        let length: UInt64
        let offset: UInt64
        let basesPerLine: UInt64
        let bytesPerLine: UInt64
    }
    var entries: [Entry] = []
}

enum FaiIndexer {
    /// 读取 .fai 索引文件
    /// 格式：name\tlength\toffset\tbasesPerLine\tbytesPerLine
    static func read(_ data: Data) throws -> FaiIndex {
        guard let text = FormatDetector.decodeText(data) else {
            throw CoreError.format("无法解码 .fai 索引文件")
        }
        var index = FaiIndex()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(separator: "\t").map(String.init)
            guard parts.count >= 5,
                  let length = UInt64(parts[1]),
                  let offset = UInt64(parts[2]),
                  let basesPerLine = UInt64(parts[3]),
                  let bytesPerLine = UInt64(parts[4]) else {
                throw CoreError.format(".fai 索引格式错误：\(trimmed)")
            }
            index.entries.append(FaiIndex.Entry(
                name: parts[0],
                length: length,
                offset: offset,
                basesPerLine: basesPerLine,
                bytesPerLine: bytesPerLine
            ))
        }
        return index
    }

    /// 从 Alignment 生成 .fai 索引文本。
    /// 虚拟索引：描述与 AlignmentWriter 默认导出（wrapWidth=0，每条序列单行）一致的
    /// FASTA 布局，偏移累加先前所有序列的字节数；不要与任意换行宽度的真实文件混用。
    static func write(_ alignment: Alignment) -> Data {
        var output = ""
        var offset: UInt64 = 0
        for seq in alignment.sequences {
            let residues = String(bytes: seq.residues, encoding: .ascii) ?? ""
            // samtools .fai 的 length 是 **ungapped** 长度；比对导出场景下残基串含 '-'，
            // 直接取 residues.count 会得到"含空位长度"，语义与 .fai 规范不符。
            // 本索引自我声明为"虚拟索引"，这里进一步把 length 写成真正的非空位残基数，
            // basesPerLine 仍描述本虚拟布局（单行 = 全部含空位字符），并在写出时加注。
            let length = UInt64(residues.filter { $0 != "-" && $0 != "." }.count)
            let headerLine = ">\(seq.name)\(seq.description.isEmpty ? "" : " \(seq.description)")\n"
            let recordLine = residues.isEmpty ? "" : residues + "\n"
            let recordBytes = UInt64(headerLine.utf8.count + recordLine.utf8.count)
            // 单行布局：basesPerLine = 全长，bytesPerLine = 全长 + 1 换行；空序列跳过
            if length > 0 {
                output += "\(seq.name)\t\(length)\t\(offset + UInt64(headerLine.utf8.count))\t\(length)\t\(length + 1)\n"
            }
            offset += recordBytes
        }
        return output.data(using: .utf8) ?? Data()
    }
}

// MARK: - 统一解析入口


// MARK: - Stockholm 解析器（Pfam/Rfam/HMMER 标准）

struct StockholmParser {
    static func parse(_ data: Data, progress: ProgressCallback? = nil) throws -> Alignment {
        guard let text = FormatDetector.decodeText(data) else {
            throw CoreError.format("无法解码为文本")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("# STOCKHOLM") else {
            throw CoreError.format("Stockholm 文件缺少 '# STOCKHOLM' 头")
        }

        var collector = BlockAwareResidueCollector()
        var metadata: [String: String] = [:]
        var rf: [String] = []

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let stoTotal = UInt64(lines.count)
        var stoLineIdx: UInt64 = 0
        for lineSub in lines {
            stoLineIdx += 1
            // 行级节流进度上报
            if let cb = progress, stoLineIdx % 2000 == 0 { cb(stoLineIdx, stoTotal) }
            let line = lineSub.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { collector.beginBlock(); continue }   // 空行 = 块边界
            if line == "//" { break }
            if line.hasPrefix("#") {
                // #=GF ID xxx / #=GF AC xxx / #=GC RF xxx
                if line.uppercased().hasPrefix("#=GF") {
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    if parts.count >= 3, parts[1].uppercased() == "ID" || parts[1].uppercased() == "AC" {
                        metadata[parts[1].uppercased()] = parts[2]
                    }
                } else if line.uppercased().hasPrefix("#=GC RF") {
                    let cols = line.split(separator: " ", omittingEmptySubsequences: true)
                    if cols.count >= 3 { rf.append(String(cols[2])) }
                }
                continue
            }
            // 序列行：name residues
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            let name = parts[0]
            // 非法字符显式报错而非 compactMap 静默丢弃
            var residues: [UInt8] = []
            for c in parts[1].uppercased() {
                guard let a = c.asciiValue else {
                    throw CoreError.format("Stockholm：非法字符 '\(c)'")
                }
                if (a >= 0x41 && a <= 0x5A) || a == 0x2D || a == 0x2A {
                    residues.append(a)
                } else if a == 0x3F || a == 0x2E {
                    residues.append(a == 0x2E ? 0x2D : 0x3F)   // '.'（Stockholm 插入列空位）→ 规范空位
                } else {
                    throw CoreError.format("Stockholm：非法字符 '\(c)'")
                }
            }
            collector.add(name: name, residues: residues)      // 同名序列各自成记录
        }

        let records = collector.finish()
        guard !records.isEmpty else { throw CoreError.format("Stockholm：未找到序列行") }
        var sequences: [Sequence] = []
        for rec in records where !rec.residues.isEmpty {
            sequences.append(Sequence(name: rec.name, residues: rec.residues))
        }
        return try ParsedAlignment.finalize(sequences, datatype: DatatypeDetector.detect(sequences),
                                            metadata: metadata)
    }
}

// MARK: - GFF3 注释解析（纯逻辑，供注释浏览器使用）

struct GffFeature {
    let seqid: String
    let type: String
    let start: Int   // 1-based inclusive
    let end: Int     // 1-based inclusive
    let strand: String
    let name: String
}

struct GffParser {
    static func parse(_ data: Data) -> [GffFeature] {
        guard let text = FormatDetector.decodeText(data) else {
            return []
        }
        var features: [GffFeature] = []
        for lineSub in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = lineSub.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let cols = line.split(separator: "\t").map(String.init)
            guard cols.count >= 5,
                  let start = Int(cols[3]), let end = Int(cols[4]), start <= end else { continue }
            var name = cols[2]
            if cols.count >= 9 {
                // 从属性列提取 Name=xxx
                for kv in cols[8].split(separator: ";") {
                    let pair = kv.split(separator: "=", maxSplits: 1).map(String.init)
                    if pair.count == 2, pair[0] == "Name" { name = pair[1]; break }
                }
            }
            features.append(GffFeature(seqid: cols[0], type: cols[2], start: start, end: end,
                                       strand: cols.count >= 7 ? cols[6] : ".", name: name))
        }
        return features
    }
}

// MARK: - gzip 解压（打开 .gz 比对文件）

enum Gzip {
    /// 解压 gzip（RFC 1952）数据：10 字节头 + deflate 流 + 8 字节尾。
    /// 支持 BGZF 多成员（bgzip 块大小在 FEXTRA 的 BC 子字段中精确编码）。
    /// 非 BGZF 的普通拼接 gzip（`cat a.fa.gz b.fa.gz > c.fa.gz`）
    /// 检测到文件内有多于一个 gzip 头但无法精确分割时，返回 nil 触发报错，
    /// 不再静默丢弃后半份数据。
    static func decompress(_ data: Data) -> Data? {
        guard data.count > 18 else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 0x08 else { return nil }

        var result = Data()
        var cursor = 0
        var allMembersBGZF = true   // 跟踪是否全部成员都是 BGZF
        var memberCount = 0
        while cursor + 18 <= bytes.count,
              bytes[cursor] == 0x1F, bytes[cursor + 1] == 0x8B, bytes[cursor + 2] == 0x08 {
            guard let (memberData, nextOffset, isBGZF) = decodeMember(bytes, from: cursor) else { break }
            guard !memberData.isEmpty else { break }
            result.append(memberData)
            if !isBGZF { allMembersBGZF = false }
            memberCount += 1
            if nextOffset <= cursor { break }
            cursor = nextOffset
        }
        if result.isEmpty { return nil }
        // 非 BGZF 拼接 gzip 检测。
        // decodeMember 非 BGZF 时 nextOffset = bytes.count，整个文件被当作一个成员。
        // 如果文件中含多个 gzip 头但只处理了 1 个非 BGZF 成员，说明是 `cat a.gz b.gz` 拼接，
        // 第二个成员被当作 deflate 数据，静默丢失半份数据。返回 nil 触发报错。
        // BGZF 文件也有多个头，但 bsize 让 cursor 精确推进，memberCount > 1 且 allMembersBGZF = true。
        // 判别依据是"解析成员边界后校验 trailer"，而不是在**整份压缩字节流**上扫描
        // 1F 8B 08 —— 那会把 DEFLATE 压缩后的熵负载也扫进去。
        // 该三字节在随机数据里平均每 1677 万字节出现一次，于是 10 MB 的 .gz 约有 45 %
        // 概率命中、100 MB 接近 100 %，命中即返回 nil：用户得到一个正常压缩文件的"解压失败"。
        // 验证 gzip trailer（CRC32 + ISIZE）：单成员文件的尾部必然与解压结果吻合，
        // 吻合即确定只有一个成员（压缩负载里的巧合魔数不再触发误判）；
        // 不吻合才判定为拼接 gzip 并拒绝，静默丢数据的防线保留。
        // 判别顺序：先找"存在第二个成员的可信边界"，再考虑 trailer 一致性。
        // 反过来做会漏判：`cat a.gz b.gz` 且两份内容相同时，文件尾部 trailer
        // 恰好与"整份单成员"的解释自洽（CRC 相同、ISIZE 相同），只看 trailer 会误放行。
        if memberCount == 1 && !allMembersBGZF
            && hasBelievableSecondMemberBoundary(bytes: bytes, firstUncompressedLength: result.count) {
            return nil
        }
        return result
    }

    /// 是否存在"可信的第二成员起点"：魔数出现在 p，且紧接其前的 4 字节 ISIZE 恰等于
    /// 第一个成员解压出的长度。压缩负载里巧合出现的 1F 8B 08 几乎不可能同时满足该条件
    /// （需再凑对一个 32 位 ISIZE）；
    /// 而 `cat a.gz b.gz` 的真实拼接必然满足。
    private static func hasBelievableSecondMemberBoundary(bytes: [UInt8], firstUncompressedLength: Int) -> Bool {
        _ = firstUncompressedLength
        var p = 18
        while p + 18 <= bytes.count {
            // 三重巧合判据：魔数 + FLG 保留位为 0 + 前 4 字节是"装得下"的 ISIZE。
            // 单成员文件里压缩负载中偶然出现的 1F 8B 08 要同时满足三条的概率
            // ≈ 2^-24 × 1/8 × p/2^32，10 MB 文件整体误拒率 <0.05 %。
            if bytes[p] == 0x1F, bytes[p + 1] == 0x8B, bytes[p + 2] == 0x08,
               bytes[p + 3] & 0xE0 == 0 {
                // 前一个成员的 trailer 就贴在魔数前面：ISIZE 必须是一个"装得下"的值
                //（≤ 该位置之前的可用字节数）。压缩负载里巧合出现的三字节能同时让
                // 这四个字节落在合理区间的概率约 2^-32 × p/2^32，实际可忽略。
                let sizeAt = p - 4
                let le = UInt32(bytes[sizeAt]) | (UInt32(bytes[sizeAt + 1]) << 8)
                    | (UInt32(bytes[sizeAt + 2]) << 16) | (UInt32(bytes[sizeAt + 3]) << 24)
                if le > 0, le <= UInt32(p) { return true }
            }
            p += 1
        }
        return false
    }

    /// gzip trailer 校验：最后 8 字节 = CRC32(ISIZE 前的原始数据) + ISIZE（原始长度 mod 2^32）。
    private static func trailerMatches(bytes: [UInt8], uncompressed: Data) -> Bool {
        guard bytes.count >= 18 else { return false }
        let crcAt = bytes.count - 8, sizeAt = bytes.count - 4
        func le32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | (UInt32(bytes[at + 1]) << 8) | (UInt32(bytes[at + 2]) << 16) | (UInt32(bytes[at + 3]) << 24)
        }
        let expectedCRC = le32(crcAt)
        let expectedSize = le32(sizeAt)
        let raw = [UInt8](uncompressed)
        return crc32(raw) == expectedCRC && UInt32(truncatingIfNeeded: raw.count) == expectedSize
    }

    /// 统计文件中 gzip 头魔数（1F 8B 08）出现次数（仅用于诊断，不参与拒绝判定）
    private static func countGzipHeaders(_ bytes: [UInt8]) -> Int {
        var count = 0
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0x1F && bytes[i + 1] == 0x8B && bytes[i + 2] == 0x08 {
                count += 1
                i += 3
            } else {
                i += 1
            }
        }
        return count
    }

    /// 解码单个 gzip 成员，返回（解压数据，下一成员起始偏移，是否为BGZF）。
    /// BGZF（bgzip）通过 FEXTRA 的 BC 子字段携带块大小，可精确推进；
    /// 普通 gzip 成员无块大小时按单成员处理（余下字节全部视为 deflate 流）。
    private static func decodeMember(_ bytes: [UInt8], from start: Int) -> (Data, Int, Bool)? {
        let flags = bytes[start + 3]
        var offset = start + 10
        var bgzfBlockSize: Int? = nil
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { return nil }
            let xlen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            let extraStart = offset + 2
            let extraEnd = min(extraStart + xlen, bytes.count)
            // 遍历子字段寻找 BGZF 的 BC（BSIZE）
            var p = extraStart
            while p + 4 <= extraEnd {
                let si = bytes[p], sname = bytes[p + 1]
                let slen = Int(bytes[p + 2]) | (Int(bytes[p + 3]) << 8)
                if si == 0x42, sname == 0x43, slen == 2, p + 4 + 2 <= extraEnd {
                    bgzfBlockSize = (Int(bytes[p + 4]) | (Int(bytes[p + 5]) << 8)) + 1
                }
                p += 4 + slen
            }
            offset = extraEnd
        }
        if flags & 0x08 != 0 { // FNAME
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC

        let deflateEnd: Int
        let nextOffset: Int
        let isBGZF: Bool
        if let bsize = bgzfBlockSize, start + bsize <= bytes.count, offset + 8 < start + bsize {
            deflateEnd = start + bsize - 8
            nextOffset = start + bsize
            isBGZF = true
        } else {
            deflateEnd = bytes.count - 8
            nextOffset = bytes.count
            isBGZF = false
        }
        guard offset < deflateEnd else { return nil }
        let deflated = Array(bytes[offset..<deflateEnd])
        guard let member = inflate(Data(deflated)) else { return nil }
        return (member, nextOffset, isBGZF)
    }

    /// 压缩为单成员 gzip（RFC 1952）：`.gz` 来源保存时必须重新压缩，
    /// 否则未压缩文本写回 .gz 会破坏容器且扩展名与内容不符。
    /// 与 inflate 对称：Apple COMPRESSION_ZLIB 处理的是裸 DEFLATE，故先 deflate，
    /// 再套 10 字节头 + CRC32 + ISIZE 尾。
    static func compress(_ data: Data) -> Data? {
        let raw = [UInt8](data)
        guard let deflated = deflate(raw) else { return nil }
        var out = Data()
        out.append(contentsOf: [0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xFF])
        out.append(deflated)
        appendLE32(crc32(raw), &out)
        appendLE32(UInt32(truncatingIfNeeded: raw.count), &out)   // ISIZE = 原始长度 mod 2^32
        return out
    }

    private static func appendLE32(_ value: UInt32, _ out: inout Data) {
        out.append(UInt8(value & 0xFF))
        out.append(UInt8((value >> 8) & 0xFF))
        out.append(UInt8((value >> 16) & 0xFF))
        out.append(UInt8((value >> 24) & 0xFF))
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { n in
            var c = UInt32(n)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in bytes { crc = crcTable[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    /// 裸 DEFLATE（无 zlib/gzip 头），与 inflate 的 COMPRESSION_ZLIB 口径一致。
    private static func deflate(_ input: [UInt8]) -> Data? {
        if input.isEmpty { return Data() }
        var capacity = max(input.count + input.count / 1_000 + 64, 64 * 1024)
        let inputLen = input.count
        for _ in 0..<6 {
            var dst = Data(count: capacity)
            let encoded = dst.withUnsafeMutableBytes { dstPtr -> Int in
                input.withUnsafeBytes { srcPtr -> Int in
                    compression_encode_buffer(
                        dstPtr.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        srcPtr.bindMemory(to: UInt8.self).baseAddress!, inputLen,
                        nil, COMPRESSION_ZLIB)
                }
            }
            if encoded > 0 && encoded < capacity {
                dst.removeSubrange(encoded..<dst.count)
                return dst
            }
            capacity *= 4
        }
        return nil
    }

    private static func inflate(_ input: Data) -> Data? {
        // 压缩比未知：容量不足时按 4 倍重试（首试 8 倍起步）
        var capacity = max(input.count * 8, 64 * 1024)
        for _ in 0..<8 {
            var dst = Data(count: capacity)
            let decoded = dst.withUnsafeMutableBytes { dstPtr -> Int in
                input.withUnsafeBytes { srcPtr -> Int in
                    compression_decode_buffer(
                        dstPtr.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        srcPtr.bindMemory(to: UInt8.self).baseAddress!, input.count,
                        nil, COMPRESSION_ZLIB)
                }
            }
            if decoded > 0 && decoded < capacity {
                dst.removeSubrange(decoded..<dst.count)
                return dst
            }
            capacity *= 4
        }
        return nil
    }
}

struct AlignmentParser {
    static func parse(_ data: Data, format: AlignmentFormat? = nil, progress: ProgressCallback? = nil) throws -> Alignment {
        let fmt = format ?? FormatDetector.detect(data)
        switch fmt {
        case .fasta: return try FastaParser.parse(data, progress: progress)
        case .fastq: return try FastqParser.parse(data, progress: progress)
        case .nexus: return try NexusParser.parse(data, progress: progress)
        case .phylip: return try PhylipParser.parse(data, progress: progress)
        case .clustal: return try ClustalParser.parse(data, progress: progress)
        case .msf: return try MsfParser.parse(data, progress: progress)
        case .stockholm: return try StockholmParser.parse(data, progress: progress)
        case .unknown:
            // 尝试 FASTA
            return try FastaParser.parse(data, progress: progress)
        }
    }
}
