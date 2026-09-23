//  EdgeCaseTests.swift
//  SeqAlignMac — 边界输入与格式变体测试
//
//  覆盖：
//  - PHYLIP 顺序格式换行续行
//  - NEXUS interleaved MATRIX 聚合
//  - 正则搜索：字面大写化不反转转义语义、validateRegex 与引擎一致
//  - 引物：简并度溢出饱和、非法字符报错、盐浓度校验
//  - 写出器：NEXUS 名称引用、PHYLIP 名称唯一性、GCG 校验和、参差序列防护
//  - KMP 搜索 O(n) 全量扫描 + 重叠命中语义
//  - zh/en 本地化对照（空串/缺 key 防护）的目标适用性说明
//  - UndoRedo：InsertGap 行尾钳制撤销、事务嵌套、内存上限

import Foundation
import XCTest
@testable import SeqAlignCore

final class EdgeCaseTests: XCTestCase {

    // MARK: - PHYLIP 顺序格式（换行续行）

    func testPhylipSequentialWrappedLines() throws {
        // 经典 sequential：每条序列按 60/行换行续写，续行顶格不带名称
        let seq1 = String(repeating: "ACGT", count: 20)  // 80 bp
        let seq2 = String(repeating: "TTTT", count: 20)
        let text = """
        2 80
        \(seq1.prefix(60))
        \(seq1.dropFirst(60))
        \(seq2.prefix(60))
        \(seq2.dropFirst(60))
        """
        let alignment = try PhylipParser.parse(Data(text.utf8))
        XCTAssertEqual(alignment.seqCount, 2)
        XCTAssertEqual(alignment.length, 80)
        XCTAssertEqual(String(decoding: alignment.sequences[0].residues, as: UTF8.self), seq1)
        XCTAssertEqual(String(decoding: alignment.sequences[1].residues, as: UTF8.self), seq2)
    }

    func testPhylipSequentialStrict10Wrapped() throws {
        // strict10：续行顶格（第 10 列是残基而非空格），不得被误读为新 taxon 名称
        let first70 = String(repeating: "ACGT", count: 20).prefix(70)
        let last10 = String(repeating: "G", count: 10)
        let pad = String(repeating: " ", count: 6)  // 名称 Seq1/Seq2 填充到 10 列
        let text = """
        2 80
        Seq1\(pad)\(first70)
        \(last10)
        Seq2\(pad)\(first70.replacingOccurrences(of: "A", with: "T"))
        \(last10)
        """
        let alignment = try PhylipParser.parse(Data(text.utf8))
        XCTAssertEqual(alignment.seqCount, 2)
        XCTAssertEqual(alignment.sequences[0].name, "Seq1")
        XCTAssertEqual(alignment.sequences[1].name, "Seq2")
        XCTAssertEqual(alignment.length, 80)
        XCTAssertTrue(alignment.sequences[0].residues.allSatisfy { $0 != 0x2D },
                      "顺序格式续行不应被静默补成 gap")
    }

    // MARK: - NEXUS interleaved

    func testNexusInterleavedMatrixAggregation() throws {
        let text = """
        #NEXUS
        BEGIN DATA;
        DIMENSIONS NTAX=2 NCHAR=10;
        FORMAT DATATYPE=DNA GAP=- MISSING=?;
        MATRIX
        Seq1 ACGTACGT
        Seq2 ACGTACGA

        Seq1 AC
        Seq2 AC
        ;
        END;
        """
        let alignment = try NexusParser.parse(Data(text.utf8))
        XCTAssertEqual(alignment.seqCount, 2, "interleaved 块中同名 taxon 应聚合为一条序列")
        XCTAssertEqual(alignment.sequences[0].name, "Seq1")
        XCTAssertEqual(alignment.sequences[0].residues.count, 10, "interleaved 两块应拼接为 10 残基")
    }

    // MARK: - 正则搜索

    func testRegexEscapedClassNotReversedByUppercasing() throws {
        // \d+ 大写化后不得变成 \D+（数字→非数字的语义反转）
        XCTAssertEqual(SearchEngine.uppercasingLiterals(#"acg\d+ tN"#), #"ACG\d+ TN"#)
        XCTAssertEqual(SearchEngine.uppercasingLiterals(#"[ac]gt\b"#), #"[ac]GT\b"#)
    }

    func testRegexContentSearchFindsDigits() throws {
        let fasta = """
        >S1
        AAAA12345AAAA
        """
        let alignment = try FastaParser.parse(Data(fasta.utf8))
        let engine = SearchEngine(alignment: alignment, pattern: #"\d+"#, scope: .content, useRegex: true)
        let hits = engine.findAll()
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.position, 4)
        XCTAssertEqual(hits.first?.matchLen, 5)
    }

    func testValidateRegexMatchesEngine() throws {
        // 引擎侧编译失败的模式，预检也必须失败（两者走同一路径）
        XCTAssertTrue(SearchEngine.validateRegex("A[CG]T", scope: .content))
        XCTAssertFalse(SearchEngine.validateRegex("A[CG", scope: .content))
        XCTAssertFalse(SearchEngine.validateRegex("(?P<>x", scope: .content))
    }

    // MARK: - KMP 全量扫描 + 重叠命中

    func testFindAllOverlappingMatchesOofN() throws {
        let fasta = """
        >polyA
        AAAAAAAAAA
        """
        let alignment = try FastaParser.parse(Data(fasta.utf8))
        let engine = SearchEngine(alignment: alignment, pattern: "AA", scope: .content, useRegex: false)
        let hits = engine.findAll()
        XCTAssertEqual(hits.count, 9, "重叠命中应逐位输出")
        for (i, hit) in hits.enumerated() {
            XCTAssertEqual(hit.position, i)
        }
    }

    // MARK: - 引物

    func testDegeneracyOverflowSaturates() {
        // 16 连 N = 4^16 > UInt32.max
        let result = IUPACCode.degeneracy(String(repeating: "N", count: 16))
        // min 是"每歧义位只有一种真残基"的下界，max 才是 4^16 的最坏变体数。
        // 溢出保护由 max 的饱和语义承担。
        XCTAssertEqual(result.max, .max)
        let small = IUPACCode.degeneracy("ACGT")
        XCTAssertEqual(small.min, 1)
        XCTAssertEqual(small.max, 1)
    }

    func testNNTmRejectsUnsupportedCharacters() {
        XCTAssertThrowsError(try PrimerCalculator.tm("ACGU", method: .nearestNeighbor))
        XCTAssertThrowsError(try PrimerCalculator.tm("AC-G", method: .nearestNeighbor))
        XCTAssertThrowsError(try PrimerCalculator.tm("A", method: .nearestNeighbor))
    }

    func testNNTmRejectsInvalidSalt() {
        var options = TmOptions.default
        options.naMolar = -1
        XCTAssertThrowsError(try PrimerCalculator.tm("ACGTACGT", method: .nearestNeighbor, options: options))
    }

    // MARK: - 写出器

    func testNexusQuotesNamesWithSpecialCharacters() throws {
        let alignment = Alignment(sequences: [
            Sequence(name: "seq one", residues: Array("ACGT".utf8)),
        ], datatype: .nucleicAcid)
        let nexus = String(decoding: AlignmentWriter.writeNexus(alignment), as: UTF8.self)
        let lines = nexus.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains { $0.contains("TAXLABELS") && $0.contains("'seq one'") }, "含空格的名称应加引号")
        XCTAssertTrue(lines.contains { $0.contains("'seq one'") && $0.hasSuffix("ACGT") }, "MATRIX 行名应与 TAXLABELS 一致")
    }

    func testPhylipStrict10NamesUnique() throws {
        let prefix = String(repeating: "ABCDEF", count: 2)  // 12 字符，截断到 10 后前缀相同
        let alignment = Alignment(sequences: [
            Sequence(name: prefix + "1", residues: Array("ACGT".utf8)),
            Sequence(name: prefix + "2", residues: Array("ACGT".utf8)),
        ], datatype: .nucleicAcid)
        let phylip = String(decoding: AlignmentWriter.writePhylip(alignment, variant: .strict10Char), as: UTF8.self)
        let names = phylip.split(separator: "\n").dropFirst().map { String($0.prefix(10)) }
        XCTAssertEqual(Set(names).count, names.count, "截断后名称必须唯一")
    }

    func testWritersHandleRaggedSequences() throws {
        // 参差序列（未 pad）写出不得构造非法区间
        let alignment = Alignment(sequences: [
            Sequence(name: "long", residues: Array(repeating: UInt8(0x41), count: 130)),
            Sequence(name: "short", residues: Array(repeating: UInt8(0x43), count: 10)),
        ], datatype: .nucleicAcid)
        XCTAssertNoThrow(AlignmentWriter.writePhylip(alignment, variant: .interleaved))
        XCTAssertNoThrow(AlignmentWriter.writeClustal(alignment))
        XCTAssertNoThrow(AlignmentWriter.writeMsf(alignment))
        XCTAssertNoThrow(AlignmentWriter.writeStockholm(alignment))
    }

    func testMsfChecksumIsGcgValue() throws {
        // GCG 校验和：Σ (i % 57 + 1) × ASCII，mod 10000
        let residues = Array("ACGT".utf8)
        let expected = (((0 % 57) + 1) * 65 + ((1 % 57) + 1) * 67 + ((2 % 57) + 1) * 71 + ((3 % 57) + 1) * 84) % 10000
        let alignment = Alignment(sequences: [Sequence(name: "s", residues: residues)], datatype: .nucleicAcid)
        let msf = String(decoding: AlignmentWriter.writeMsf(alignment), as: UTF8.self)
        let headerLine = msf.split(separator: "\n").first { $0.contains("MSF:") } ?? ""
        XCTAssertTrue(headerLine.contains("MSF: \(expected)"), "MSF: 字段应为 GCG 校验和，实际: \(headerLine)")
    }

    // MARK: - 核心语义

    func testGcContentExcludesAmbiguousBases() {
        // 1 GC / 2 可判定碱基 = 50%；N 不计入分母
        let residues = Array("AGN".utf8)
        XCTAssertEqual(SequenceUtils.gcContent(residues), 0.5, accuracy: 1e-9)
    }

    func testMutationTypeGapVsGapNotMatch() {
        XCTAssertEqual(SequenceUtils.mutationType(0x2D, 0x2D), -1)
        XCTAssertEqual(SequenceUtils.mutationType(0x4E, 0x4E), -1)  // N-vs-N
        XCTAssertEqual(SequenceUtils.mutationType(0x41, 0x41), 0)   // A-vs-A 仍为匹配
    }

    func testColumnStatsExcludeAmbiguousFromVariation() throws {
        // N-vs-A 列不应被计为可变位点
        let alignment = Alignment(sequences: [
            Sequence(name: "s1", residues: Array("NAAA".utf8)),
            Sequence(name: "s2", residues: Array("AAAA".utf8)),
        ], datatype: .nucleicAcid)
        let q = AlignmentStatsCalculator.computeQuality(alignment)
        XCTAssertEqual(q.variableSites, 0)
    }

    // MARK: - 撤销/重做

    func testInsertGapUndoAtClampedPosition() {
        // 行短于 pos 时插入钳制到行尾：撤销必须删除同样位置
        let alignment = Alignment(sequences: [
            Sequence(name: "s1", residues: Array("ACGT".utf8)),
        ], datatype: .nucleicAcid)
        let cmd = InsertGapCommand(index: 0, pos: 100, gapLen: 2)
        cmd.execute(on: alignment)
        XCTAssertEqual(alignment.sequences[0].residues.count, 6)
        cmd.undo(on: alignment)
        XCTAssertEqual(alignment.sequences[0].residues, Array("ACGT".utf8), "撤销后必须还原原序列")
    }

    func testUndoRedoStackMemoryCap() {
        // 快照型命令应计入内存上限：500 条 × 10000 残基 ≈ 5MB/份 ×2，
        // 超过 256MB 上限前旧命令必须被淘汰
        let manager = UndoRedoManager()
        let big = Array(repeating: UInt8(0x41), count: 10_000)
        for i in 0..<60 {
            let seqs = (0..<250).map { j in Sequence(name: "s\(j)", residues: big) }
            let cmd = SortSequencesCommand(oldSequences: seqs, newSequences: seqs)
            manager.execute(cmd, on: Alignment(sequences: seqs, datatype: .nucleicAcid))
            XCTAssertEqual(manager.undoStackDepth, min(i + 1, 50))
        }
        XCTAssertLessThanOrEqual(manager.undoStackDepth, 50)
    }

    func testEmptyTransactionKeepsRedoStack() {
        let alignment = Alignment(sequences: [Sequence(name: "s", residues: Array("ACGT".utf8))], datatype: .nucleicAcid)
        let manager = UndoRedoManager()
        let cmd = RenameCommand(index: 0, oldName: "s", newName: "t")
        manager.execute(cmd, on: alignment)
        manager.undoCommand(on: alignment)
        XCTAssertEqual(manager.canRedo, true)
        // 空事务 commit 不应清掉重做历史
        manager.beginTransaction()
        manager.commitTransaction()
        XCTAssertEqual(manager.canRedo, true)
    }

    // MARK: - FASTQ / Clustal 变体

    func testFastqRejectsIllegalResidue() {
        let bad = """
        @s1
        ACGT5
        +
        IIIII
        """
        XCTAssertThrowsError(try FastqParser.parse(Data(bad.utf8)), "非法残基应报错而非静默丢弃")
    }

    func testClustalWithoutHeaderButValidBody() throws {
        // MAFFT clustal 输出无 CLUSTAL 头：正文布局正确时同样接受
        let text = """
        s1      ACGTACGT
        s2      ACGTACGA
        """
        let alignment = try ClustalParser.parse(Data(text.utf8))
        XCTAssertEqual(alignment.seqCount, 2)
    }

    // MARK: - FASTQ 写出保留质量值

    func testWriteFastqPreservesQualityRoundtrip() throws {
        let src = """
        @s1 first
        ACGT
        +
        IIHI
        """
        let parsed = try FastqParser.parse(Data(src.utf8))
        XCTAssertEqual(parsed.sequences[0].quality, [40, 40, 39, 40], "Phred+33：'I'=40、'H'=39")

        let out = AlignmentWriter.writeFastq(parsed)
        let reparsed = try FastqParser.parse(out)
        XCTAssertEqual(reparsed.sequences[0].residues, parsed.sequences[0].residues)
        XCTAssertEqual(reparsed.sequences[0].quality, parsed.sequences[0].quality, "往返后质量值不得丢失")
        XCTAssertEqual(reparsed.sequences[0].name, "s1")
    }

    // MARK: - Gzip 压缩/解压往返

    func testGzipCompressDecompressRoundtrip() throws {
        let payload = Data((0..<500).map { _ in "ACGTACGTACGTACGT\n" }.joined().utf8)
        guard let gz = Gzip.compress(payload) else { return XCTFail("compress 返回 nil") }
        XCTAssertEqual([gz[0], gz[1], gz[2]], [0x1F, 0x8B, 0x08], "应为 gzip 魔数头")
        guard let back = Gzip.decompress(gz) else { return XCTFail("decompress 返回 nil") }
        XCTAssertEqual(back, payload, "压缩→解压必须逐字节还原（校验 CRC/ISIZE/deflate 正确性）")
    }

    // MARK: - 共识模式 IUPAC / 严格 / 多数

    private func ntAlignment(_ rows: [String]) -> Alignment {
        Alignment(sequences: rows.enumerated().map { i, s in
            Sequence(name: "s\(i)", residues: Array(s.utf8))
        }, datatype: .nucleicAcid)
    }

    func testConsensusModeIUPAC() {
        // 列0=[A,G]→R，列1=[A,G]→R，列2=[G,C]→S
        let a = ntAlignment(["AAG", "GGC"])
        let iupac = AlignmentStatsCalculator.computeColumnStats(a, mode: .iupac).consensus
        XCTAssertEqual(String(decoding: iupac, as: UTF8.self), "RRS")
        // 四行单列覆盖全部四种碱基 → N
        let n = AlignmentStatsCalculator.computeColumnStats(ntAlignment(["A", "C", "G", "T"]), mode: .iupac).consensus
        XCTAssertEqual(n[0], UInt8(ascii: "N"))
    }

    func testConsensusModeStrictAndMajority() {
        let a = ntAlignment(["AA", "AT"])  // 列0 全 A；列1 A vs T
        let strict = AlignmentStatsCalculator.computeColumnStats(a, mode: .strict).consensus
        XCTAssertEqual(strict[0], UInt8(ascii: "A"), "全一致列输出该残基")
        XCTAssertEqual(strict[1], UInt8(ascii: "N"), "不一致列输出 N")

        let majority = AlignmentStatsCalculator.computeColumnStats(a, mode: .majority).consensus
        XCTAssertEqual(majority[1], UInt8(ascii: "A"), "多数规则并列取字节较小者（A < T）")
    }

    // MARK: - 翻译保留原名

    func testTranslateKeepsOriginalName() throws {
        let a = try FastaParser.parse(Data(">s1\nATGATG\n".utf8))
        let aa = try! AlignmentTranslator.translate(a, table: .standard, frame: 0, displayMode: .aminoAcidOnly)
        XCTAssertEqual(aa.sequences[0].name, "s1", "核心翻译不追加 _AA（后缀策略由调用方决定）")
    }

    // MARK: - InsertGap 脏列语义

    func testInsertGapDirtyColumnsForcesFullRecompute() {
        let cmd = InsertGapCommand(index: 0, pos: 1, gapLen: 2)
        XCTAssertNil(cmd.dirtyColumns, "插入空位会右移其后所有列，应返回 nil 走全量重算而非低估")
    }

    // 注：zh/en 本地化对称性检查依赖 `AppStrings`（位于 Localization.swift）。
    // 该文件 import SwiftUI/AppKit，被有意排除在纯领域 SeqAlignCore 目标之外，
    // 因此本测试目标无法、也不应引用它；该对称性校验由 App 目标承担。
}
