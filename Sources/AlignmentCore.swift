//  AlignmentCore.swift
//  SeqAlignMac — 核心数据模型与算法层
//  净室自研实现，不引用任何第三方源码

import Foundation

// MARK: - 枚举定义

enum Datatype: Int32 {
    case nucleicAcid = 0
    case aminoAcid = 1
}

enum ColorScheme: Int32 {
    case minimal = 4            // 极简（默认）：按列保守度灰阶，不按碱基上色
    case defaultNucleotide = 0
    case clustalX = 1
    case zappo = 2
    case seaView = 3
    case transitionTransversion = 5  // 过渡/颠换感知：转换=蓝系，颠换=红系，匹配=灰
    case okabeIto = 6                 // Okabe-Ito 色觉无障碍色板（红绿色盲友好）
}

enum GeneticCodeTable: Int32 {
    case standard = 1
    case vertebrateMito = 2
    case yeast = 3
    case moldProtozoanMito = 4
    case invertebrateMito = 5
    case ciliate = 6
    case echinodermMito = 9
    case bacterial = 11
    case altYeast = 12
    case ascidianMito = 13
    case flatwormMito = 14
    case blepharismaMito = 15    // NCBI 15：Blepharisma 核码（UAG→Q）
    case euplotid = 10           // NCBI 10：Euplotid 核码（UGA→C，UAA/UAG 仍为终止）
    case chlorophycean = 16      // NCBI 16：绿藻线粒体码（UAG→L）
    case pterobranchMito = 24    // NCBI 24：羽腮动物线粒体（AGA→S、AGG→K、UGA→W）
    case sr1 = 25                // NCBI 25：Candidate division SR1（UGA→G）
    case peritrichNuclear = 30   // NCBI 30：Peritrich 核码（UAA/UAG→E）
}

enum PhylipVariant: Int32 {
    case sequential = 0
    case interleaved = 1
    case strict10Char = 2
    case fullnamePadded = 3
}

enum TmMethod: Int32 {
    case nearestNeighbor = 0
    case wallace = 1
}

enum DimerMode: Int32 {
    case selfDimer = 0
    case hetero = 1
}

enum MsfType: Int32 {
    case na = 0
    case aa = 1
}

// MARK: - 数据模型

struct Sequence {
    var name: String
    var description: String
    var residues: [UInt8]
    /// FASTQ Phred 质量值（与残基一一对应；非 FASTQ 来源为 nil）
    var quality: [UInt8]? = nil

    init(name: String, description: String = "", residues: [UInt8], quality: [UInt8]? = nil) {
        self.name = name
        self.description = description
        self.residues = residues
        self.quality = quality
    }
}

struct CharsetInfo {
    var name: String
    var ranges: [(start: UInt32, end: UInt32)] // 1-based inclusive
    /// 原始 CHARSET 表达式（如 `1-60\3`）。列结构未被改动时按原样回写，
    /// 避免把步长定义展开成一串单列区间；任何重映射都会把它置为 nil。
    var originalSpec: String? = nil
}

/// Alignment 是 class（引用类型），持有多变状态 revision / _cachedLength，
/// 后台线程（如统计面板）会调用 snapshot()，而主线程可能同时编辑 sequences 数组，
/// 无同步机制时会触发数组并发访问崩溃，因此用锁保护所有读写操作，
/// 保证 snapshot() 与编辑操作互斥。
/// 锁选用 NSRecursiveLock：撤销/重做命令经 performLocked 统一持锁执行，
/// 命令内部再调用 seqCount / length / padToMaxLength 等同锁 accessor 时可重入，不会自死锁。
final class Alignment {
    var sequences: [Sequence]
    var datatype: Datatype
    var metadata: [String: String]
    var charsets: [CharsetInfo]

    /// 变异版本号：任何会修改 residues / sequences / charsets 的写操作都应自增，
    /// 用于让画布共识缓存、长度缓存等依赖「内容是否变化」的逻辑正确失效。
    var revision: UInt64 = 0

    /// 来源是否为"已比对"：解析器在 padToMaxLength 之前用原始长度判定并写入。
    /// 模型仍保存补齐后的等长序列（渲染与列统计需要），但界面与下游必须据此
    /// 明示"这些列未必同源"，而不是把右补空位的未比对序列当成比对去算统计/建树。
    var provenance: AlignmentProvenance.Status = .unknown

    /// 线程安全锁：保护 sequences 数组的读写，防止后台线程 snapshot() 与主线程编辑并发崩溃
    private let lock = NSRecursiveLock()

    init(sequences: [Sequence] = [], datatype: Datatype = .nucleicAcid,
         metadata: [String: String] = [:], charsets: [CharsetInfo] = []) {
        self.sequences = sequences
        self.datatype = datatype
        self.metadata = metadata
        self.charsets = charsets
    }

    /// 锁内 mutation 通道：命令式编辑统一经本方法持锁执行，
    /// 保证主线程写入与后台线程 snapshot()/lockedSequences() 遍历互斥。
    func performLocked<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    var seqCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sequences.count
    }

    // 长度缓存：基于 revision 失效，避免每次 draw 都 O(n) 全量扫描 + 数组分配。
    private var _cachedLength: Int = 0
    private var _cachedLengthRevision: UInt64 = .max
    var length: Int {
        lock.lock()
        defer { lock.unlock() }
        if _cachedLengthRevision != revision {
            _cachedLength = sequences.reduce(0) { max($0, $1.residues.count) }
            _cachedLengthRevision = revision
        }
        return _cachedLength
    }

    /// 将所有序列补齐到最长长度（右补 '-'）。
    /// FASTQ 来源的 quality 数组必须同步补齐，否则 `Sequence` 声明的
    /// 「质量值与残基一一对应」不变量被破坏，任何"逐列质量"的新功能都会静默错位。
    /// 补 0（Q0）而非 '!'（33），由写出侧换算 Phred+33，避免模型里混入 ASCII 语义。
    func padToMaxLength() {
        lock.lock()
        defer { lock.unlock() }
        let maxLen = sequences.reduce(0) { max($0, $1.residues.count) }
        for i in sequences.indices {
            if sequences[i].residues.count < maxLen {
                sequences[i].residues.append(contentsOf: [UInt8](repeating: 0x2D, count: maxLen - sequences[i].residues.count))
            }
            if sequences[i].quality != nil, sequences[i].quality!.count < maxLen {
                sequences[i].quality!.append(contentsOf: [UInt8](repeating: 0, count: maxLen - sequences[i].quality!.count))
            }
        }
        revision += 1
    }

    /// 获取某行某列的残基（越界或负索引返回 '-'）
    func residue(row: Int, col: Int) -> UInt8 {
        lock.lock()
        defer { lock.unlock() }
        // 负索引通过上界 guard 后会直接越界 trap（视口偏移计算可能产生负值）
        guard row >= 0, row < sequences.count else { return 0x2D }
        let seq = sequences[row]
        guard col >= 0, col < seq.residues.count else { return 0x2D }
        return seq.residues[col]
    }

    /// 获取某列所有残基
    func columnResidues(col: Int) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        guard col >= 0 else { return [UInt8](repeating: 0x2D, count: sequences.count) }
        return sequences.compactMap { seq in
            col < seq.residues.count ? seq.residues[col] : 0x2D
        }
    }

    /// 不可变快照：深拷贝序列残基，供后台线程只读使用，避免与主线程编辑产生数据竞争。
    /// Alignment 为引用类型，直接赋值仅共享同一实例；调用方必须用本方法获得独立副本。
    /// 加锁保护 snapshot 期间的序列遍历，防止主线程同时 remove/insert 导致崩溃。
    func snapshot() -> Alignment {
        lock.lock()
        defer { lock.unlock() }
        let copied = sequences.map {
            Sequence(name: $0.name, description: $0.description,
                     residues: [UInt8]($0.residues),
                     quality: $0.quality.map { [UInt8]($0) })
        }
        return Alignment(sequences: copied, datatype: datatype, metadata: metadata, charsets: charsets)
    }

    /// 线程安全的序列数组只读访问（供后台线程遍历）。
    /// 闭包在锁内同步消费；返回值不得持有内部数组引用出锁——需要带出数据时
    /// 在闭包内复制（如 snapshot()/Array(seqs)），依赖 Array CoW 保证隔离。
    func lockedSequences<T>(_ block: ([Sequence]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block(sequences)
    }
}

// MARK: - 共享序列工具（单一事实来源）

enum SequenceUtils {
    /// 核酸残基反向互补（A↔T/U、C↔G、IUPAC 简并码按互补关系互换、空位与未知不变）。
    /// 翻译、引物计算等场景统一使用本方法，避免多处各自实现造成语义分叉。
    ///
    /// 简并码必须按 IUPAC 定义求互补（互补于「组成碱基集合的互补」），不能原样保留，
    /// 否则 R/Y/K/M/B/D/H/V 会给出错误的反向互补：
    ///   R(A|G)↔Y(C|T)、K(G|T)↔M(A|C)、B(C|G|T)↔V(A|C|G)、D(A|G|T)↔H(A|C|T)，
    ///   S(C|G)、W(A|T)、N 自互补。小写输入先大写化，避免 a/c/g/t 不被互补。
    static func reverseComplement(_ residues: [UInt8]) -> [UInt8] {
        residues.reversed().map { complement($0) }
    }

    /// 单字节核酸互补（不反向）。空位的任意写法归一化为规范空位 '-'。
    static func complement(_ b: UInt8) -> UInt8 {
        switch b {
        case 0x61: return 0x54              // a→T（小写兼容）
        case 0x63: return 0x47              // c→G
        case 0x67: return 0x43              // g→C
        case 0x74, 0x75: return 0x41        // t/u→A
        case 0x41: return 0x54              // A→T
        case 0x54, 0x55: return 0x41        // T/U→A
        case 0x43: return 0x47              // C→G
        case 0x47: return 0x43              // G→C
        case 0x52: return 0x59              // R(A|G)→Y(C|T)
        case 0x59: return 0x52              // Y→R
        case 0x4B: return 0x4D              // K(G|T)→M(A|C)
        case 0x4D: return 0x4B              // M→K
        case 0x42: return 0x56              // B(C|G|T)→V(A|C|G)
        case 0x56: return 0x42              // V→B
        case 0x44: return 0x48              // D(A|G|T)→H(A|C|T)
        case 0x48: return 0x44              // H→D
        case 0x53: return 0x53              // S(C|G) 自互补
        case 0x57: return 0x57              // W(A|T) 自互补
        case 0x4E: return 0x4E              // N→N
        case 0x2D, 0x2E, 0x7E: return 0x2D  // - / . / ~ → 规范空位
        default: return b                   // ? * 0-9 等：无互补语义，原样保留
        }
    }

    /// 判断两个碱基之间是转换（transition）还是颠换（transversion）。
    /// 转换：A↔G, C↔T (嘌呤↔嘌呤, 嘧啶↔嘧啶)
    /// 颠换：A↔C, A↔T, G↔C, G↔T
    /// 返回: 0=匹配, 1=转换, 2=颠换, -1=含空位或非标准碱基
    ///
    /// 本函数是 Ti/Tv 统计的必要构件；歧义判定必须按数据类型分叉，
    /// 否则蛋白比对里的标准氨基酸会被当成未知状态参与定性。
    /// 核酸侧只把真正无法定性的符号（N/X/?）与简并码判为 -1；
    /// 蛋白侧一律返回 -1（转换/颠换只对核酸有意义）。
    static func mutationType(_ a: UInt8, _ b: UInt8) -> Int {
        // 空位与歧义码先于相等判断：gap-vs-gap 与 N-vs-N 不应算「匹配」，
        // N-vs-A 也不应落入颠换分支（N 代表任意碱基，无法定性）
        if ResidueAlphabet.isGap(a) || ResidueAlphabet.isGap(b) { return -1 }
        if ResidueAlphabet.nucleotideUnassignable.contains(a)
            || ResidueAlphabet.nucleotideUnassignable.contains(b) { return -1 }
        if a == b { return 0 }
        // 嘌呤: A(0x41), G(0x47); 嘧啶: C(0x43), T(0x54), U(0x55)
        let purines: Set<UInt8> = [0x41, 0x47]
        let pyrimidines: Set<UInt8> = [0x43, 0x54, 0x55]
        let aIsPurine = purines.contains(a)
        let bIsPurine = purines.contains(b)
        let aIsPyrimidine = pyrimidines.contains(a)
        let bIsPyrimidine = pyrimidines.contains(b)
        if (aIsPurine && bIsPurine) || (aIsPyrimidine && bIsPyrimidine) {
            return 1 // 转换
        }
        return 2 // 颠换
    }

    /// GC 含量计算（返回 0.0..1.0）。
    /// 分母只统计可判定碱基 A/C/G/T/U（对齐 EMBOSS 口径）：
    /// N 等歧义码进入分母会系统性低估 GC%，'-' 同样不计。
    /// GC 在本工程内以本函数为唯一实现；`stats` 等导出路径必须调用本函数而不是自己数，
    /// 否则同一指标在界面与 `cli stats` 导出的 CSV 里给出两个不同的数。
    static func gcContent(_ residues: [UInt8]) -> Double {
        var gc = 0
        var acgt = 0
        for b in residues {
            switch b {
            case 0x47, 0x43: gc += 1; acgt += 1          // G / C
            case 0x41, 0x54, 0x55: acgt += 1             // A / T / U
            default: break
            }
        }
        guard acgt > 0 else { return 0 }
        return Double(gc) / Double(acgt)
    }

    /// 有效（非空位）长度
    static func effectiveLength(_ residues: [UInt8]) -> Int {
        residues.filter { $0 != 0x2D }.count
    }
}

// MARK: - 数据类型判定（单一事实来源）

/// 判型白名单为全部 IUPAC 核酸码（含简并码 RYSWKMBDHV）：只含 "ACGTUN-" 的
/// 窄白名单会把含简并码的核酸比对误判为蛋白质，导致翻译/引物计算被禁用。
/// 检测采用采样策略——均匀抽取至多 100 条序列的两个窗口，避免大文件全量扫描的
/// 数千万次 Set 查找。
///
/// 白名单收敛到 `ResidueAlphabet.nucleotideCharacters`，覆盖解析器实际接受的
/// '.'（PHYLIP/HMMER 空位写法）、'*'（终止密码子）、'?'（缺失）与数字简并码 0-9；
/// 缺少这些字符时，"用 . 作空位的核酸比对""含终止密码子的 CDS 比对"
/// 会在第一个越界字符处就被判为蛋白，进而启用蛋白着色/蛋白歧义集、禁用 GC 与翻译。
///
/// 判型口径（"由声明字段判型"与"由残基字母表判型"）统一由本枚举给出，
/// NEXUS 的 DATATYPE 声明解析（AlignmentParsers）共用 `datatype(fromDeclaration:)`。
enum DatatypeDetector {
    /// 全部 IUPAC 核酸字符（含简并码、空位写法、终止符、缺失与数字简并码）
    static var nucleotideChars: Set<UInt8> { ResidueAlphabet.nucleotideCharacters }

    /// 采样检测上限：抽样步长取上取整，保证实际检查条数严格不超过 maxSampleSeqs 条。
    private static let maxSampleSeqs = 100
    /// 每条序列检查的残基数：N 端 50 + 中部 50（合计 100，但**不是**"前 100 个残基"）。
    private static let maxSampleResidues = 100

    static func detect(_ sequences: [Sequence]) -> Datatype {
        let seqCount = sequences.count
        guard seqCount > 0 else { return .nucleicAcid }

        // 采样——均匀抽取至多 maxSampleSeqs 条序列（step 上取整，保证条数不超过上限）；
        // 每条同时检查头窗口与中位窗口（前部常为测序接头/引物区，
        // 只查头部会把主体为蛋白的拼接序列误判为核酸）
        let step = max(1, (seqCount + maxSampleSeqs - 1) / maxSampleSeqs)
        func windowIsNucleic(_ seq: Sequence, start: Int, count: Int) -> Bool {
            let n = min(count, max(0, seq.residues.count - start))
            for j in start..<(start + n) where !nucleotideChars.contains(seq.residues[j]) {
                return false
            }
            return true
        }
        for i in stride(from: 0, to: seqCount, by: step) {
            let seq = sequences[i]
            let headCount = min(maxSampleResidues / 2, seq.residues.count)
            if !windowIsNucleic(seq, start: 0, count: headCount) { return .aminoAcid }
            let mid = seq.residues.count / 2
            if !windowIsNucleic(seq, start: mid, count: maxSampleResidues / 2) { return .aminoAcid }
        }
        return .nucleicAcid
    }

    /// 由 NEXUS `DATATYPE=` 声明字段判型（声明判型的单一入口）。
    /// NEXUS 的声明写法多样（有无等号、PROT/AMINO/AA/DNA/RNA/NUC 等关键字），
    /// 必须归一后统一匹配，只认个别写法会让其余写法落到核酸默认值。
    static func datatype(fromDeclaration decl: String) -> Datatype? {
        // 去掉空白与等号后按关键字前缀匹配：DATATYPE=PROTEIN / DATATYPE PROTEIN / dtype=aa
        let normalized = decl.uppercased()
            .replacingOccurrences(of: "=", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        guard let idx = normalized.firstRange(of: "DATATYPE")?.lowerBound else {
            // NEXUS 也允许 `#NEXUS` 后无 DATATYPE 的裸声明（如 "PROT"）
            let bare = normalized.replacingOccurrences(of: " ", with: "")
            if bare.hasPrefix("PROT") || bare.hasPrefix("AMINO") || bare.hasPrefix("AA") { return .aminoAcid }
            if bare.hasPrefix("DNA") || bare.hasPrefix("RNA") || bare.hasPrefix("NUC") { return .nucleicAcid }
            return nil
        }
        let tail = normalized[idx...].dropFirst("DATATYPE".count)
            .replacingOccurrences(of: " ", with: "")
        if tail.hasPrefix("PROT") || tail.hasPrefix("AMINO") || tail.hasPrefix("AA") { return .aminoAcid }
        if tail.hasPrefix("DNA") || tail.hasPrefix("RNA") || tail.hasPrefix("NUC") { return .nucleicAcid }
        return nil
    }
}

// MARK: - 进度回调

typealias ProgressCallback = (UInt64, UInt64) -> Void

// MARK: - 错误类型

enum CoreError: Error, LocalizedError {
    case io(String)
    case format(String)
    case noMem(String)
    case invalidArg(String)
    case outOfRange(String)
    case unsupported(String)
    case external(String)
    case partial(String)


    var errorDescription: String? {
        switch self {
        case .io(let m): return "IO 错误: \(m)"
        case .format(let m): return "格式错误: \(m)"
        case .noMem(let m): return "内存不足: \(m)"
        case .invalidArg(let m): return "无效参数: \(m)"
        case .outOfRange(let m): return "索引越界: \(m)"
        case .unsupported(let m): return "不支持的操作: \(m)"
        case .external(let m): return "外部命令失败: \(m)"
        case .partial(let m): return "部分成功: \(m)"
        }
    }
}

// MARK: - 错误机制说明
//
// 本工程统一采用 Swift 原生 `throw CoreError` 错误模型：
// 所有领域函数（含 PrimerCalculator.tm）一律通过 throws 向上传递错误，不依赖全局可变状态。
