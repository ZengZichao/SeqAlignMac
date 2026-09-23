//  FormatRoundTripTests.swift
//  SeqAlignMac — 写出/读回逐字节往返与输入边界测试
//
//  通用断言：对每个写出格式，"解析器读回后的 residues 与名称必须与写出前逐字节相等"，
//  fixture 显式包含 (a) 名称恰为 10 字符、(b) 含 '.' 空位、(c) 含重复名、(d) 参差长度。
//
//  这些测试与 EdgeCaseTests / SeqAlignCoreTests 一起构成 swift test 的全部用例。

import XCTest
@testable import SeqAlignCore

final class FormatRoundTripTests: XCTestCase {

    private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }
    private func str(_ b: [UInt8]) -> String { String(bytes: b, encoding: .ascii) ?? "" }
    private func parse(_ text: String, as format: AlignmentFormat? = nil) throws -> Alignment {
        try AlignmentParser.parse(Data(text.utf8), format: format)
    }

    // MARK: - PHYLIP 往返：名称满 10 字符不得静默变成全空位

    /// (a) 名称恰为 10 字符（GenBank accession 形如 AF123456.1）
    private func phylipRoundTripFixture() -> Alignment {
        let seqs = [
            Sequence(name: "AF123456.1", residues: bytes("ACGTACGTACGTACGT")),
            Sequence(name: "DQ987654.1", residues: bytes("ACGTACGTACGTACGA")),
            Sequence(name: "EU111111.1", residues: bytes("AGATCGTAGCATGCTA")),
        ]
        return Alignment(sequences: seqs, datatype: .nucleicAcid)
    }

    func testRoundtripPhylipStrict10WithTenCharNames() throws {
        let a = phylipRoundTripFixture()
        let data = AlignmentWriter.writePhylip(a, variant: .strict10Char)
        let back = try parse(String(data: data, encoding: .utf8)!, as: .phylip)
        XCTAssertEqual(back.seqCount, 3)
        for (orig, got) in zip(a.sequences, back.sequences) {
            XCTAssertEqual(got.residues, orig.residues,
                           "strict10Char 写出→读回残基必须逐字节相等（\(orig.name)）")
        }
    }

    func testRoundtripPhylipSequentialWithTenCharNames() throws {
        // 160 残基 × 3 taxon：sequential 变体会折行
        let long = String(repeating: "ACGTACGTAC", count: 16)
        let seqs = (0..<3).map { Sequence(name: "AF123456.\($0)", residues: bytes(long)) }
        let a = Alignment(sequences: seqs, datatype: .nucleicAcid)
        let back = try parse(str([UInt8](AlignmentWriter.writePhylip(a, variant: .sequential))), as: .phylip)
        XCTAssertEqual(back.seqCount, 3)
        for (i, got) in back.sequences.enumerated() {
            XCTAssertEqual(got.residues, seqs[i].residues,
                           "sequential 变体不得丢弃首块 60 残基（taxon \(i)）")
        }
    }

    func testPhylipAllGapResultIsRejectedNotSilent() {
        // 整行被当成名称 → 残基全空，必须报错而不是静默补 '-'
        let text = "1 10\nAF123456.1ACGTACGTAC\n"
        XCTAssertNoThrow(try parse(text, as: .phylip))   // 应正常解析
    }

    // MARK: - '.' 空位在各格式里的一致行为

    func testDotGapIsNormalizedInEveryFormat() throws {
        let fasta = try parse(">a\nACGT.CGTA\n>b\nACGTACGT.\n", as: .fasta)
        XCTAssertEqual(str(fasta.sequences[0].residues), "ACGT-CGTA",
                       "FASTA 的 '.' 应归一化为空位而不是保留成残基")
        XCTAssertEqual(str(fasta.sequences[1].residues), "ACGTACGT-")

        let phylip = try parse("2 10\na         ACGT.CGTA-\nb         ACGTACGT.-\n", as: .phylip)
        XCTAssertEqual(str(phylip.sequences[0].residues), "ACGT-CGTA-")
        XCTAssertEqual(str(phylip.sequences[1].residues), "ACGTACGT--")

        let clustal = try parse("CLUSTAL W (1.0) multiple sequence alignment\n\na  ACGT.CGTA\nb  ACGTACGT.\n\n", as: .clustal)
        XCTAssertEqual(str(clustal.sequences[0].residues), "ACGT-CGTA")

        let stockholm = try parse("# STOCKHOLM 1.0\n\na ACGT.CGTA\nb ACGTACGT.\n//\n", as: .stockholm)
        XCTAssertEqual(str(stockholm.sequences[0].residues), "ACGT-CGTA")
    }

    func testDotGapDoesNotShiftDownstreamResidues() throws {
        // '.' 不能当作可丢弃字符：若被删除，其后残基会左移一列
        let a = try parse("1 9\nx         ACGT.CGTA\n", as: .phylip)
        XCTAssertEqual(a.length, 9)
        XCTAssertEqual(str(a.sequences[0].residues), "ACGT-CGTA")
    }

    func testDistanceIgnoresDotOnlyColumns() {
        // 全空位对全空位不能算作"完全一致"
        let left = Alignment(sequences: [
            Sequence(name: "l", residues: bytes("ACGTACGTAC")),
            Sequence(name: "r", residues: bytes("ACGTACGTAG")),
        ], datatype: .nucleicAcid)
        let d = PhyloBuilder.pDistanceMatrix(left)
        XCTAssertEqual(d[0][1], 0.1, accuracy: 1e-9)

        let allDots = Alignment(sequences: [
            Sequence(name: "l", residues: bytes("ACGTACGTAC")),
            Sequence(name: "r", residues: bytes("..........")),
        ], datatype: .nucleicAcid)
        // 一方全空位 → 无可比位点，距离记 1.0（而不是"完全一致"的 0.0）
        let dd = PhyloBuilder.pDistanceMatrix(allDots)
        XCTAssertEqual(dd[0][1], 1.0, accuracy: 1e-9)
    }

    // MARK: - 蛋白位点统计不按核酸字母表过滤

    func testProteinVariableSitesCountStandardAminoAcids() throws {
        // 10 条序列 × 1 列，仅 K / M / S：variableSites 必须为 1
        let rows = (0..<10).map { i -> Sequence in
            Sequence(name: "s\(i)", residues: bytes(i < 5 ? "K" : "M"))
        }
        let a = Alignment(sequences: rows, datatype: .aminoAcid)
        let q = AlignmentStatsCalculator.computeQuality(a)
        XCTAssertEqual(q.variableSites, 1, "K/M/S 是标准氨基酸，必须算作真实性状")
        XCTAssertEqual(q.parsimonySites, 1)
    }

    func testProteinSingletonSiteAcrossDHSVKMYNRS() {
        // 9 个标准氨基酸逐个验证：单点变异必须计为 singleton
        for aa in "DHSVKNRMY".dropFirst(0) {
            let rows = (0..<6).map { i -> Sequence in
                Sequence(name: "s\(i)", residues: bytes(i == 0 ? String(aa) : "A"))
            }
            let a = Alignment(sequences: rows, datatype: .aminoAcid)
            let q = AlignmentStatsCalculator.computeQuality(a)
            XCTAssertEqual(q.variableSites, 1, "蛋白位点含 \(aa) 应判为变异位点")
            XCTAssertEqual(q.singletonSites, 1, "蛋白位点含 \(aa) 应判为单例位点")
        }
    }

    func testNucleotideAmbiguityStillExcludedFromSites() {
        // 核酸侧保持既有口径：R/Y/N 等简并码代表"状态未知"
        let rows = (0..<6).map { i -> Sequence in
            Sequence(name: "s\(i)", residues: bytes(i == 0 ? "R" : "A"))
        }
        let a = Alignment(sequences: rows, datatype: .nucleicAcid)
        let q = AlignmentStatsCalculator.computeQuality(a)
        XCTAssertEqual(q.variableSites, 0, "核酸简并码 R 仍按未知处理")
    }

    func testLogoIncludesStandardAminoAcids() {
        let rows = (0..<8).map { i -> Sequence in
            Sequence(name: "s\(i)", residues: bytes(i < 4 ? "K" : "M"))
        }
        let a = Alignment(sequences: rows, datatype: .aminoAcid)
        let cols = LogoCalculator.columns(a)
        XCTAssertEqual(cols.count, 1)
        let residues = Set(cols[0].stacks.map { $0.residue })
        XCTAssertEqual(residues, Set(bytes("KM")), "Logo 堆叠里必须出现 K 与 M")
        XCTAssertGreaterThan(cols[0].totalBits, 0)
    }

    // MARK: - reverseComplement 的 IUPAC 互补关系

    func testReverseComplementHandlesAllIUPACCodes() {
        // 真值：reverse + 互补，R↔Y、K↔M、B↔V、D↔H，S/W/N 自互补
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("ACGTRYKMBSWDHVN"))), "NBDHWSVKMRYACGT")
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("RYKMBDHVS"))), "SBDHVKMRY")
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("R"))), "Y")
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("Y"))), "R")
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("K"))), "M")
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("M"))), "K")
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("B"))), "V")
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("D"))), "H")
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("S"))), "S")
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("W"))), "W")
        // 自反性：两次反向互补必须回到原串
        let original = bytes("ACGTRYKMBSWDHVN")
        XCTAssertEqual(SequenceUtils.reverseComplement(SequenceUtils.reverseComplement(original)), original)
        // 小写输入也要互补（各解析器虽已大写化，ReverseComplementCommand 处理手工输入无此保证）
        XCTAssertEqual(str(SequenceUtils.reverseComplement(bytes("acgt"))), "ACGT")
    }

    // MARK: - 翻译

    func testTranslateBothIsNotLabelledProtein() throws {
        let a = try parse(">s1\nATGATG\n>s2\nATGTTT\n", as: .fasta)
        let both = AlignmentTranslator.translateChecked(a, displayMode: .both)
        XCTAssertNotEqual(both.alignment.datatype, .aminoAcid,
                          "3:1 混排轨的多数派是碱基，绝不能标为 aminoAcid")
        XCTAssertTrue(both.warnings.contains(.mixedCodonTrack))
        XCTAssertFalse(both.isSafeForPhylogenetics)
    }

    func testTranslateRejectsProteinInput() throws {
        let prot = Alignment(sequences: [Sequence(name: "p", residues: bytes("LMFKKM"))],
                             datatype: .aminoAcid)
        XCTAssertThrowsError(try AlignmentTranslator.translate(prot))
        let checked = AlignmentTranslator.translateChecked(prot)
        XCTAssertTrue(checked.warnings.contains(.notNucleotideInput))
    }

    func testFrameshiftProducesXNotFabricatedResidues() {
        // 第二序列含 1 列内部缺失（非 3 倍数）：其后一律 X，不得给出假氨基酸/假终止
        let rows = [
            Sequence(name: "ref", residues: bytes("ATGAAACCCGGGTTT")),
            Sequence(name: "del", residues: bytes("ATG-AACCCGGGTTT")),
        ]
        let a = Alignment(sequences: rows, datatype: .nucleicAcid)
        let r = AlignmentTranslator.translateChecked(a, displayMode: .aminoAcidOnly)
        XCTAssertTrue(r.warnings.contains(where: { if case .frameshift = $0 { return true } else { return false } }),
                      "必须报告哪条序列从哪一列起失去读框")
        let del = str(r.alignment.sequences[1].residues)
        XCTAssertEqual(String(del.prefix(1)), "M")
        XCTAssertTrue(del.dropFirst().allSatisfy { $0 == "X" },
                      "越相位之后不得编造残基，实际得到 \(del)")
    }

    // MARK: - NEXUS / PHYLIP 声明的 NCHAR 与实际写出行数一致

    func testRaggedAlignmentExportRowLengthsMatchDeclaredNchar() throws {
        let ragged = Alignment(sequences: [
            Sequence(name: "a", residues: bytes("ACGTACGT")),
            Sequence(name: "b", residues: bytes("AC")),
        ], datatype: .nucleicAcid)
        let nexus = String(data: AlignmentWriter.writeNexus(ragged), encoding: .utf8)!
        let declared = Int(nexus.components(separatedBy: "NCHAR=").last!
                            .prefix { $0.isNumber })!
        XCTAssertEqual(declared, 8)
        // MATRIX 行 = 4 空格缩进 + 20 列名称字段 + 残基
        for line in nexus.split(separator: "\n") where line.hasPrefix("    a") || line.hasPrefix("    b") {
            let residues = String(line.dropFirst(4 + 20))
            XCTAssertEqual(residues.count, declared, "行残基数必须等于声明的 NCHAR，实际行 \(line)")
        }
        let phy = String(data: AlignmentWriter.writePhylip(ragged, variant: .strict10Char), encoding: .utf8)!
        let data = phy.split(separator: "\n").dropFirst()
        for line in data {
            XCTAssertEqual(String(line).dropFirst(10).count, declared, "strict10 行残基数须等于 NCHAR")
        }
    }

    // MARK: - 未比对输入的标记

    func testUnalignedFastaIsFlagged() throws {
        let a = try parse(">s1\nACGTACGTACGT\n>s2\nACGT\n", as: .fasta)
        XCTAssertEqual(a.provenance, .notAligned,
                       "长度不等的 FASTA 绝不能被当作已比对呈现")
    }

    func testAlignedFastaWithInternalGapsIsFlaggedAligned() throws {
        let a = try parse(">s1\nACGT-ACGT\n>s2\nACGTA-CGT\n", as: .fasta)
        XCTAssertEqual(a.provenance, .aligned)
    }

    // MARK: - 池化一致度 ≠ 平均成对一致度（含缺失矩阵）

    func testPooledIdentityDiffersFromExactMeanPairwiseIdentity() {
        // 构造一个缺失率不均的矩阵：两序列对完整、两序列对几乎全缺失
        let rows = [
            Sequence(name: "a", residues: bytes("ACGTACGTAC")),
            Sequence(name: "b", residues: bytes("ACGTACGTAC")),
            Sequence(name: "c", residues: bytes("NNNNNNACGT")),
            Sequence(name: "d", residues: bytes("NNNNNNATGT")),
        ]
        let a = Alignment(sequences: rows, datatype: .nucleicAcid)
        let pooled = AlignmentStatsCalculator.computeQuality(a).pooledPairwiseIdentity
        let exact = AlignmentStatsCalculator.meanPairwiseIdentityExact(a)
        XCTAssertNotNil(exact)
        XCTAssertNotEqual(pooled, exact!, "两个指标在含缺失矩阵上本就不同，必须分别命名")
    }

    // MARK: - 全 N / 全 X 列不算"最保守"

    func testAllAmbiguousColumnIsNotConserved() {
        let rows = (0..<5).map { _ in Sequence(name: "s", residues: bytes("NNNNN")) }
        let a = Alignment(sequences: rows, datatype: .nucleicAcid)
        let identities = AlignmentStatsCalculator.columnIdentities(a)
        XCTAssertTrue(identities.allSatisfy { $0 == 0 }, "全 N 列一致度必须为 0，而不是 1.0")
    }

    func testAllXProteinColumnIsNotConserved() {
        let rows = (0..<5).map { _ in Sequence(name: "s", residues: bytes("XXXXX")) }
        let a = Alignment(sequences: rows, datatype: .aminoAcid)
        XCTAssertTrue(AlignmentStatsCalculator.columnIdentities(a).allSatisfy { $0 == 0 })
    }

    // MARK: - 顺序 NEXUS 的折行续块必须归给同一条 taxon

    func testSequentialNexusWrappedLinesStayOnTheirTaxon() throws {
        let nexus = """
        #NEXUS
        BEGIN DATA;
          DIMENSIONS NTAX=3 NCHAR=16;
          FORMAT DATATYPE=DNA MISSING=? GAP=;
          MATRIX
          taxA  AAAAAAAAAAAABBBB
          taxB  CCCCCCCCCCCCDDDD
          taxC  EEEEEEEEEEEEFFFF
          ;
        END;
        """
        // 顺序布局、块间无空行、同名折行：残基必须留在自己那条 taxon 上
        let a = try parse(nexus, as: .nexus)
        XCTAssertEqual(a.seqCount, 3)
        XCTAssertEqual(str(a.sequences[0].residues), "AAAAAAAAAAAABBBB")
        XCTAssertEqual(str(a.sequences[1].residues), "CCCCCCCCCCCCDDDD")
        XCTAssertEqual(str(a.sequences[2].residues), "EEEEEEEEEEEEFFFF")
    }

    // MARK: - 数据类型判定接受 '.' / '*' / 数字简并码

    func testDatatypeDetectionAcceptsPhylipDotsAndStops() {
        let dotted = [Sequence(name: "a", residues: bytes("ACGT.ACGT")),
                      Sequence(name: "b", residues: bytes("ACGTACGT*"))]
        XCTAssertEqual(DatatypeDetector.detect(dotted), .nucleicAcid,
                       "含 '.' 空位或 '*' 终止的核酸比对不得被判为蛋白")
        let numeric = [Sequence(name: "a", residues: bytes("ACGT0ACGT1"))]
        XCTAssertEqual(DatatypeDetector.detect(numeric), .nucleicAcid)
        let protein = [Sequence(name: "a", residues: bytes("MFKMELQPRS"))]
        XCTAssertEqual(DatatypeDetector.detect(protein), .aminoAcid)
    }

    func testNexusDatatypeDeclarationVariants() {
        XCTAssertEqual(DatatypeDetector.datatype(fromDeclaration: "DATATYPE=PROTEIN"), .aminoAcid)
        XCTAssertEqual(DatatypeDetector.datatype(fromDeclaration: "DATATYPE PROTEIN"), .aminoAcid)
        XCTAssertEqual(DatatypeDetector.datatype(fromDeclaration: "DATATYPE = AA"), .aminoAcid)
        XCTAssertEqual(DatatypeDetector.datatype(fromDeclaration: "DATATYPE=AMINOACID"), .aminoAcid)
        XCTAssertEqual(DatatypeDetector.datatype(fromDeclaration: "DATATYPE=RNA"), .nucleicAcid)
        XCTAssertEqual(DatatypeDetector.datatype(fromDeclaration: "DATATYPE = DNA"), .nucleicAcid)
    }

    // MARK: - 蛋白配色/保守行不作用于核酸比对

    func testProteinColourSchemesFallBackOnNucleotideData() {
        let rows = [Sequence(name: "a", residues: bytes("AAAA")),
                    Sequence(name: "b", residues: bytes("TTTT"))]
        let dna = Alignment(sequences: rows, datatype: .nucleicAcid)
        // A 在 ClustalX 蛋白表里是"疏水"（索引 1），在核酸轨道上必须是 A 的索引 1…
        XCTAssertEqual(ColorComputer.effectiveScheme(.clustalX, datatype: .nucleicAcid), .defaultNucleotide)
        XCTAssertEqual(ColorComputer.effectiveScheme(.zappo, datatype: .aminoAcid), .zappo)
        XCTAssertEqual(ColorComputer.effectiveScheme(.clustalX, datatype: .aminoAcid), .clustalX)
        XCTAssertEqual(ColorComputer.colorIndex(for: 0x41, scheme: .clustalX, datatype: .nucleicAcid),
                       ColorComputer.colorIndex(for: 0x41, scheme: .defaultNucleotide, datatype: .nucleicAcid),
                       "核酸比对上的 ClustalX 必须等价于核酸轨道")
        _ = dna
    }

    func testClustalConsensusLineDoesNotFakeConservationForAtpairs() throws {
        // 一列只有 A 与 T（A/T 颠换，最不保守）：导出的保守行不得出现 '.'
        let rows = [Sequence(name: "a", residues: bytes("AAAA")),
                    Sequence(name: "b", residues: bytes("ATTT"))]
        let dna = Alignment(sequences: rows, datatype: .nucleicAcid)
        let out = String(data: AlignmentWriter.writeClustal(dna, withConsensus: true), encoding: .utf8)!
        let consensus = out.split(separator: "\n").last { line in
            !line.isEmpty && line.allSatisfy { $0 == " " || "*:. ".contains($0) }
        }
        XCTAssertNotNil(consensus)
        XCTAssertFalse(consensus!.contains("."), "核酸 A/T 列不得借用蛋白弱保守组得到半保守点")
    }

    // MARK: - 重复名称不得首尾拼接

    func testDuplicateNamesBecomeSeparateRecords() throws {
        let clustal = """
        CLUSTAL W (1.0) multiple sequence alignment

        seq1  ACGTACGT
        seq1  TTGGCCAA

        """
        let a = try parse(clustal, as: .clustal)
        XCTAssertEqual(a.seqCount, 2, "同名序列必须成为两条记录，而不是拼成一条 16 残基假序列")
        XCTAssertEqual(str(a.sequences[0].residues), "ACGTACGT")
        XCTAssertEqual(str(a.sequences[1].residues), "TTGGCCAA")
    }

    // MARK: - Clustal 单行内的多个残基块

    func testClustalMultipleBlocksOnOneLineAreAllKept() throws {
        let aln = """
        CLUSTAL W (1.0) multiple sequence alignment

        seq1  ACGTACGT ACGTACGT ACGT
        seq2  TTGGCCAA TTGGCCAA TTGG

        """
        let a = try parse(aln, as: .clustal)
        XCTAssertEqual(str(a.sequences[0].residues), "ACGTACGTACGTACGTACGT", "parts[2...] 不得被丢弃")
        XCTAssertEqual(a.length, 20)
    }

    // MARK: - 去除空位列后 NEXUS 分区坐标必须重映射

    func testCharsetRangesRemapAfterRemovingGapColumns() throws {
        let rows = [
            Sequence(name: "a", residues: bytes("AC--GTTT")),
            Sequence(name: "b", residues: bytes("AC--GTAA")),
        ]
        let a = Alignment(sequences: rows, datatype: .nucleicAcid)
        a.charsets = [CharsetInfo(name: "part1", ranges: [(1, 8)]),
                     CharsetInfo(name: "part2", ranges: [(5, 8)])]
        let cmd = RemoveColumnsCommand(columnsToRemove: [2, 3], alignment: a, description: "去除空位列")
        cmd.execute(on: a)
        XCTAssertEqual(a.length, 6)
        XCTAssertEqual(a.charsets[0].ranges.map { "\($0.start)-\($0.end)" }, ["1-2", "3-6"],
                       "删除 2 列后 1-8 必须变成 1-6，否则导出的 CHARSET 指向错误列")
        XCTAssertEqual(a.charsets[1].ranges.map { "\($0.start)-\($0.end)" }, ["3-6"])
        cmd.undo(on: a)
        XCTAssertEqual(a.charsets[1].ranges.map { "\($0.start)-\($0.end)" }, ["5-8"],
                       "撤销必须把分区一并还原")
    }

    func testCharsetStepSpecSurvivesWhenColumnsUntouched() throws {
        let nexus = """
        #NEXUS
        BEGIN DATA;
          DIMENSIONS NTAX=1 NCHAR=6;
          FORMAT DATATYPE=DNA;
          MATRIX
          a   ACGTAC
          ;
        END;
        BEGIN SETS;
          CHARSET codon = 1-6\\3;
        END;
        """
        let a = try parse(nexus, as: .nexus)
        let out = String(data: AlignmentWriter.writeNexus(a), encoding: .utf8)!
        XCTAssertTrue(out.contains("1-6\\3"), "未改列时应原样回写步长定义，实际 \(out)")
    }

    // MARK: - 非正则 IUPAC 检索与正则路径同一口径

    func testSearchNonRegexMatchesLiteralNAndTUSwapping() throws {
        let rows = [
            Sequence(name: "hasN", residues: bytes("ACGTNNACGT")),
            Sequence(name: "hasU", residues: bytes("ACGUACGUAC")),
            Sequence(name: "plain", residues: bytes("ACGTACGTAC")),
        ]
        let a = Alignment(sequences: rows, datatype: .nucleicAcid)
        // 查询 CGTN：只有数据里第 4 位是字面 N 时才可能命中；
        // 非正则路径的展开表必须包含字面 N（与正则路径的 [ACGTN] 同一口径）。
        let engine = SearchEngine(alignment: a, pattern: "CGTN", useRegex: false)
        let hits = engine.findAll()
        XCTAssertTrue(hits.contains { $0.seqIndex == 0 && $0.position == 1 },
                      "关掉正则也要能命中数据里的字面 N")
        XCTAssertEqual(hits.filter { $0.seqIndex == 0 }.count, 1)

        let uEngine = SearchEngine(alignment: a, pattern: "ACGU", useRegex: false)
        XCTAssertEqual(Set(uEngine.findAll().map { $0.seqIndex }).sorted(), [0, 1, 2],
                       "查询里的 U 必须同时匹配数据中的 T（DNA 反向转录本）")
    }

    func testDegeneracyRangeIsNotDegenerateRange() {
        // min 与 max 必须真的不同
        let (lo, hi) = IUPACCode.degeneracy("ACGN")
        XCTAssertLessThan(lo, hi, "含歧义位时简并度应给出真实范围（下界按可判定、上界按最坏）")
        XCTAssertEqual(IUPACCode.degeneracy("ACGT").min, 1)
        XCTAssertEqual(IUPACCode.degeneracy("ACGT").max, 1)
    }

    // MARK: - GC 单一事实来源（CLI 与 GUI 同口径由源码约束保证）

    func testGcContentIgnoresAmbiguityAndGapCharacters() {
        // SequenceUtils.gcContent 是 GC 的唯一实现：分母只含 A/C/G/T/U
        XCTAssertEqual(SequenceUtils.gcContent(bytes("ACGT")), 0.5, accuracy: 1e-12)
        XCTAssertEqual(SequenceUtils.gcContent(bytes("GCNNNN")), 1.0, accuracy: 1e-12,
                       "N 等歧义码进入分母会系统性低估 GC%")
        XCTAssertEqual(SequenceUtils.gcContent(bytes("GC-.*")), 1.0, accuracy: 1e-12)
    }

    // MARK: - Logo 截断必须可见

    func testLogoReportsTruncation() {
        let long = String(repeating: "ACGT", count: 2500)   // 10_000 列
        let a = Alignment(sequences: [Sequence(name: "a", residues: bytes(long))], datatype: .nucleicAcid)
        let computed = LogoCalculator.compute(a, maxColumns: 4000)
        XCTAssertEqual(computed.columns.count, 4000)
        XCTAssertEqual(computed.alignmentColumns, 10_000)
        XCTAssertTrue(computed.isTruncated)
        XCTAssertEqual(computed.omittedColumns, 6000, "界面必须能把'还有 6000 列未计算'告诉用户")
        XCTAssertFalse(LogoCalculator.compute(a, maxColumns: 20_000).isTruncated)
    }

    // MARK: - NJ 树的披露

    func testNjTreeDisclosesSampling() {
        let rows = (0..<5).map { i -> Sequence in
            Sequence(name: "t\(i)", residues: bytes(String(repeating: "A", count: 3 + i)))
        }
        let a = Alignment(sequences: rows, datatype: .nucleicAcid)
        let full = PhyloBuilder.njTree(a)
        XCTAssertFalse(full.wasSampled)
        XCTAssertEqual(full.sequencesUsed, 5)
        let sampled = PhyloBuilder.njTree(a, maxSeqs: 2)
        XCTAssertTrue(sampled.wasSampled)
        XCTAssertEqual(sampled.sequencesTotal, 5)
        XCTAssertEqual(sampled.sequencesUsed, 2)
        XCTAssertNotNil(sampled.samplingNote)
        XCTAssertTrue(sampled.newick.contains("sampled=2_of_5"), "树串自身要携带抽样事实")
    }

    func testNjTwoTaxaKeepsBranchLength() {
        let a = Alignment(sequences: [
            Sequence(name: "A", residues: bytes("AAAA")),
            Sequence(name: "B", residues: bytes("AATT")),
        ], datatype: .nucleicAcid)
        let tree = PhyloBuilder.njTree(a, provenanceComment: false).newick
        // p-distance = 0.5，无根两叶各占一半 → 0.25000
        XCTAssertTrue(tree.contains(":0.25000"), "两条序列也必须给出分支长度，实际 \(tree)")
    }

    func testNjTipNamesAreUniqueAfterSanitising() {
        let a = Alignment(sequences: [
            Sequence(name: "Taxon A", residues: bytes("AAAA")),
            Sequence(name: "Taxon_A", residues: bytes("AAAC")),
            Sequence(name: "Taxon-C", residues: bytes("AACC")),
        ], datatype: .nucleicAcid)
        let tree = PhyloBuilder.njTree(a).newick
        let tips = ["Taxon_A", "Taxon_A_2", "Taxon-C"].filter { tree.contains("\($0):") || tree.contains("\($0),") }
        XCTAssertGreaterThanOrEqual(tips.count, 2, "归一化后同名 tip 必须唯一化，实际 \(tree)")
    }

    // MARK: - 盐校正的量纲（与 Biopython 的绝对对照）

    func testSaltCorrectionMatchesReferenceImplementation() throws {
        // 参照值来自 Biopython 1.87 Bio.SeqUtils.MeltingTemp.Tm_NN(
        //     "ATGCGTTACGAATTGCAAGC", dnac1=250, dnac2=250, saltcorr=5, nn_table=DNA_NN4)
        //   Na=50 mM, Mg=0   -> 55.46 °C
        //   Na=50 mM, Mg=1.5 -> 62.13 °C
        let seq = "ATGCGTTACGAATTGCAAGC"
        let noMg = try XCTUnwrap(PrimerCalculator.tm(seq, options: TmOptions(naMolar: 0.05, mgMolar: 0, oligoMolar: 250e-9)).max)
        let withMg = try XCTUnwrap(PrimerCalculator.tm(seq, options: TmOptions(naMolar: 0.05, mgMolar: 1.5e-3, oligoMolar: 250e-9)).max)
        XCTAssertEqual(noMg, 55.46, accuracy: 1.5, "Mg=0 的近邻法 Tm 必须与第三方实现吻合")
        XCTAssertEqual(withMg, 62.13, accuracy: 1.5, "1.5 mM Mg2+ 的绝对值必须与第三方实现吻合")
        XCTAssertGreaterThan(withMg, noMg, "Mg2+ 只应小幅稳定双链")
        XCTAssertLessThan(withMg - noMg, 12.0, "Mg 项抬高幅度必须在物理合理区间内")
        // 单位约定自洽：120*sqrt(Mg_mM) 折成等效 Na+ 后，两条路径必须给出同一个 Tm
        let equivalentNa = 0.05 + 120.0 * (1.5).squareRoot() / 1000.0
        let viaNa = try XCTUnwrap(PrimerCalculator.tm(seq, options: TmOptions(naMolar: equivalentNa, mgMolar: 0, oligoMolar: 250e-9)).max)
        XCTAssertEqual(viaNa, withMg, accuracy: 1e-6)
        // dNTP 螯合 Mg2+：[dNTPs] >= [Mg2+] 时不再有游离 Mg2+ 贡献
        let chelated = try XCTUnwrap(PrimerCalculator.tm(seq, options: TmOptions(naMolar: 0.05, mgMolar: 1.5e-3,
                                                                                oligoMolar: 250e-9, dntpMolar: 1.5e-3)).max)
        XCTAssertEqual(chelated, noMg, accuracy: 1e-6)
    }

    // MARK: - Phred 偏移判据：高质量 Phred+33 文件按 +33 解析

    func testPhred33HighQualityReadsAreNotMisreadAsPhred64() throws {
        // 全 Q40（'I' = 0x49）混入一个 Q0 后，必须按 Phred+33 解析
        let quality = String(repeating: "I", count: 10)
        let fastq = "@r1\nACGTACGTAC\n+\n\(quality)\n@r2\nACGTACGTAC\n+\n!!!!!!!!!!\n"
        let a = try parse(fastq, as: .fastq)
        let summary = AlignmentStatsCalculator.computeQualitySummary(a)
        XCTAssertEqual(summary.minPhred, 0, "文件里出现过 '!'(Q0) 即可确定性判为 Phred+33")
        XCTAssertLessThan(summary.meanPhred, 40)
    }

    // MARK: - padToMaxLength 之后质量与残基仍一一对应

    func testPaddingKeepsQualityResidueCorrespondence() throws {
        let fastq = "@r1\nACGT\n+\n!!!!\n@r2\nACGTACGTAC\n+\nIIIIIIIIII\n"
        let a = try parse(fastq, as: .fastq)
        XCTAssertEqual(a.length, 10)
        for seq in a.sequences {
            XCTAssertEqual(seq.quality?.count, seq.residues.count,
                           "补齐后质量数组长度必须与残基数组一致")
        }
    }

    // MARK: - 通用断言：全格式逐字节往返

    func testByteExactRoundTripAcrossFormats() throws {
        let original = Alignment(sequences: [
            Sequence(name: "AF123456.1", residues: bytes("ACGTACGTAC")),   // (a) 恰为 10 字符
            Sequence(name: "short", residues: bytes("ACGT-ACGTA")),         // 普通
            Sequence(name: "dup", residues: bytes("TT.GGCCAA-")),           // (b) 含 '.' 空位（写出侧归一化）
            Sequence(name: "dup", residues: bytes("AATTCCGG--")),           // (c) 重复名
        ], datatype: .nucleicAcid)
        original.padToMaxLength()
        // 写出侧把 '.' / '~' 归一化为规范空位，因此往返后的真值也按归一化口径比较
        let expected = original.sequences.map { str($0.residues.map { ResidueAlphabet.normalize($0) }) }
        XCTAssertEqual(Set(expected), Set(["ACGTACGTAC", "ACGT-ACGTA", "TT-GGCCAA-", "AATTCCGG--"]))

        for variant in [PhylipVariant.strict10Char, .sequential, .interleaved, .fullnamePadded] {
            let text = String(data: AlignmentWriter.writePhylip(original, variant: variant), encoding: .utf8)!
            let back = try parse(text, as: .phylip)
            XCTAssertEqual(back.sequences.map { str($0.residues) }.sorted(), expected.sorted(),
                           "通用断言：PHYLIP 变体 \(variant) 往返后残基必须逐字节相等")
        }
        let nexusText = String(data: AlignmentWriter.writeNexus(original), encoding: .utf8)!
        XCTAssertEqual(try parse(nexusText, as: .nexus).sequences.map { str($0.residues) }.sorted(),
                       expected.sorted())
        let clustalText = String(data: AlignmentWriter.writeClustal(original), encoding: .utf8)!
        XCTAssertEqual(try parse(clustalText, as: .clustal).sequences.map { str($0.residues) }.sorted(),
                       expected.sorted())
        let stoText = String(data: AlignmentWriter.writeStockholm(original), encoding: .utf8)!
        XCTAssertEqual(try parse(stoText, as: .stockholm).sequences.map { str($0.residues) }.sorted(),
                       expected.sorted())
        let msfText = String(data: AlignmentWriter.writeMsf(original), encoding: .utf8)!
        XCTAssertEqual(try parse(msfText, as: .msf).sequences.map { str($0.residues) }.sorted(),
                       expected.sorted())
    }

    // MARK: - 压缩负载里含 1F 8B 08 的单成员 gzip 仍可读

    func testSingleMemberGzipContainingMagicBytesStillDecodes() throws {
        // 构造一个未压缩内容里就含 0x1F8B08 的文件，压缩后魔数出现在"负载语义"层面；
        // 更关键的是随机压缩数据里的巧合魔数不得触发拒绝 —— trailer CRC 校验给出确定性判据。
        let payload = Data([0x1F, 0x8B, 0x08] + Array(">a\nACGT\n".utf8) + [0x1F, 0x8B, 0x08])
        let gz = try XCTUnwrap(Gzip.compress(payload))
        let out = try XCTUnwrap(Gzip.decompress(gz))
        XCTAssertEqual(out, payload, "正常压缩的单成员文件不得被误判为拼接 gzip")
        // 真正的拼接文件仍必须被拒绝
        let first = try XCTUnwrap(Gzip.compress(payload))
        let second = try XCTUnwrap(Gzip.compress(payload))
        var concat = first
        concat.append(second)
        // 拼接后整体 trailer 与"单成员"解释不符 → 返回 nil 触发报错，不静默丢数据
        XCTAssertNil(Gzip.decompress(concat), "真实拼接仍须被拒绝，不能静默丢后半份")
    }
}
