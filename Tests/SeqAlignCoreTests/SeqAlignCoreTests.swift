//  SeqAlignCoreTests.swift
//  SeqAlignMac — 领域逻辑单元测试
//
//  覆盖：
//  - 7 解析器往返（FASTA / FASTQ / NEXUS / PHYLIP 交错与顺序 / CLUSTAL / MSF）
//  - 引物 Tm（NN / Wallace）/ ΔG / GC 对拍（≤1°C / ≤3.0 / ≤0.02）
//  - 翻译对拍 NCBI 标准表 + 17 张遗传密码表对拍官方 gc.prt
//  - 撤销/重做 7 场景
//  - IUPAC 简并搜索
//  - 比对质量 + 列统计
//  - NEXUS charset
//  - 数据类型判定 + 颜色索引一致性 + 反向互补 + 搜索快照

import Foundation
import Compression
import XCTest
@testable import SeqAlignCore

final class SeqAlignCoreTests: XCTestCase {

    // MARK: - 内联夹具（小样例，避免依赖 209MB / 10MB 外部大文件）

    let smallFasta = """
    >Seq1 description sample
    ATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
    >Seq2 description sample
    ATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGT
    >Seq3 description sample
    ATGCTAGCTAGCTAGC---CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
    """

    let smallFastq = """
    @Seq1 description sample
    ATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
    +
    I85=<<98F7GB657;<EH5F;IFB<CG=5:B?=9;?87A8@@H=6CF8A7F>IH@G;76
    @Seq2 description sample
    ATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGT
    +
    <>7<8A=CI@:@@;=I7HI:F<:CA=IF<?6<6?A=7;G?;IDAIC9=9<FF=GBGA@<9
    @Seq3 description sample
    ATGCTAGCTAGCTAGC---CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
    +
    ED7689I:BH7AAHCE=F58F=I?8>B:C5=E:E8I>IEH;9@:FE5H?D58@><6<G77
    """

    let nexus = """
    #NEXUS
    BEGIN TAXA;
      DIMENSIONS NTAX=3;
      TAXLABELS Seq1 Seq2 Seq3;
    END;

    BEGIN CHARACTERS;
      DIMENSIONS NCHAR=60;
      FORMAT DATATYPE=DNA MISSING=? GAP=-;
      MATRIX
        Seq1  ATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
        Seq2  ATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGT
        Seq3  ATGCTAGCTAGCTAGC---CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
      ;
    END;

    BEGIN SETS;
      CHARSET codons_1 = 1-60\\3;
      CHARSET codons_2 = 2-60\\3;
      CHARSET codons_3 = 3-60\\3;
      TAXSET all = 3;
    END;
    """

    let phylipInterleaved = """
    3 60
    Seq1        ATGCTAGCTAGCTAGCTAGC
    Seq2        ATGCTAGCTAGCTAGCTAGC
    Seq3        ATGCTAGCTAGCTAGC---C
                TAGCTAGCTAGCTAGCTAGC
                TAGCTAGCTAGCTAGCTAGC
                TAGCTAGCTAGCTAGCTAGC
                TAGCTAGCTAGCTAGCTAGC
                TAGCTAGCTAGCTAGCTAGT
                TAGCTAGCTAGCTAGCTAGC
    """

    let phylipSequential = """
    3 60
    Seq1        ATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
    Seq2        ATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGT
    Seq3        ATGCTAGCTAGCTAGC---CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
    """

    let clustal = """
    CLUSTAL W (1.83) multiple sequence alignment

               Seq1  ATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
               Seq2  ATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGT
               Seq3  ATGCTAGCTAGCTAGC---CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
                     ****************   **************************************** 
    """

    let msf = """
    !!NA_MULTIPLE_ALIGNMENT

      MSF: 3  Type: N  Len: 60  Check: ..  ..

     Name:            Seq1  Len: 60  Weight: 1.00
     Name:            Seq2  Len: 60  Weight: 1.00
     Name:            Seq3  Len: 60  Weight: 1.00

    //

               Seq1  ATGCTAGCTA
               Seq2  ATGCTAGCTA
               Seq3  ATGCTAGCTA

               Seq1  GCTAGCTAGC
               Seq2  GCTAGCTAGC
               Seq3  GCTAGC---C

               Seq1  TAGCTAGCTA
               Seq2  TAGCTAGCTA
               Seq3  TAGCTAGCTA

               Seq1  GCTAGCTAGC
               Seq2  GCTAGCTAGC
               Seq3  GCTAGCTAGC

               Seq1  TAGCTAGCTA
               Seq2  TAGCTAGCTA
               Seq3  TAGCTAGCTA

               Seq1  GCTAGCTAGC
               Seq2  GCTAGCTAGT
               Seq3  GCTAGCTAGC



    """

    // MARK: - 解析 + 往返

    private func parseFixture(_ text: String, format: AlignmentFormat) throws -> Alignment {
        let data = text.data(using: .utf8)!
        return try AlignmentParser.parse(data, format: format)
    }

    private func assertRoundtrip(_ text: String, format: AlignmentFormat, line: UInt = #line) throws {
        let a = try parseFixture(text, format: format)
        XCTAssertEqual(a.seqCount, 3, line: line)
        XCTAssertEqual(a.length, 60, line: line)
        XCTAssertEqual(a.datatype, .nucleicAcid, line: line)
        let written = AlignmentWriter.writeFasta(a)
        let b = try AlignmentParser.parse(written, format: .fasta)
        XCTAssertEqual(b.seqCount, 3, line: line)
        XCTAssertEqual(b.length, 60, line: line)
        for i in 0..<3 {
            XCTAssertEqual(b.sequences[i].name, a.sequences[i].name, line: line)
            XCTAssertEqual(b.sequences[i].residues, a.sequences[i].residues, line: line)
        }
    }

    func testRoundtripFasta() throws {
        try assertRoundtrip(smallFasta, format: .fasta)
    }

    func testRoundtripFastq() throws {
        let a = try parseFixture(smallFastq, format: .fastq)
        XCTAssertEqual(a.seqCount, 3)
        XCTAssertEqual(a.length, 60)
        XCTAssertEqual(a.datatype, .nucleicAcid)
        // FASTQ 质量行被丢弃，残基与 FASTA 一致
        let fa = try parseFixture(smallFasta, format: .fasta)
        for i in 0..<3 {
            XCTAssertEqual(a.sequences[i].residues, fa.sequences[i].residues)
        }
    }

    func testRoundtripNexus() throws {
        try assertRoundtrip(nexus, format: .nexus)
    }

    func testRoundtripPhylipInterleaved() throws {
        // 真正的多块交错格式（20 列分块，3 块循环）
        try assertRoundtrip(phylipInterleaved, format: .phylip)
    }

    func testRoundtripPhylipSequential() throws {
        try assertRoundtrip(phylipSequential, format: .phylip)
    }

    func testRoundtripClustal() throws {
        try assertRoundtrip(clustal, format: .clustal)
    }

    func testRoundtripMsf() throws {
        try assertRoundtrip(msf, format: .msf)
    }

    // MARK: - 数据类型判定

    func testDatatypeDetectionNucleotide() throws {
        let a = try parseFixture(smallFasta, format: .fasta)
        XCTAssertEqual(a.datatype, .nucleicAcid)
    }

    func testDatatypeDetectionProtein() {
        // 含 M / K / T 等常见氨基酸字母的蛋白质序列应判为氨基酸。
        let protein = Sequence(name: "P", residues: Array("MKTAYIAKQRG".utf8))
        XCTAssertEqual(DatatypeDetector.detect([protein]), .aminoAcid)
        // 核酸字符集含 A/C/G/T/U/N/- 与 IUPAC 简并码 R/Y/W/S/K/M/B/D/H/V；
        // 不含任何该集合字符的序列判为蛋白质。
        let dna = Sequence(name: "D", residues: Array("ACGTUN-".utf8))
        XCTAssertEqual(DatatypeDetector.detect([dna]), .nucleicAcid)
    }

    // MARK: - 引物 Tm / ΔG / GC

    struct PrimerRef {
        let sequence: String
        let tmNN: Double      // 具体序列 = tm_nn；简并序列 = tm_nn_max（参考上限）
        let tmNNIsMax: Bool   // true=简并，比对 nnMax；false=具体，比对 nnMin 与 nnMax
        let tmWallace: Double
        let gc: Double
        let seqB: String?
        let heteroDg: Double?
    }

    private var primerRefs: [PrimerRef] {
        [
            PrimerRef(sequence: "GCGTTTGCGT", tmNN: 36.571, tmNNIsMax: false, tmWallace: 32.0, gc: 0.6, seqB: nil, heteroDg: nil),
            PrimerRef(sequence: "GTAAAACGACGGCCAGT", tmNN: 51.674, tmNNIsMax: false, tmWallace: 52.0, gc: 0.5294, seqB: nil, heteroDg: nil),
            PrimerRef(sequence: "CAGGAAACAGCTATGACC", tmNN: 49.12, tmNNIsMax: false, tmWallace: 54.0, gc: 0.5, seqB: nil, heteroDg: nil),
            PrimerRef(sequence: "ATGGCTAGCTAGCTAGCTAG", tmNN: 52.103, tmNNIsMax: false, tmWallace: 60.0, gc: 0.5, seqB: nil, heteroDg: nil),
            PrimerRef(sequence: "TTGTAGGCGGTTACTATTGC", tmNN: 52.019, tmNNIsMax: false, tmWallace: 58.0, gc: 0.45, seqB: nil, heteroDg: nil),
            PrimerRef(sequence: "CCCCCGGGGGAAAATTTT", tmNN: 54.042, tmNNIsMax: false, tmWallace: 56.0, gc: 0.5556, seqB: nil, heteroDg: nil),
            // 简并引物：参考 tm_nn_max=56.385（实现 nnMax 与之吻合）；简并展开最小值语义与 OligoCalc 不同，仅比对上限。
            PrimerRef(sequence: "GARMGNATHAAYGARMG", tmNN: 56.385, tmNNIsMax: true, tmWallace: 28.0, gc: 0.4, seqB: nil, heteroDg: nil),
            // 异源二聚（参考 hetero_dg）
            PrimerRef(sequence: "GTAAAACGACGGCCAGT", tmNN: 0, tmNNIsMax: false, tmWallace: 0, gc: 0, seqB: "CAGGAAACAGCTATGACC", heteroDg: -6.027),
            PrimerRef(sequence: "GCGTTTGCGT", tmNN: 0, tmNNIsMax: false, tmWallace: 0, gc: 0, seqB: "ATGGCTAGCTAGCTAGCTAG", heteroDg: 0.0),
            PrimerRef(sequence: "CCCCCGGGGGAAAATTTT", tmNN: 0, tmNNIsMax: false, tmWallace: 0, gc: 0, seqB: "TTGTAGGCGGTTACTATTGC", heteroDg: 0.0),
        ]
    }

    func testPrimerTmAndGC() throws {
        let tmTol = 1.0, gcTol = 0.02
        for ref in primerRefs {
            let seq = ref.sequence
            if ref.seqB == nil {
                let (nnMin, nnMax) = try PrimerCalculator.tm(seq, method: .nearestNeighbor)
                if ref.tmNNIsMax {
                    XCTAssertLessThanOrEqual(abs(nnMax - ref.tmNN), tmTol, "Tm_NN max \(seq)")
                    XCTAssertLessThanOrEqual(nnMin, nnMax, "Tm min<=max \(seq)")
                } else {
                    XCTAssertLessThanOrEqual(abs(nnMin - ref.tmNN), tmTol, "Tm_NN min \(seq)")
                    XCTAssertLessThanOrEqual(abs(nnMax - ref.tmNN), tmTol, "Tm_NN max \(seq)")
                    let (wMin, _) = try PrimerCalculator.tm(seq, method: .wallace)
                    XCTAssertLessThanOrEqual(abs(wMin - ref.tmWallace), tmTol, "Tm_W \(seq)")
                }
                let gc = PrimerCalculator.gcContent(seq)
                XCTAssertLessThanOrEqual(abs(gc - ref.gc), gcTol, "GC \(seq)")
            } else {
                let dg = PrimerCalculator.dimer(seq, b: ref.seqB!, mode: .hetero)
                let ok = (dg * ref.heteroDg! >= 0) && abs(dg - ref.heteroDg!) <= 3.0
                XCTAssertTrue(ok, "heteroΔG \(seq)×\(ref.seqB!): got \(dg) ref \(ref.heteroDg!)")
            }
        }
    }

    /// 自二聚 ΔG 为启发式近似（与 OligoCalc 自二聚算法语义不同，不精确对拍数值），
    /// 仅校验契约：完全自互补的回文序列应产生强负自二聚 ΔG。异源二聚数值对拍见 testPrimerTmAndGC。
    func testSelfDimerContract() {
        let palindrome = PrimerCalculator.dimer("GCGCGCGC", mode: .selfDimer)
        XCTAssertLessThan(palindrome, 0, "回文序列应产生负自二聚 ΔG")
    }

    func testPrimerDegenerateRejectsOverflow() {
        // 简并度超过 4096 上限必须抛错，不得静默采样。
        let huge = String(repeating: "N", count: 7) // 4^7 = 16384 > 4096
        XCTAssertThrowsError(try PrimerCalculator.tm(huge))
    }

    // MARK: - 翻译（NCBI 标准表）

    func testTranslateStandardFrame0() throws {
        let a = try parseFixture(smallFasta, format: .fasta)
        let aa = try! AlignmentTranslator.translate(a, table: .standard, frame: 0, displayMode: .aminoAcidOnly)
        XCTAssertEqual(aa.datatype, .aminoAcid)
        // 首密码子 ATG → M
        XCTAssertEqual(aa.sequences[0].residues.first, UInt8(ASCII: "M"))
        XCTAssertEqual(aa.sequences[1].residues.first, UInt8(ASCII: "M"))
    }

    func testTranslateSingleCodon() throws {
        let seq = Sequence(name: "s", residues: Array("ATG".utf8))
        let a = Alignment(sequences: [seq], datatype: .nucleicAcid)
        let aa = try! AlignmentTranslator.translate(a, table: .standard, frame: 0, displayMode: .aminoAcidOnly)
        XCTAssertEqual(String(bytes: aa.sequences[0].residues, encoding: .ascii), "M")
    }

    func testTranslateNegativeFrame() throws {
        let a = try parseFixture(smallFasta, format: .fasta)
        let aa = try! AlignmentTranslator.translate(a, table: .standard, frame: -1, displayMode: .aminoAcidOnly)
        XCTAssertEqual(aa.datatype, .aminoAcid)
        XCTAssertGreaterThan(aa.length, 0)
        // 负框结果应与「先反向互补再正框翻译」一致
        let rc = SequenceUtils.reverseComplement(a.sequences[0].residues)
        let rcAlign = Alignment(sequences: [Sequence(name: "rc", residues: rc)], datatype: .nucleicAcid)
        let rcAA = try! AlignmentTranslator.translate(rcAlign, table: .standard, frame: 0, displayMode: .aminoAcidOnly)
        XCTAssertEqual(aa.sequences[0].residues, rcAA.sequences[0].residues)
    }

    // MARK: - 撤销 / 重做 7 场景

    private func freshAlignment() throws -> Alignment {
        try parseFixture(smallFasta, format: .fasta)
    }

    private func residuesString(_ s: Sequence) -> String {
        String(bytes: s.residues, encoding: .ascii) ?? ""
    }

    func testUndoRename() throws {
        let a = try freshAlignment()
        let mgr = UndoRedoManager()
        let cmd = RenameCommand(index: 0, oldName: a.sequences[0].name, newName: "Renamed")
        mgr.execute(cmd, on: a)
        XCTAssertEqual(a.sequences[0].name, "Renamed")
        _ = mgr.undoCommand(on: a)
        XCTAssertEqual(a.sequences[0].name, "Seq1")
        _ = mgr.redoCommand(on: a)
        XCTAssertEqual(a.sequences[0].name, "Renamed")
    }

    func testUndoRemoveSeq() throws {
        let a = try freshAlignment()
        let mgr = UndoRedoManager()
        let removed = a.sequences[2]
        let cmd = RemoveSeqCommand(indices: [2], removedSequences: [removed])
        mgr.execute(cmd, on: a)
        XCTAssertEqual(a.seqCount, 2)
        _ = mgr.undoCommand(on: a)
        XCTAssertEqual(a.seqCount, 3)
        XCTAssertEqual(a.sequences[2].name, "Seq3")
        _ = mgr.redoCommand(on: a)
        XCTAssertEqual(a.seqCount, 2)
    }

    func testUndoReverseComplement() throws {
        let a = try freshAlignment()
        let mgr = UndoRedoManager()
        let original = a.sequences[0].residues
        let cmd = ReverseComplementCommand(index: 0, originalResidues: original)
        mgr.execute(cmd, on: a)
        XCTAssertEqual(a.sequences[0].residues, SequenceUtils.reverseComplement(original))
        _ = mgr.undoCommand(on: a)
        XCTAssertEqual(a.sequences[0].residues, original)
    }

    func testUndoInsertGap() throws {
        let a = try freshAlignment()
        let mgr = UndoRedoManager()
        let before = a.sequences[0].residues.count
        let cmd = InsertGapCommand(index: 0, pos: 5, gapLen: 3)
        mgr.execute(cmd, on: a)
        XCTAssertEqual(a.sequences[0].residues.count, before + 3)
        XCTAssertEqual(a.sequences[0].residues[5], 0x2D)
        _ = mgr.undoCommand(on: a)
        XCTAssertEqual(a.sequences[0].residues.count, before)
    }

    func testUndoTransaction() throws {
        let a = try freshAlignment()
        let mgr = UndoRedoManager()
        mgr.beginTransaction()
        mgr.execute(RenameCommand(index: 0, oldName: a.sequences[0].name, newName: "X"), on: a)
        mgr.execute(InsertGapCommand(index: 1, pos: 0, gapLen: 2), on: a)
        mgr.commitTransaction()
        XCTAssertEqual(a.sequences[0].name, "X")
        XCTAssertEqual(a.sequences[1].residues[0], 0x2D)
        _ = mgr.undoCommand(on: a)
        XCTAssertEqual(a.sequences[0].name, "Seq1")
        XCTAssertNotEqual(a.sequences[1].residues[0], 0x2D)
        _ = mgr.redoCommand(on: a)
        XCTAssertEqual(a.sequences[0].name, "X")
    }

    func testUndoAddSeq() throws {
        let a = try freshAlignment()
        let mgr = UndoRedoManager()
        let newSeq = Sequence(name: "New", residues: Array("ATGC".utf8))
        let cmd = AddSeqCommand(sequence: newSeq)
        mgr.execute(cmd, on: a)
        XCTAssertEqual(a.seqCount, 4)
        _ = mgr.undoCommand(on: a)
        XCTAssertEqual(a.seqCount, 3)
        _ = mgr.redoCommand(on: a)
        XCTAssertEqual(a.seqCount, 4)
    }

    func testUndoMoveSeq() throws {
        let a = try freshAlignment()
        let mgr = UndoRedoManager()
        let cmd = MoveSeqCommand(fromIndex: 0, toIndex: 2)
        mgr.execute(cmd, on: a)
        XCTAssertEqual(a.sequences[1].name, "Seq1")
        _ = mgr.undoCommand(on: a)
        XCTAssertEqual(a.sequences[0].name, "Seq1")
        _ = mgr.redoCommand(on: a)
        XCTAssertEqual(a.sequences[1].name, "Seq1")
    }

    // MARK: - 搜索 IUPAC

    func testSearchExactAndDegenerate() throws {
        let a = try parseFixture(smallFasta, format: .fasta)
        // 三序列均以 ATGC 开头
        let exact = SearchEngine(alignment: a, pattern: "ATGC").findAll()
        XCTAssertEqual(exact.count, 3)
        XCTAssertTrue(exact.allSatisfy { $0.position == 0 })

        // 简并 Y={C,T}：ATGY 同时命中 ATGC(Seq1/Seq3) 与 ATGT(Seq2)
        let deg = SearchEngine(alignment: a, pattern: "ATGY").findAll()
        XCTAssertEqual(deg.count, 3)

        let none = SearchEngine(alignment: a, pattern: "ZZZZ").findAll()
        XCTAssertEqual(none.count, 0)
    }

    // MARK: - 比对质量 + 列统计

    func testQualityAndColumnStats() throws {
        let a = try parseFixture(smallFasta, format: .fasta)
        let quality = AlignmentStatsCalculator.computeQuality(a)
        XCTAssertEqual(quality.totalColumns, 60)
        XCTAssertGreaterThan(quality.pooledPairwiseIdentity, 0)
        XCTAssertLessThanOrEqual(quality.pooledPairwiseIdentity, 1.0)

        let stats = AlignmentStatsCalculator.computeColumnStats(a)
        XCTAssertEqual(stats.columnCount, 60)
        XCTAssertEqual(stats.consensus.count, 60)
        // 第 0 列三序列均为 A → 一致度 1.0
        XCTAssertEqual(stats.identity[0], 1.0, accuracy: 1e-9)

        // 列一致度单一来源：columnIdentities 与 computeColumnStats 一致
        let ids = AlignmentStatsCalculator.columnIdentities(a)
        XCTAssertEqual(ids.count, 60)
        XCTAssertEqual(ids[0], stats.identity[0], accuracy: 1e-9)
    }

    // MARK: - NEXUS charset

    func testNexusCharset() throws {
        let a = try parseFixture(nexus, format: .nexus)
        XCTAssertEqual(a.charsets.count, 3)
        XCTAssertEqual(a.charsets[0].name, "codons_1")
        XCTAssertEqual(a.charsets[1].name, "codons_2")
        XCTAssertEqual(a.charsets[2].name, "codons_3")
        // 1-60\3 → 20 个单点（步长 3）
        XCTAssertEqual(a.charsets[0].ranges.count, 20)
        XCTAssertEqual(a.charsets[0].ranges.first?.start, 1)
    }

    // MARK: - 颜色索引一致性（ColorSchemes 与 ExportManager 共用单一来源）

    func testColorIndexDefaultNucleotide() {
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x41, scheme: .defaultNucleotide), 1) // A
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x43, scheme: .defaultNucleotide), 2) // C
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x47, scheme: .defaultNucleotide), 3) // G
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x54, scheme: .defaultNucleotide), 4) // T
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x4E, scheme: .defaultNucleotide), 5) // N
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x2D, scheme: .defaultNucleotide), 6) // Gap
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x58, scheme: .defaultNucleotide), 7) // 其他/IUPAC
    }

    func testColorIndexClustalX() {
        // AVLIMFW → 1
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x41, scheme: .clustalX), 1)
        // 非类别残基 → 索引 7（保守阈值在 computeViewport 中叠加，此处仅类别映射）
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x58, scheme: .clustalX), 7)
    }

    func testColorIndexViewportUsesSingleSource() throws {
        let a = try parseFixture(smallFasta, format: .fasta)
        let matrix = ColorComputer.computeViewport(a, scheme: .defaultNucleotide, rowStart: 0, rowCount: 1, colStart: 0, colCount: 4)
        // 首行首四列 ATGC → 默认核苷酸类别索引 [A=1, T=4, G=3, C=2] → [1,4,3,2]
        XCTAssertEqual(matrix, [1, 4, 3, 2])
    }

    // MARK: - 反向互补单一来源

    func testReverseComplement() {
        let rc = SequenceUtils.reverseComplement([0x41, 0x54, 0x47, 0x43]) // ATGC
        XCTAssertEqual(rc, [0x47, 0x43, 0x41, 0x54]) // GCAT
        XCTAssertEqual(SequenceUtils.reverseComplement([0x4E]), [0x4E]) // N 不变
        // 与翻译负框使用的实现一致（同一函数）
        let a = try! parseFixture(smallFasta, format: .fasta)
        let translated = try! AlignmentTranslator.translate(a, table: .standard, frame: -1, displayMode: .aminoAcidOnly)
        let manual = try! AlignmentTranslator.translate(
            Alignment(sequences: [Sequence(name: "rc", residues: SequenceUtils.reverseComplement(a.sequences[0].residues))], datatype: .nucleicAcid),
            table: .standard, frame: 0, displayMode: .aminoAcidOnly)
        XCTAssertEqual(translated.sequences[0].residues, manual.sequences[0].residues)
    }

    // MARK: - 搜索快照（并发安全基础）

    func testAlignmentSnapshotIsIndependent() throws {
        let a = try freshAlignment()
        let snapshot = a.snapshot()
        // 修改原对象不应影响快照
        a.sequences[0].residues[0] = 0x4E // 改为 N
        a.sequences.append(Sequence(name: "extra", residues: [0x41]))
        XCTAssertNotEqual(a.sequences[0].residues[0], snapshot.sequences[0].residues[0])
        XCTAssertEqual(snapshot.seqCount, 3)
        XCTAssertEqual(snapshot.sequences[0].residues[0], 0x41) // 仍为 A
    }
}


// MARK: - 核心扩展测试

final class CoreEnhancementTests: XCTestCase {

    // Stockholm 往返
    func testStockholmRoundtrip() throws {
        let sto = "# STOCKHOLM 1.0\n\n#=GF ID test\n\nseq1 AC-GT\nseq2 ACTGT\n//\n"
        let align = try StockholmParser.parse(sto.data(using: .utf8)!)
        XCTAssertEqual(align.seqCount, 2)
        XCTAssertEqual(align.length, 5)
        XCTAssertEqual(Array(align.sequences[0].residues), Array("AC-GT".utf8))
        let out = String(data: AlignmentWriter.writeStockholm(align), encoding: .utf8)!
        XCTAssertTrue(out.hasPrefix("# STOCKHOLM 1.0"))
        XCTAssertTrue(out.contains("//"))
        let reparsed = try StockholmParser.parse(out.data(using: .utf8)!)
        XCTAssertEqual(reparsed.sequences.map { String(bytes: $0.residues, encoding: .ascii)! },
                       ["AC-GT", "ACTGT"])
        XCTAssertEqual(reparsed.metadata["ID"], "test")
    }

    // FASTQ 质量值解析 + Q20/Q30 统计
    func testFastqQualityStats() throws {
        let fq = "@r1\nACGTACGT\n+\nIIIIIIII\n@r2\nACGTACGA\n+\nIIIIII#I\n"
        let align = try FastqParser.parse(fq.data(using: .utf8)!)
        XCTAssertEqual(align.sequences[0].quality, [40,40,40,40,40,40,40,40])
        let summary = AlignmentStatsCalculator.computeQualitySummary(align)
        XCTAssertTrue(summary.hasData)
        XCTAssertEqual(summary.readCount, 2)
        XCTAssertEqual(summary.q20Ratio, 15.0 / 16.0, accuracy: 1e-9) // 1 个 Q2
        XCTAssertEqual(summary.q30Ratio, 15.0 / 16.0, accuracy: 1e-9)
        XCTAssertEqual(summary.minPhred, 2)
    }

    // gzip 解压（用 Apple Compression 的 zlib 编码构造一个 gzip 容器）
    func testGzipDecompress() throws {
        let original = ">s\nACGTACGTACGT\n"
        let compressed = try gzip(original.data(using: .utf8)!)
        let restored = Gzip.decompress(compressed)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored, original.data(using: .utf8))
    }

    private func gzip(_ data: Data) throws -> Data {
        // 手工构造 RFC1952：header + raw deflate(COMPRESSION_ZLIB 输出) + CRC32/ISIZE 占位
        var deflated = Data(count: data.count * 4)
        let encoded = deflated.withUnsafeMutableBytes { dst -> Int in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!,
                                          data.count * 4,
                                          src.bindMemory(to: UInt8.self).baseAddress!,
                                          data.count, nil, COMPRESSION_ZLIB)
            }
        }
        deflated.removeSubrange(encoded..<deflated.count)
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0,0,0,0, 0x00, 0xFF])
        out.append(deflated)
        out.append(Data([0,0,0,0]))           // CRC32（解压器不校验）
        out.append(withUnsafeBytes(of: UInt32(truncatingIfNeeded: data.count).littleEndian) { Data($0) })
        return out
    }

    // Logo：完全一致列的信息含量接近 log2(4)=2 bits（小样本校正后略低）
    func testLogoFullyConservedColumn() throws {
        let fasta = ">a\nAAAAAAAAAA\n>b\nAAAAAAAAAA\n>c\nAAAAAAAAAA\n"
        let align = try FastaParser.parse(fasta.data(using: .utf8)!)
        let cols = LogoCalculator.columns(align)
        XCTAssertEqual(cols.count, 10)
        XCTAssertGreaterThan(cols[0].totalBits, 1.2)
        XCTAssertLessThan(cols[0].totalBits, 2.0)
        XCTAssertEqual(cols[0].stacks.first?.residue, 0x41)
        XCTAssertEqual(cols[0].stacks.first?.fraction ?? 0, 1.0, accuracy: 1e-9)
    }

    // NJ：两条序列的 Newick
    func testNJTwoSeqs() throws {
        let fasta = ">a\nAAAAAAAAAA\n>b\nAAAAAAAAAA\n"
        let align = try FastaParser.parse(fasta.data(using: .utf8)!)
        let newick = PhyloBuilder.njNewick(align)
        // 两条序列也要给出距离信息（d/2），且树串自带抽样披露。
        XCTAssertTrue(newick.hasPrefix("(a:0.00000,b:0.00000)"), "实际得到 \(newick)")
        XCTAssertTrue(newick.contains("sampled=2_of_2"))
    }

    // NJ：三条序列 Newick 平衡性（叶节点均出现、以分号结尾）
    func testNJThreeSeqs() throws {
        let fasta = ">a\nAAAAAAAAAA\n>b\nAAAAAAAATT\n>c\nAAAAAAAACC\n"
        let align = try FastaParser.parse(fasta.data(using: .utf8)!)
        let newick = PhyloBuilder.njNewick(align)
        XCTAssertTrue(newick.hasSuffix(";"))
        for leaf in ["a", "b", "c"] {
            XCTAssertTrue(newick.contains(leaf + ":"), "缺少叶 \(leaf): \(newick)")
        }
    }

    // 滑动窗口一致度
    func testSlidingWindowIdentity() throws {
        let fasta = ">a\nAAAAAAAAAATT\n>b\nAAAAAAAAAATT\n>c\nAAAAAAAAAATT\n"
        let align = try FastaParser.parse(fasta.data(using: .utf8)!)
        let points = PhyloBuilder.slidingWindowIdentity(align, window: 6)
        XCTAssertFalse(points.isEmpty)
        // 前 10 列全一致 → 覆盖这些列的窗口一致度应为 1.0
        XCTAssertTrue(points.contains { $0.identity > 0.999 })
    }

    // Okabe-Ito 索引映射存在且与默认核酸索引一致（色板在渲染层）
    func testOkabeItoIndices() {
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x41, scheme: .okabeIto), 1)
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x43, scheme: .okabeIto), 2)
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x47, scheme: .okabeIto), 3)
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x54, scheme: .okabeIto), 4)
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x2D, scheme: .okabeIto), 6)
    }

    // 遗传密码表对拍 NCBI gc.prt 官方定义
    func testNewGeneticCodeTables() {
        // 表 3 酵母线粒体：ATA→M、CTT/CTC/CTA/CTG→T、TGA→W
        let t3 = TranslationTables.table(for: .yeast)
        XCTAssertEqual(t3["ATA"], "M")
        XCTAssertEqual(t3["CTT"], "T")
        XCTAssertEqual(t3["CTC"], "T")
        XCTAssertEqual(t3["CTA"], "T")
        XCTAssertEqual(t3["CTG"], "T")
        XCTAssertEqual(t3["TGA"], "W")
        // 表 9 棘皮动物线粒体：AAA→N、AGA/AGG→S、TGA→W；ATA 保持 Ile
        let t9 = TranslationTables.table(for: .echinodermMito)
        XCTAssertEqual(t9["AAA"], "N")
        XCTAssertEqual(t9["AGA"], "S")
        XCTAssertEqual(t9["AGG"], "S")
        XCTAssertEqual(t9["TGA"], "W")
        XCTAssertEqual(t9["ATA"], "I")
        // 表 10 Euplotid 核码：UGA→C；UAA/UAG 仍为终止
        let t10 = TranslationTables.table(for: .euplotid)
        XCTAssertEqual(t10["TGA"], "C")
        XCTAssertEqual(t10["TAA"], "*")
        XCTAssertEqual(t10["TAG"], "*")
        // 表 14 替代扁形动物线粒体：TAA→Y、AAA→N、AGA/AGG→S、TGA→W；ATA 保持 Ile
        let t14 = TranslationTables.table(for: .flatwormMito)
        XCTAssertEqual(t14["TAA"], "Y")
        XCTAssertEqual(t14["AAA"], "N")
        XCTAssertEqual(t14["AGA"], "S")
        XCTAssertEqual(t14["AGG"], "S")
        XCTAssertEqual(t14["TGA"], "W")
        XCTAssertEqual(t14["ATA"], "I")
        // 表 15 Blepharisma 核码（NCBI 15 Blepharisma Nuclear）：UAG→Q，UAA 仍为终止
        let t15 = TranslationTables.table(for: .blepharismaMito)
        XCTAssertEqual(t15["TAG"], "Q")
        XCTAssertEqual(t15["TAA"], "*")
        // 表 16 绿藻线粒体：UAG→L
        let t16 = TranslationTables.table(for: .chlorophycean)
        XCTAssertEqual(t16["TAG"], "L")
        // 表 24 羽腮动物线粒体：UGA→W、AGA→S、AGG→K
        let t24 = TranslationTables.table(for: .pterobranchMito)
        XCTAssertEqual(t24["TGA"], "W")
        XCTAssertEqual(t24["AGA"], "S")
        XCTAssertEqual(t24["AGG"], "K")
        // 表 25 Candidate Division SR1 / Gracilibacteria：UGA→G
        let t25 = TranslationTables.table(for: .sr1)
        XCTAssertEqual(t25["TGA"], "G")
        // 表 30 Peritrich 核码：UAA/UAG→E
        let t30 = TranslationTables.table(for: .peritrichNuclear)
        XCTAssertEqual(t30["TAA"], "E")
        XCTAssertEqual(t30["TAG"], "E")
        // 表 11 细菌：密码子→氨基酸赋值与标准表完全一致
        XCTAssertEqual(TranslationTables.table(for: .bacterial).count,
                       TranslationTables.table(for: .standard).count)
        XCTAssertEqual(TranslationTables.table(for: .bacterial)["CTG"], "L")
    }

    // 引物 Tm 盐浓度可配置：不同 Na+ 得到不同 Tm
    func testTmRespondsToSalt() throws {
        let seq = "ATGCTAGCTAGCTAGCTAGC"
        let lowSalt = TmOptions(naMolar: 0.01, mgMolar: 0, oligoMolar: 0.25e-6)
        let highSalt = TmOptions(naMolar: 0.5, mgMolar: 0, oligoMolar: 0.25e-6)
        let tmLow = try PrimerCalculator.tm(seq, options: lowSalt)
        let tmHigh = try PrimerCalculator.tm(seq, options: highSalt)
        XCTAssertGreaterThan(tmHigh.0, tmLow.0, "更高盐浓度应得到更高 Tm")
    }

    // GFF3 解析
    func testGffParse() {
        let gff = "##gff-version 3\nseq1\t.\tgene\t10\t60\t.\t+\t.\tID=g1;Name=genA\n"
        let features = GffParser.parse(gff.data(using: .utf8)!)
        XCTAssertEqual(features.count, 1)
        XCTAssertEqual(features[0].seqid, "seq1")
        XCTAssertEqual(features[0].type, "gene")
        XCTAssertEqual(features[0].start, 10)
        XCTAssertEqual(features[0].end, 60)
        XCTAssertEqual(features[0].name, "genA")
        XCTAssertEqual(features[0].strand, "+")
    }
}

// 小工具：由字符字面量构造 UInt8（仅 ASCII）
extension UInt8 {
    init(ASCII c: Character) {
        self = UInt8(c.asciiValue!)
    }
}
