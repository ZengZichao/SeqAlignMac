//  CLIRunner.swift
//  SeqAlignMac — 无界面命令行模式
//
//  用法：
//    SeqAlignMac cli stats    <aln-file> [--out <csv>]
//    SeqAlignMac cli export   <aln-file> --format png|pdf|svg [-o <out>]
//                            [--fontsize 13] [--dark] [--scheme minimal|clustalx|zappo|seaview|default|titv|okabeito]
//    SeqAlignMac cli convert  <aln-file> --format nexus|phylip|clustal|msf|stockholm|fasta|fastq
//                            [-o <out-file>] [--start N] [--end M]
//
//  stats 输出 CSV（stdout 或 --out 文件）：序列数/列数/类型/各项一致度/变异位点等。
//  convert 将输入对齐文件转换为指定格式写出（支持区域裁剪 --start/--end）。
//  在 SeqAlignMacApp.init() 中检测参数并先行退出，不启动 GUI。

import AppKit
import Foundation

enum CLIRunner {
    static func run(_ args: [String]) -> Never {
        // args = [可执行路径, "cli", 子命令, 文件, ...选项]；去掉前两个
        let params = Array(args.dropFirst(2))
        guard params.count >= 2 else {
            print(usage)
            exit(64)
        }

        let subcommand = params[0]
        let inputPath = params[1]
        guard let inputData = loadData(inputPath) else {
            FileHandle.standardError.write("无法读取文件: \(inputPath)\n".data(using: .utf8)!)
            exit(66)
        }

        let format = FormatDetector.detect(inputData)
        do {
            let alignment = try AlignmentParser.parse(inputData, format: format)
            switch subcommand {
            case "stats":
                try runStats(alignment, fileName: (inputPath as NSString).lastPathComponent,
                             outPath: option(params, "--out"))
            case "export":
                try runExport(alignment, params: params,
                              baseName: ((inputPath as NSString).lastPathComponent as NSString).deletingPathExtension)
            case "convert":
                try runConvert(alignment, params: params,
                               baseName: ((inputPath as NSString).lastPathComponent as NSString).deletingPathExtension)
            default:
                print(usage)
                exit(64)
            }
            exit(0)
        } catch {
            FileHandle.standardError.write("错误: \(error.localizedDescription)\n".data(using: .utf8)!)
            exit(70)
        }
    }

    private static let usage = """
    Usage:
      SeqAlignMac cli stats    <alignment-file> [--out results.csv]
      SeqAlignMac cli export   <alignment-file> --format png|pdf|svg [-o output]
                             [--fontsize N] [--dark] [--scheme minimal|clustalx|zappo|seaview|default|titv|okabeito]
      SeqAlignMac cli convert  <alignment-file> --format nexus|phylip|clustal|msf|stockholm|fasta|fastq
                             [-o output-file] [--start N] [--end M]
    Supported input formats: FASTA / FASTQ / NEXUS / PHYLIP / CLUSTAL / MSF / Stockholm (.gz supported)
    """

    // MARK: - stats 子命令

    private static func runStats(_ alignment: Alignment, fileName: String, outPath: String?) throws {
        let q = AlignmentStatsCalculator.computeQuality(alignment)
        let qs = AlignmentStatsCalculator.computeQualitySummary(alignment)

        var lines: [String] = []
        func csv(_ field: String) -> String {
            // RFC 4180：含逗号/引号/换行的字段加引号并转义内部双引号
            if field.contains(",") || field.contains("\"") || field.contains("\n") {
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return field
        }
        lines.append("metric,value")
        lines.append("file,\(csv(fileName))")
        lines.append("sequences,\(alignment.seqCount)")
        lines.append("columns,\(alignment.length)")
        lines.append("datatype,\(alignment.datatype == .nucleicAcid ? "nucleotide" : "aminoacid")")
                // 字段名与实现口径一致（位点加权池化值，不是"平均成对一致度"）
        lines.append("pooled_identity_site_weighted,\(String(format: "%.4f", q.pooledPairwiseIdentity))")
        // 把"这堆序列是否真的已比对"随 CSV 一起导出，避免下游把右补空位的
        // 未比对输入当成比对做定量分析
        lines.append("declared_aligned,\(alignment.provenance.rawValue)")
        lines.append("mean_column_identity,\(String(format: "%.4f", meanColumnIdentity(alignment)))")
        lines.append("min_column_identity,\(String(format: "%.4f", q.minColumnIdentity))")
        lines.append("max_column_identity,\(String(format: "%.4f", q.maxColumnIdentity))")
        lines.append("gap_columns,\(q.gapColumns)")
        lines.append("total_columns,\(q.totalColumns)")
        lines.append("variable_sites,\(q.variableSites)")
        lines.append("parsimony_informative_sites,\(q.parsimonySites)")
        lines.append("singleton_sites,\(q.singletonSites)")
        lines.append("gc_content,\(String(format: "%.4f", gcContent(alignment)))")
        if qs.hasData {
            lines.append("fastq_mean_phred,\(String(format: "%.2f", qs.meanPhred))")
            lines.append("fastq_q20_ratio,\(String(format: "%.4f", qs.q20Ratio))")
            lines.append("fastq_q30_ratio,\(String(format: "%.4f", qs.q30Ratio))")
        }
        let output = lines.joined(separator: "\n") + "\n"

        if let outPath {
            try output.data(using: .utf8)!.write(to: URL(fileURLWithPath: outPath))
            print("已写入 \(outPath)")
        } else {
            print(output, terminator: "")
        }
    }

    private static func meanColumnIdentity(_ alignment: Alignment) -> Double {
        let ids = AlignmentStatsCalculator.columnIdentities(alignment)
        guard !ids.isEmpty else { return 0 }
        return ids.reduce(0, +) / Double(ids.count)
    }

    /// GC 一律走 `SequenceUtils.gcContent`（工程声明的"单一事实来源"）。
    /// 若在此自建口径，除 '-' 与 'N' 以外的所有字节都会算作"可判定碱基"，
    /// R/Y/S/W/K/M/B/D/H/V、'.'、'?'、'*' 等简并/模糊字符会分母计分但分子不计，
    /// 导出的 gc_content 会比界面显示值系统性偏低，且对简并码最密集的数据偏得最多。
    private static func gcContent(_ alignment: Alignment) -> Double {
        guard alignment.datatype == .nucleicAcid else { return 0 }
        var total = 0.0
        var count = 0
        alignment.lockedSequences { seqs in
            for seq in seqs {
                let acgt = seq.residues.filter { [0x41, 0x43, 0x47, 0x54, 0x55].contains($0) }.count
                guard acgt > 0 else { continue }
                total += SequenceUtils.gcContent(seq.residues) * Double(acgt)
                count += acgt
            }
        }
        return count > 0 ? total / Double(count) : 0
    }

    // MARK: - export 子命令

    private static func runExport(_ alignment: Alignment, params: [String], baseName: String) throws {
        let fmtName = option(params, "--format") ?? "png"
        let exportFormat: ExportFormat
        switch fmtName.lowercased() {
        case "png": exportFormat = .png
        case "pdf": exportFormat = .pdf
        case "svg": exportFormat = .svg
        default:
            FileHandle.standardError.write("Error: unknown --format '\(fmtName)' (expected png|pdf|svg)\n".data(using: .utf8)!)
            exit(64)
        }

        var options = ExportOptions(format: exportFormat,
                                     colorScheme: scheme(named: option(params, "--scheme")))
        if let raw = option(params, "--fontsize"), let v = Double(raw), v >= 6, v <= 40 {
            options.fontSize = v
        } else if option(params, "--fontsize") != nil {
            FileHandle.standardError.write("Warning: invalid --fontsize, using default 13\n".data(using: .utf8)!)
        }
        options.dark = params.contains("--dark")
        let savedNameW = UserDefaults.standard.double(forKey: "SeqAlignMac.nameColWidth")
        options.nameColWidth = savedNameW > 0 ? CGFloat(savedNameW) : 150

        let outPath = option(params, "-o") ?? option(params, "--output")
            ?? "\(baseName)_alignment.\(fmtName.lowercased())"

        let data = try ExportManager.exportImage(alignment, options: options)
        try data.write(to: URL(fileURLWithPath: outPath))
        print("已导出 \(outPath)")
    }

    // MARK: - convert 子命令

    private static func runConvert(_ alignment: Alignment, params: [String], baseName: String) throws {
        guard let fmtName = option(params, "--format") else {
            FileHandle.standardError.write("Error: --format is required for convert\n".data(using: .utf8)!)
            exit(64)
        }

        // 可选区域裁剪：--start/--end（1-based 闭区间）
        let startIdx = option(params, "--start").flatMap { Int($0) } ?? 1
        let endIdx = option(params, "--end").flatMap { Int($0) } ?? alignment.length
        let workAlignment: Alignment
        if startIdx > 1 || endIdx < alignment.length {
            workAlignment = try subAlignment(alignment, start: startIdx, end: endIdx)
        } else {
            workAlignment = alignment
        }

        // 混排轨不是可比对的数据，CLI 同样拒绝输出（避免错误结果流入下游管线）
        if AlignmentTranslator.isMixedCodonTrack(workAlignment) {
            FileHandle.standardError.write("Error: codon+amino-acid mixed track cannot be exported; choose a single-track translation\n".data(using: .utf8)!)
            exit(65)
        }
        let data: Data
        let defaultExt: String
        switch fmtName.lowercased() {
        case "nexus", "nex":
            data = AlignmentWriter.writeNexus(workAlignment)
            defaultExt = "nexus"
        case "phylip", "phy":
            data = AlignmentWriter.writePhylip(workAlignment)
            defaultExt = "phy"
        case "clustal", "aln":
            data = AlignmentWriter.writeClustal(workAlignment)
            defaultExt = "aln"
        case "msf":
            data = AlignmentWriter.writeMsf(workAlignment)
            defaultExt = "msf"
        case "stockholm", "sto":
            data = AlignmentWriter.writeStockholm(workAlignment)
            defaultExt = "sto"
        case "fasta", "fa", "fas":
            data = AlignmentWriter.writeFasta(workAlignment)
            defaultExt = "fasta"
        case "fastq", "fq":
            // FASTQ 输出走 writeFastq（Phred+33，质量行按残基长度对齐），
            // 与读取路径对称，保证往返不丢质量串。
            guard workAlignment.sequences.contains(where: { $0.quality != nil }) else {
                throw CoreError.unsupported("convert fastq 需要带质量值的 FASTQ 来源；非 FASTQ 数据请用 --format fasta")
            }
            data = AlignmentWriter.writeFastq(workAlignment)
            defaultExt = "fastq"
        default:
            FileHandle.standardError.write("Error: unknown --format '\(fmtName)' (expected nexus|phylip|clustal|msf|stockholm|fasta|fastq)\n".data(using: .utf8)!)
            exit(64)
        }

        let outPath = option(params, "-o") ?? option(params, "--output")
            ?? "\(baseName).\(defaultExt)"
        try data.write(to: URL(fileURLWithPath: outPath))
        print("Converted to \(fmtName) → \(outPath)")
    }

    /// 从对齐中截取列区域（1-based 闭区间）
    private static func subAlignment(_ alignment: Alignment, start: Int, end: Int) throws -> Alignment {
        let s = max(1, start) - 1
        let e = min(alignment.length, end)
        guard s < e else {
            throw CoreError.invalidArg("Invalid region: \(start)-\(end)")
        }
        var subSeqs: [Sequence] = []
        let width = e - s
        // 裁剪后必须把 NEXUS 分区平移到新区间，否则 --start/--end 导出的
        // NEXUS 会带着旧坐标的 CHARSET 定义（字面合法、指向错误的列），
        // MrBayes / RAxML / IQ-TREE 照单全收 → 最难事后发现的错误之一。
        let croppedCharsets = CharsetRemapper.crop(alignment.charsets, startCol: s, endCol: e - 1)
        alignment.lockedSequences { seqs in
            for seq in seqs {
                let count = seq.residues.count
                let lo = min(s, count)
                let hi = max(lo, min(e, count))
                var slice = Array(seq.residues[lo..<hi])
                // 序列短于请求区间时以 '-' 右补齐到统一宽度（与写盘层 paddedSlice 口径一致）
                if slice.count < width {
                    slice.append(contentsOf: [UInt8](repeating: 0x2D, count: width - slice.count))
                }
                subSeqs.append(Sequence(name: seq.name, description: seq.description, residues: slice))
            }
        }
        let out = Alignment(sequences: subSeqs, datatype: alignment.datatype,
                            metadata: alignment.metadata, charsets: croppedCharsets)
        out.provenance = alignment.provenance
        return out
    }

    private static func scheme(named name: String?) -> ColorScheme {
        switch (name ?? "minimal").lowercased() {
        case "clustalx": return .clustalX
        case "zappo": return .zappo
        case "seaview": return .seaView
        case "default": return .defaultNucleotide
        case "titv": return .transitionTransversion
        case "okabeito": return .okabeIto
        default: return .minimal
        }
    }

    // MARK: - 工具

    /// 读取文件（支持 .gz 自动解压）
    private static func loadData(_ path: String) -> Data? {
        guard var data = FileManager.default.contents(atPath: path) else { return nil }
        if (path as NSString).pathExtension.lowercased() == "gz" {
            if let decompressed = Gzip.decompress(data) {
                data = decompressed
            } else {
                return nil
            }
        }
        return data
    }

    /// 取 --key value 形式的选项值（值不能是另一个 "-" 开头的 flag）
    private static func option(_ params: [String], _ key: String) -> String? {
        guard let idx = params.firstIndex(of: key), idx + 1 < params.count else { return nil }
        let value = params[idx + 1]
        guard !value.hasPrefix("-") || value == "-" else { return nil }
        return value
    }
}
