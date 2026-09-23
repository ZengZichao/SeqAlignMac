//  PrimerCalculator.swift
//  SeqAlignMac — 引物 Tm / GC / 二聚体计算
//  依据 -SPEC.md  实现
//  算法依据：SantaLucia 1998（统一近邻参数 + 末端校正）、von Ahsen et al 1999（盐校正）

import Foundation

// MARK: - Tm 计算选项

struct TmOptions {
    var naMolar: Double = 0.05    // Na+ 浓度（M）
    var mgMolar: Double = 0.0     // Mg2+ 浓度（M）
    var oligoMolar: Double = 0.25e-6 // 寡链浓度（M）
    /// dNTP 浓度（M）。Mg2+ 会被 dNTP 螯合，[dNTPs] >= [Mg2+] 时视为无游离 Mg2+。
    var dntpMolar: Double? = nil

    static let `default` = TmOptions()
}

// MARK: - IUPAC 简并码

enum IUPACCode {
    /// IUPAC 简并码 → 展开碱基集合
    static func expand(_ code: Character) -> [Character] {
        switch code.uppercased().first {
        case "A": return ["A"]
        case "C": return ["C"]
        case "G": return ["G"]
        case "T": return ["T"]
        case "U": return ["U"]
        case "R": return ["A", "G"]
        case "Y": return ["C", "T"]
        case "S": return ["G", "C"]
        case "W": return ["A", "T"]
        case "K": return ["G", "T"]
        case "M": return ["A", "C"]
        case "B": return ["C", "G", "T"]
        case "D": return ["A", "G", "T"]
        case "H": return ["A", "C", "T"]
        case "V": return ["A", "C", "G"]
        // 'N' 必须同时能匹配数据里的字面 N，否则同一句 NNN 查询
        // 关掉正则开关就匹配不到 N（正则路径显式写了 [ACGTN]，两条路径互相矛盾），
        // 而真实 GenBank / 条码序列里 N 极多。
        case "N": return ["A", "C", "G", "T"]
        default: return [code]
        }
    }

    /// 检索专用的 IUPAC 展开。与 `expand` 分开的理由是必要的：
    /// `expand` 同时服务于引物简并度与变体枚举，把字面 'N' 混进变体集合会让
    /// `PrimerCalculator.tm` 收到 NN 法无法计算的"N"（实测抛错），
    /// 而检索侧恰恰**必须**能命中数据里的字面 N —— 正则路径写的就是 `[ACGTN]`，
    /// 非正则路径过去只给 `[ACGT]`，于是同一句 NNN 开关正则前后结果不同。
    /// 另外 T/U 在翻译、统计、配色里都被当作同一条碱基（ColumnStats / ColorLogic），
    /// 检索 RNA 序列或其 DNA 反向转录本时同样必须互通。
    static func expandForSearch(_ code: Character) -> [Character] {
        var set = expand(code)
        set.append(code)                       // 字面字符本身也是合法匹配对象
        if code == "T" { set.append("U") }
        if code == "U" { set.append("T") }
        return Array(Set(set)).sorted()
    }

    /// 简并度的两种口径：
    /// - `lowerBound`：把 gap / 未知位按"可判定"的最小方式计入（gap→0 个候选、N→4）。
    /// - `upperBound`：把 gap / 未知位按最坏方式计入（未知→4）。
    /// (min, max) 两个分支不得乘同一个 count：若恒等，
    /// 承诺了一个不存在的区分，接 UI 时会显示假的范围。这里给出真实语义。
    enum DegeneracyScope {
        case knownOnly      // 只统计可判定位置（gap 不参与乘法）
        case worstCase      // gap / 未知一律按最大简并度 4 计
    }

    /// 计算简并度（min, max）。
    /// 溢出保护：Swift 整数乘法上溢即 trap（16 个全歧义位即 4^16 > UInt32.max），
    /// 这里改为饱和语义——超过上限时返回 UInt32.max，表示「简并度 ≥ 2^32-1」。
    static func degeneracy(_ seq: String) -> (min: UInt32, max: UInt32) {
        // 真正的 min/max 区分"可判定位置的简并度"与"含 gap / 未知位时的取值范围"。
        // · min（下界）：跳过 gap（0 个候选 = 不贡献乘法），未知码按 1 计（最保守读法：
        //   该位其实只有 1 种可能），得到"确定简并度"。
        // · max（上界）：gap 按 1 计、未知码（N=4、R/Y=2…）按其展开基数计，
        //   得到"最坏情形变体数"。
        // 溢出保护与饱和语义在此实现。
        var minD: UInt32 = 1
        var maxD: UInt32 = 1
        var minSaturated = false
        var maxSaturated = false
        func mul(_ a: inout UInt32, _ b: UInt32, _ saturated: inout Bool) {
            if saturated { a = .max; return }
            let (r, o) = a.multipliedReportingOverflow(by: b)
            if o { saturated = true; a = .max } else { a = r }
        }
        for c in seq {
            if c == "-" || c == "." || c == "~" {
                mul(&maxD, 1, &maxSaturated)          // gap：上界按 1 计（不引入新变体）
                continue                              // gap：下界直接跳过
            }
            let expanded = expand(c)
            let count = UInt32(expanded.count)
            guard count > 0 else { continue }
            // N/R/Y/… 等歧义码：下界按 1（该位可能是任意单一残基），上界按展开基数
            let isDegenerate = count > 1
            mul(&minD, isDegenerate ? 1 : count, &minSaturated)
            mul(&maxD, count, &maxSaturated)
        }
        return (minD, maxD)
    }

    /// 展开所有 IUPAC 变体（上限 limit）
    static func expandAll(_ seq: String, limit: Int = 4096) -> [String]? {
        var results: [String] = [""]
        for c in seq {
            let expanded = expand(c)
            // 提前超限返回，避免先构建远超上限的大数组再丢弃（如全 N 的 7-mer）
            if results.count * expanded.count > limit {
                return nil
            }
            var newResults: [String] = []
            for r in results {
                for b in expanded {
                    newResults.append(r + String(b))
                }
            }
            results = newResults
            if results.count > limit {
                return nil // 超限
            }
        }
        return results
    }
}

// MARK: - SantaLucia 1998 统一近邻参数

enum NNTeplexParameters {
    // ΔH (kcal/mol), ΔS (cal/(mol·K)) — SantaLucia 1998 统一近邻参数
    // 10 个唯一 NN 双联体（含反向互补对等）
    static let nnParams: [String: (deltaH: Double, deltaS: Double)] = [
        "AA": (-7.9, -22.2), "TT": (-7.9, -22.2),
        "AT": (-7.2, -20.4),
        "TA": (-7.2, -21.3),
        "CA": (-8.5, -22.7), "TG": (-8.5, -22.7),
        "GT": (-8.4, -22.4), "AC": (-8.4, -22.4),
        "CT": (-7.8, -21.0), "AG": (-7.8, -21.0),
        "GA": (-8.2, -22.2), "TC": (-8.2, -22.2),
        "CG": (-10.6, -27.2), // CG 正确值
        "GC": (-9.8, -24.4),   // GC 正确值（非 -10.6）
        "GG": (-8.0, -19.9), "CC": (-8.0, -19.9),
    ]

    // 末端校正（SantaLucia 1998 统一参数的 helix initiation 项）
    // 注：统一参数中末端项本身已完整包含通用初始化贡献（init w/ term G·C = 0.1/-2.8，
    // init w/ term A·T = 2.3/4.1），不要再叠加通用 ΔH 0.2/ΔS -5.7，否则重复计算。
    // 末端 G/C：ΔH += 0.1, ΔS += -2.8
    // 末端 A/T：ΔH += 2.3, ΔS += 4.1
    static func terminalCorrection(_ first: Character, _ last: Character) -> (deltaH: Double, deltaS: Double) {
        var dH = 0.0, dS = 0.0
        // 5' 端
        let is5GC = first == "G" || first == "C"
        if is5GC { dH += 0.1; dS += -2.8 }
        else { dH += 2.3; dS += 4.1 }
        // 3' 端
        let is3GC = last == "G" || last == "C"
        if is3GC { dH += 0.1; dS += -2.8 }
        else { dH += 2.3; dS += 4.1 }
        return (dH, dS)
    }
}

// MARK: - 引物计算器

enum PrimerCalculator {
    // MARK: 简并度
    static func degeneracy(_ seq: String) -> (min: UInt32, max: UInt32) {
        IUPACCode.degeneracy(seq)
    }

    // MARK: Tm 计算
    static func tm(_ seq: String, method: TmMethod = .nearestNeighbor,
                   options: TmOptions = .default) throws -> (min: Double, max: Double) {
        let upperSeq = seq.uppercased()

        switch method {
        case .wallace:
            // Wallace 规则：Tm = 2*(A+T) + 4*(G+C)
            if let variants = IUPACCode.expandAll(upperSeq) {
                var tms: [Double] = []
                for v in variants {
                    let aT = v.filter { $0 == "A" || $0 == "T" || $0 == "U" }.count
                    let gC = v.filter { $0 == "G" || $0 == "C" }.count
                    tms.append(Double(2 * aT + 4 * gC))
                }
                return (tms.min() ?? 0, tms.max() ?? 0)
            } else {
                throw CoreError.unsupported("简并引物展开超过 4096 上限")
            }
        case .nearestNeighbor:
            // NN 法（SantaLucia 1998 含末端校正 + 盐校正 von Ahsen 1999）
            // 参数校验：非法盐浓度会经 sqrt/log 产出 NaN 的「伪科学结果」
            guard options.naMolar > 0, options.mgMolar >= 0, options.oligoMolar > 0 else {
                throw CoreError.unsupported("盐浓度参数非法（Na+ 必须 > 0，Mg2+ 必须 ≥ 0，oligo 必须 > 0）")
            }
            if let variants = IUPACCode.expandAll(upperSeq) {
                var tms: [Double] = []
                for v in variants {
                    // NN 表只覆盖 ACGT 双联体：U/gap 等字符会静默跳过 NN 贡献，
                    // 产生貌似合理实则失真的 Tm，这里显式报错
                    guard v.allSatisfy({ $0 == "A" || $0 == "C" || $0 == "G" || $0 == "T" }) else {
                        throw CoreError.unsupported("序列含 NN 法无法计算的字符（如 U 或 gap）：\(v)")
                    }
                    if let tm = calculateNNTm(v, options: options) {
                        tms.append(tm)
                    }
                }
                if tms.isEmpty {
                    throw CoreError.unsupported("序列过短或无效，无法计算 NN-Tm（至少需要 2 个碱基）")
                }
                return (tms.min()!, tms.max()!)
            } else {
                throw CoreError.unsupported("简并引物展开超过 4096 上限")
            }
        }
    }

    /// SantaLucia 1998 NN 法计算 Tm
    private static func calculateNNTm(_ seq: String, options: TmOptions) -> Double? {
        let chars = Array(seq)
        guard chars.count >= 2 else { return nil }

        var dH = 0.0 // kcal/mol
        var dS = 0.0 // cal/(mol·K)

        // 末端校正
        let termCorr = NNTeplexParameters.terminalCorrection(chars[0], chars[chars.count - 1])
        dH += termCorr.deltaH
        dS += termCorr.deltaS

        // NN 参数累加
        for i in 0..<(chars.count - 1) {
            let nn = String(chars[i]) + String(chars[i + 1])
            if let params = NNTeplexParameters.nnParams[nn] {
                dH += params.deltaH
                dS += params.deltaS
            } else {
                // 尝试反向互补
                let rcNN = reverseComplement(nn)
                if let params = NNTeplexParameters.nnParams[rcNN] {
                    dH += params.deltaH
                    dS += params.deltaS
                }
            }
        }

        // 盐校正：等效单价阳离子浓度（von Ahsen 路线）
        //
        // 采用的式子
        //     [Na+]_eq (mM) = [Na+] + [K+] + [Tris]/2 + 120 * sqrt([Mg2+] - [dNTPs])
        // 其中**全部浓度为 mM**，且根号内是 (Mg - dNTP)（dNTP 螯合 Mg2+）；
        // 当 [dNTPs] >= [Mg2+] 时认为无游离 Mg2+，不追加该项。
        // 本实现的输入字段单位为 M（UI 以 mM/µM 收集后换算），故先换算到 mM 再套式。
        var saltMm = options.naMolar * 1000.0
        if options.mgMolar > 0 {
            let mgMm = options.mgMolar * 1000.0
            let dntpMm = (options.dntpMolar ?? 0) * 1000.0
            let freeMgMm = mgMm - dntpMm
            if freeMgMm > 0 { saltMm += 120.0 * sqrt(freeMgMm) }
        }
        let n = Double(chars.count)
        let saltEffect = max(saltMm / 1000.0, 0.001)   // 回到 M，供 SantaLucia 的 ln 项使用
        dS = dS + 0.368 * (n - 1) * log(saltEffect)

        // Tm = ΔH×1000 / (ΔS(salt) + R×ln(C_T/x)) − 273.15
        let R = 1.987 // cal/(mol·K)
        // 判断是否自互补（回文序列）
        let isSelfComplementary = isPalindrome(seq)
        let x = isSelfComplementary ? 1.0 : 4.0
        let ct = options.oligoMolar
        let denominator = dS + R * log(ct / x)
        guard abs(denominator) > 1e-10 else { return nil }
        let tm = (dH * 1000.0) / denominator - 273.15
        return tm
    }

    private static func isPalindrome(_ seq: String) -> Bool {
        let chars = Array(seq)
        let rc = String(chars.reversed().map { complementChar($0) })
        return seq == rc
    }

    private static func complementChar(_ c: Character) -> Character {
        switch c {
        case "A": return "T"
        case "T": return "A"
        case "C": return "G"
        case "G": return "C"
        case "U": return "A"
        default: return c
        }
    }

    private static func reverseComplement(_ s: String) -> String {
        let bytes = Array(s.utf8)
        let rc = SequenceUtils.reverseComplement(bytes)
        return String(bytes: rc, encoding: .ascii) ?? s
    }

    // MARK: GC 含量
    static func gcContent(_ seq: String) -> Double {
        let upper = seq.uppercased()
        let total = upper.filter { $0 == "A" || $0 == "C" || $0 == "G" || $0 == "T" || $0 == "U" }.count
        guard total > 0 else { return 0.0 }
        let gc = upper.filter { $0 == "G" || $0 == "C" }.count
        return Double(gc) / Double(total)
    }

    // MARK: 二聚体 ΔG
    /// 基于 NN 热力学的最长 3′ 端互补配对 ΔG 估算
    /// 输入长度上限——dimer 为 O(n×m) 滑动枚举，误贴 10kb 序列会主线程冻结；
    /// 与 Tm 路径的 4096 展开上限（IUPACCode.expandAll）同一保护思路
    static let maxDimerInputLength = 200

    static func dimer(_ a: String, b: String? = nil, mode: DimerMode = .selfDimer) -> Double {
        // 超长输入截断：二聚体倾向由 3′ 端局部互补主导，200 nt 远超判别所需
        let seqA = Array(a.uppercased().prefix(maxDimerInputLength))
        let seqB: [Character]
        switch mode {
        case .selfDimer:
            // 取 a 的反向互补链
            seqB = seqA.reversed().map { complementChar($0) }
        case .hetero:
            seqB = Array((b ?? "").uppercased().prefix(maxDimerInputLength)).reversed().map { complementChar($0) }
        }

        guard seqA.count >= 4 && seqB.count >= 4 else { return 0.0 }

        var bestDg = 0.0
        // 滑动枚举 a 的 3′ 后缀与互补链的对齐位置
        // 以 a 的 3′ 端后缀为锚（从长到短）
        for aStart in (0..<seqA.count).reversed() {
            let aSuffix = Array(seqA[aStart...]) // a 的 3′ 后缀

            // 在 seqB 上滑动寻找连续互补窗口
            for bStart in 0..<seqB.count {
                var windowLen = 0
                var dg = 0.0

                // 检查连续互补
                while windowLen < aSuffix.count && (bStart + windowLen) < seqB.count {
                    let aChar = aSuffix[windowLen]
                    let bChar = seqB[bStart + windowLen]

                    // 仅标准碱基互补
                    if isComplementary(aChar, bChar) {
                        windowLen += 1
                    } else {
                        break // 窗口断裂
                    }
                }

                if windowLen >= 4 {
                    // 累加 NN ΔG
                    dg = calculateWindowDg(aSuffix, seqB, bStart, windowLen)
                    if dg < bestDg {
                        bestDg = dg
                    }
                }
            }
        }
        return bestDg
    }

    private static func isComplementary(_ a: Character, _ b: Character) -> Bool {
        let pair = "\(a)\(b)"
        return pair == "AT" || pair == "TA" || pair == "GC" || pair == "CG" ||
               pair == "AU" || pair == "UA"
    }

    /// 计算窗口的 ΔG（NN 双联体 ΔG + 末端校正）
    private static func calculateWindowDg(_ aSuffix: [Character], _ bSeq: [Character],
                                           _ bStart: Int, _ windowLen: Int) -> Double {
        // ΔG = ΔH - T×ΔS（37°C = 310.15K）
        let T = 310.15 // 37°C
        var dG = 0.0

        // 末端校正
        let termCorr = NNTeplexParameters.terminalCorrection(aSuffix[0], aSuffix[windowLen - 1])
        dG += termCorr.deltaH * 1000.0 - T * termCorr.deltaS

        // NN 双联体 ΔG
        for i in 0..<(windowLen - 1) {
            let nn = String(aSuffix[i]) + String(aSuffix[i + 1])
            if let params = NNTeplexParameters.nnParams[nn] {
                dG += params.deltaH * 1000.0 - T * params.deltaS
            }
        }

        return dG / 1000.0 // 转回 kcal/mol
    }
}
