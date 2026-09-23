//  SearchEngine.swift
//  SeqAlignMac — 搜索引擎（双范围 + 正则）
//  依据 -SPEC.md  实现
//
//  变更：
//  - 支持两种搜索范围：序列内容（残基）/ 物种名称（序列名）
//  - 支持正则表达式：正则模式下 IUPAC 简并码（R/Y/S/W/K/M/B/D/H/V/N）
//    在字符类外自动展开为等价正则类（如 R→[AG]），与旧 IUPAC 语义无缝衔接；
//    字符类内的字母保持原样，交给用户显式控制。
//  - 非正则模式保留原 IUPAC 展开引擎（行为完全不变）

import Foundation

struct SearchHit: Equatable {
    let seqIndex: Int
    let position: Int
    let matchLen: Int
    /// 是否为「物种/序列名称」命中（画布按整行高亮）
    var isNameHit: Bool = false
}

/// 搜索范围
enum SearchScope: Int32, CaseIterable {
    case content = 0   // 序列内容（残基）
    case name = 1      // 物种/序列名称
}

final class SearchEngine {
    private let alignment: Alignment
    private let scope: SearchScope
    private let useRegex: Bool
    private let rawPattern: String
    /// 正则模式（useRegex=true 时有效）
    private let regex: NSRegularExpression?
    /// IUPAC 展开集合（非正则内容搜索时有效）
    private let patternSets: [[Character]]
    /// KMP next 数组（仅当模式为单字符精确匹配时预计算，加速子串搜索）
    /// 当所有 patternSets 都是单元素集合时，模式退化为精确子串，可用 KMP。
    private let kmpNext: [Int]?
    /// 精确匹配模式字节（KMP 专用，nil 表示无法用 KMP）
    private let kmpPattern: [UInt8]?
    private var currentSeq: Int = 0
    private var currentPos: Int = 0
    /// KMP 跨 next() 调用的匹配状态：findAll 连续调用时文本指针不回退，
    /// 避免每次命中都从 currentPos 重扫到序列尾（最坏 O(n²)）
    private var kmpState: Int = 0
    /// 正则路径的序列字符串缓存：同序列 h 个命中只解码一次
    private var cachedRegexSeqIndex: Int = -1
    private var cachedRegexString: String = ""

    init(alignment: Alignment, pattern: String, scope: SearchScope = .content, useRegex: Bool = false) {
        self.alignment = alignment
        self.scope = scope
        self.useRegex = useRegex
        if useRegex {
            let upLiteral = Self.uppercasingLiterals(pattern)
            self.rawPattern = upLiteral
            // 内容搜索：IUPAC 简并码在字符类外自动展开；名称搜索：纯正则（物种名中的
            // B/M/R/H 等字母是普通字符，不得按简并码展开）
            let translated = (scope == .content) ? Self.translatePattern(upLiteral, useRegex: true) : upLiteral
            self.regex = try? NSRegularExpression(pattern: translated, options: [.caseInsensitive])
            self.patternSets = []
            self.kmpNext = nil
            self.kmpPattern = nil
        } else {
            let up = pattern.uppercased()
            self.rawPattern = up
            self.regex = nil
            let expandedSets = up.map { IUPACCode.expandForSearch($0) }   // 
            self.patternSets = expandedSets
            // 检查是否可使用 KMP（所有字符展开为单元素集合 = 精确匹配）
            if scope == .content, let patBytes = Self.tryExactPattern(up, patternSets: expandedSets) {
                self.kmpPattern = patBytes
                self.kmpNext = Self.buildKMPNext(patBytes)
            } else {
                self.kmpPattern = nil
                self.kmpNext = nil
            }
        }
    }

    /// 仅将字面字符大写化（供正则模式使用）：转义序列与字符类内容保持原样。
    /// 不得先整体 uppercased() 再翻译：\d→\D、\b→\B、\w→\W、\s→\S 会被静默反转。
    static func uppercasingLiterals(_ pattern: String) -> String {
        var out = ""
        var inClass = false
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "\\" && !inClass {
                // 转义序列：连同下一字符原样保留
                out.append(c)
                i = pattern.index(after: i)
                if i < pattern.endIndex {
                    out.append(pattern[i])
                    i = pattern.index(after: i)
                }
                continue
            }
            if c == "[" && !inClass {
                inClass = true
                out.append(c)
            } else if c == "]" && inClass {
                inClass = false
                out.append(c)
            } else if inClass {
                // 字符类内容是用户显式控制区（与 translatePattern 口径一致），原样保留
                out.append(c)
            } else {
                out += c.uppercased()
            }
            i = pattern.index(after: i)
        }
        return out
    }

    /// 尝试将模式转换为精确匹配字节序列（当所有 IUPAC 展开都是单元素时）
    private static func tryExactPattern(_ pattern: String, patternSets: [[Character]]) -> [UInt8]? {
        var bytes: [UInt8] = []
        for (ch, expanded) in zip(pattern, patternSets) {
            // 单元素展开 = 非简并码，可做精确匹配
            guard expanded.count == 1, let scalar = ch.asciiValue else { return nil }
            bytes.append(scalar)
        }
        return bytes.isEmpty ? nil : bytes
    }

    /// 构建 KMP next 数组（部分匹配表）
    private static func buildKMPNext(_ pattern: [UInt8]) -> [Int] {
        let m = pattern.count
        var next = [Int](repeating: 0, count: m)
        var k = 0
        for i in 1..<m {
            while k > 0 && pattern[k] != pattern[i] {
                k = next[k - 1]
            }
            if pattern[k] == pattern[i] {
                k += 1
            }
            next[i] = k
        }
        return next
    }

    /// 查找下一个命中
    func next() -> SearchHit? {
        switch scope {
        case .content: return nextContentHit()
        case .name: return nextNameHit()
        }
    }

    /// 查找全部命中
    /// shouldStop 协作取消——连续键入时旧的全表扫描提前终止，
    /// 不再多个后台任务堆积跑完全程（generation 只负责丢弃过期结果）
    func findAll(shouldStop: (() -> Bool)? = nil) -> [SearchHit] {
        var hits: [SearchHit] = []
        currentSeq = 0
        currentPos = 0
        kmpState = 0
        while let hit = next() {
            hits.append(hit)
            if let stop = shouldStop, stop() { break }
        }
        return hits
    }

    // MARK: - 序列内容搜索

    private func nextContentHit() -> SearchHit? {
        guard !rawPattern.isEmpty else { return nil }
        if let regex {
            return nextContentRegexHit(regex)
        }
        // 正则编译失败时禁止降级到 IUPAC 路径：patLen=0 会在每个位置返回
        // 零长度假命中（UI 预检已拦截大多数，这里是最后一道防线）
        if useRegex { return nil }
        // 优先使用 KMP 加速精确子串搜索（O(n+m) 替代 O(n×m)）
        if let kmpPattern, let kmpNext {
            return nextContentKMPHit(kmpPattern, next: kmpNext)
        }
        return nextContentIUPACHit()
    }

    /// KMP 子串搜索（仅用于非 IUPAC 简并码的精确匹配模式）。
    /// 匹配状态跨 next() 调用保持，findAll 整体 O(n)，支持重叠命中（与旧行为一致）。
    private func nextContentKMPHit(_ pattern: [UInt8], next: [Int]) -> SearchHit? {
        let m = pattern.count
        while currentSeq < alignment.seqCount {
            let seqRes = alignment.sequences[currentSeq].residues
            let seqLen = seqRes.count
            while currentPos < seqLen {
                if seqRes[currentPos] == pattern[kmpState] {
                    currentPos += 1
                    kmpState += 1
                    if kmpState == m {
                        let hit = SearchHit(seqIndex: currentSeq, position: currentPos - m, matchLen: m)
                        // 重叠命中：回退到 next 末位继续匹配（等价于 currentPos += 1）
                        kmpState = next[m - 1]
                        return hit
                    }
                } else if kmpState > 0 {
                    kmpState = next[kmpState - 1]
                } else {
                    currentPos += 1
                }
            }
            currentSeq += 1
            currentPos = 0
            kmpState = 0
        }
        return nil
    }

    /// 正则匹配残基串（IUPAC 已在 translatePattern 中展开）
    private func nextContentRegexHit(_ regex: NSRegularExpression) -> SearchHit? {
        while currentSeq < alignment.seqCount {
            if currentSeq != cachedRegexSeqIndex {
                // 同序列多个命中只解码一次，避免 O(n×h) 的重复 String 分配
                cachedRegexString = String(decoding: alignment.sequences[currentSeq].residues, as: UTF8.self)
                cachedRegexSeqIndex = currentSeq
            }
            let str = cachedRegexString
            let total = str.utf16.count
            if currentPos < total {
                let searchRange = NSRange(location: currentPos, length: total - currentPos)
                if let match = regex.firstMatch(in: str, range: searchRange), match.range.length > 0 {
                    let hit = SearchHit(seqIndex: currentSeq,
                                        position: match.range.location,
                                        matchLen: match.range.length)
                    // 非重叠前进：跳过整个匹配，避免 `\d+` 之类量词把 "12345" 内部数字
                    // 逐个再匹配成多次命中（字面量重叠由独立的 KMP/IUPAC 路径负责）。
                    currentPos = match.range.location + max(match.range.length, 1)
                    return hit
                }
            }
            currentSeq += 1
            currentPos = 0
        }
        return nil
    }

    /// 原 IUPAC 展开引擎（非正则内容搜索）
    private func nextContentIUPACHit() -> SearchHit? {
        let patLen = patternSets.count
        while currentSeq < alignment.seqCount {
            let seq = alignment.sequences[currentSeq]
            let seqLen = seq.residues.count
            while currentPos + patLen <= seqLen {
                if iupacMatchAt(seq: seq, pos: currentPos) {
                    let hit = SearchHit(seqIndex: currentSeq, position: currentPos, matchLen: patLen)
                    currentPos += 1
                    return hit
                }
                currentPos += 1
            }
            currentSeq += 1
            currentPos = 0
        }
        return nil
    }

    /// IUPAC 简并匹配（使用预计算的展开集合）
    private func iupacMatchAt(seq: Sequence, pos: Int) -> Bool {
        let seqRes = seq.residues
        for i in 0..<patternSets.count {
            guard pos + i < seqRes.count else { return false }
            // residues 由解析器保证为 ASCII；加断言，否则下面
            // Character(UnicodeScalar(UInt8)) 与"字节下标 == 字符下标"的假设会静默失效。
            assert(seqRes[pos + i] < 0x80, "SearchEngine: 非 ASCII 残基字节进入匹配路径")
            let seqChar = Character(UnicodeScalar(seqRes[pos + i]))
            if patternSets[i].contains(seqChar) { continue }
            // T/U 等价（非正则路径与正则路径同一口径）
            if seqChar == "U", patternSets[i].contains("T") { continue }
            if seqChar == "T", patternSets[i].contains("U") { continue }
            return false
        }
        return true
    }

    // MARK: - 物种/序列名称搜索

    private func nextNameHit() -> SearchHit? {
        guard !rawPattern.isEmpty else { return nil }
        while currentSeq < alignment.seqCount {
            let name = alignment.sequences[currentSeq].name
            let matched: Bool
            if let regex {
                let range = NSRange(location: 0, length: name.utf16.count)
                matched = regex.firstMatch(in: name, range: range) != nil
            } else {
                matched = name.range(of: rawPattern, options: [.caseInsensitive]) != nil
            }
            if matched {
                let hit = SearchHit(seqIndex: currentSeq, position: 0, matchLen: 0, isNameHit: true)
                currentSeq += 1
                return hit
            }
            currentSeq += 1
        }
        return nil
    }

    // MARK: - 正则翻译 / 校验

    /// 正则模式预处理：字符类外的 IUPAC 简并码展开为等价正则类，
    /// 正则元字符与字符类内内容原样保留。非正则模式不做翻译。
    static func translatePattern(_ pattern: String, useRegex: Bool) -> String {
        guard useRegex else { return pattern }
        var out = ""
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "\\" {
                // 转义序列：连同下一字符原样保留
                out.append(c)
                if i != pattern.index(before: pattern.endIndex) {
                    i = pattern.index(after: i)
                    out.append(pattern[i])
                }
            } else if c == "[" {
                // 字符类：整段原样复制（用户显式控制；未闭合时复制到串尾）
                out.append(c)
                var j = i
                while true {
                    j = pattern.index(after: j)
                    guard j != pattern.endIndex else { break }
                    out.append(pattern[j])
                    if pattern[j] == "]" { break }
                }
                // j 停在 ']'（已复制）或 endIndex（未闭合）；i 移到 ']' 之后
                i = (j == pattern.endIndex) ? j : pattern.index(after: j)
                continue   // i 已就位，跳过末尾自增
            } else if let expansion = iupacRegexExpansion(c) {
                out.append(expansion)
            } else {
                out.append(c)
            }
            i = pattern.index(after: i)
        }
        return out
    }

    /// IUPAC 简并码 → 正则字符类（N 额外匹配字面 N，兼容序列中的未知碱基）
    private static func iupacRegexExpansion(_ c: Character) -> String? {
        switch c {
        case "R": return "[AG]"
        case "Y": return "[CT]"
        case "S": return "[GC]"
        case "W": return "[AT]"
        case "K": return "[GT]"
        case "M": return "[AC]"
        case "B": return "[CGT]"
        case "D": return "[AGT]"
        case "H": return "[ACT]"
        case "V": return "[ACG]"
        case "N": return "[ACGTN]"
        default: return nil
        }
    }

    /// 校验模式是否为合法正则（供 UI 在主线程预检，避免无效正则进入计算）。
    /// 必须与 init 走完全相同的「字面大写化 + IUPAC 翻译」路径，
    /// 否则预检通过的模式在引擎侧可能编译失败或语义不同。
    static func validateRegex(_ pattern: String, scope: SearchScope = .content) -> Bool {
        guard !pattern.isEmpty else { return true }
        do {
            let upLiteral = uppercasingLiterals(pattern)
            let translated = (scope == .content) ? translatePattern(upLiteral, useRegex: true) : upLiteral
            _ = try NSRegularExpression(pattern: translated, options: [.caseInsensitive])
            return true
        } catch {
            return false
        }
    }
}
