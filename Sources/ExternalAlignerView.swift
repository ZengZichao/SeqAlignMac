//  ExternalAlignerView.swift
//  SeqAlignMac — 外部比对器弹窗（从 ToolSheetViews.swift 拆分）
//
//  调用 MAFFT / MUSCLE / ClustalW2 等外部比对工具对当前序列重新比对。

import AppKit
import Darwin
import SwiftUI

struct ExternalAlignerView: View {
    @Binding var isPresented: Bool
    @Binding var path: String
    @Environment(\.openWindow) private var openWindow
    @State private var isRunning = false
    @State private var runError: String?
    @State private var selectedPreset = L.s.alignerPresetMafft
    @State private var runningTask: Process?
    @State private var timeoutWork: DispatchWorkItem?
    @State private var cancelRequested = false

    /// 预设 = 显示名 + 命令模板。模板中 {input}/{output} 为文件占位符；
    /// captureStdout = true 时结果取进程 stdout（mafft 的输出方式），忽略 {output}。
    /// 各比对器参数格式互不兼容（旧版对 mafft 追加 -in/-out 导致无法运行）：
    /// - mafft：位置参数输入，结果写 stdout
    /// - muscle v5：-align <in> -output <out>
    /// - clustalw2：-infile=<in> -outfile=<out>
    private var presets: [(name: String, cmd: String, captureStdout: Bool)] {
        [
            (L.s.alignerPresetMafft, "mafft --quiet {input}", true),
            (L.s.alignerPresetMuscle, "muscle -align {input} -output {output}", false),
            (L.s.alignerPresetClustal, "clustalw2 -infile={input} -outfile={output} -quiet", false),
            (L.s.alignerPresetCustom, "", true),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.s.alignerTitle).font(.system(size: Minimal.fontXL, weight: .semibold))
            Text(L.s.alignerDesc)
                .font(.system(size: Minimal.fontXS))
                .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 12) {
                Text(L.s.alignerLabel)
                    .font(.system(size: Minimal.fontSM))
                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    .frame(width: 68, alignment: .leading)
                Picker("", selection: $selectedPreset) {
                    ForEach(presets, id: \.name) { p in
                        Text(p.name).tag(p.name)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: selectedPreset) { _, newPreset in
                    if let p = presets.first(where: { $0.name == newPreset }) {
                        path = p.cmd
                    }
                }
                .frame(minWidth: 220, alignment: .leading)
            }

            MinimalTextField(placeholder: L.s.alignerPlaceholder, text: $path)
            Text(String(format: L.s.alignerExample, "{input}", "{output}"))
                .font(.system(size: Minimal.fontXS))
                .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                .font(.system(size: Minimal.fontXS))
                .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))

            if let err = runError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(Minimal.destructive(dark: isDarkAppearance)))
                    Text(err)
                        .font(.system(size: Minimal.fontXS))
                        .foregroundColor(Color(Minimal.destructive(dark: isDarkAppearance)))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L.s.alignerRunning)
                        .font(.system(size: Minimal.fontXS))
                        .lineLimit(1)
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                }
            }

            HStack {
                Spacer()
                MinimalSecondaryButton(title: L.s.cancel) {
                    if !isRunning { isPresented = false }
                }
                .disabled(isRunning)
                Button(action: { if isRunning { cancelRun() } else { run() } }) {
                    Text(isRunning ? L.s.alignerTerminate : L.s.alignerRun)
                        .font(.system(size: Minimal.fontSM, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(Color(Minimal.surface(dark: isDarkAppearance)))
                        .padding(.horizontal, Minimal.space4 - Minimal.space1)
                        .frame(height: Minimal.controlH)
                        .background(RoundedRectangle(cornerRadius: Minimal.radiusSM, style: .continuous)
                            .fill(Color(Minimal.primary(dark: isDarkAppearance))))
                        .contentShape(Rectangle())
                }
                .buttonStyle(MinimalButtonStyle())
                .keyboardShortcut(.return)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 460, height: 300)
        .minimalSheetContainer()
        .onAppear {
            // 首次打开时 path 为空则填充当前预设的命令模板，
            // 避免用户第一次点「运行」命中空命令报错
            if path.isEmpty {
                if let p = presets.first(where: { $0.name == selectedPreset }) {
                    path = p.cmd
                }
            }
        }
    }

    private func run() {
        guard !isRunning else { return }
        guard let ws = WindowRegistry.shared.activeForAction, let align = ws.currentAlignment else { return }
        var cmd = path.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { runError = L.s.alignerEnterCmd; return }

        // 点击立即置 isRunning
        runError = nil
        isRunning = true
        cancelRequested = false

        // 在主线程读取（presets 计算属性访问 L10n），其余重活全部后台
        // 过去 captureStdout **按预设名**查（"自定义"预设为 true），
        // 而界面示例文案恰恰鼓励用户写 {input} / {output}。于是
        // "自定义 + myaligner {input} {output}"这一被界面推荐的组合下，
        // 程序去取空的 stdout 判定失败，而 defer 已把比对器写好的结果文件删掉。
        // 现在按用户**实际填写的命令**判断：命令里出现 {output} 就读文件，否则取 stdout。
        let captureStdout = !cmd.contains("{output}")
        // 后台线程禁止读活的 Alignment（违反工程 B3「后台须持快照」约定，
        // 与 TranslationOptionsView / ExportCoordinator / SaveManager 一致）——
        // 在主线程先取快照，后台仅操作该独立副本。
        let snapshot = align.snapshot()

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // FASTA 序列化 + 临时文件写盘移入后台
            let fastaData = AlignmentWriter.writeFasta(snapshot)
            let tempDir = FileManager.default.temporaryDirectory
            let inputFile = tempDir.appendingPathComponent("seqalign_input_\(UUID().uuidString).fasta")
            let outputFile = tempDir.appendingPathComponent("seqalign_output_\(UUID().uuidString).fasta")
            do {
                try fastaData.write(to: inputFile)
            } catch {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runError = "\(L.s.alignerTempWriteFail) \(error.localizedDescription)"
                }
                return
            }

            // 模板占位符展开；无占位符的自定义命令按 stdout 捕获处理（输入经 stdin 传入）
            let hasPlaceholders = cmd.contains("{input}") || cmd.contains("{output}")
            let feedsStdin = !hasPlaceholders
            if hasPlaceholders {
                cmd = cmd.replacingOccurrences(of: "{input}", with: inputFile.path)
                cmd = cmd.replacingOccurrences(of: "{output}", with: outputFile.path)
            }

            let args = parseCommandLine(cmd)
            guard let executable = args.first else {
                try? FileManager.default.removeItem(at: inputFile)
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runError = L.s.alignerEnterCmd
                }
                return
            }

            let exeURL: URL
            if executable.contains("/") {
                let resolved = (executable as NSString).expandingTildeInPath
                guard FileManager.default.isExecutableFile(atPath: resolved) else {
                    try? FileManager.default.removeItem(at: inputFile)
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.runError = "\(L.s.alignerNotFound)\(executable)"
                    }
                    return
                }
                exeURL = URL(fileURLWithPath: resolved)
            } else {
                guard let found = locateExecutable(executable) else {
                    try? FileManager.default.removeItem(at: inputFile)
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.runError = "\(L.s.alignerNotFound)\(executable)"
                    }
                    return
                }
                exeURL = found
            }

            let task = Process()
            DispatchQueue.main.async { self.runningTask = task }
            task.executableURL = exeURL
            task.arguments = Array(args.dropFirst())
            let stderrPipe = Pipe()
            task.standardError = stderrPipe
            // stdout 始终接管为 Pipe 并发排空：无论是否用作结果，都要防止
            // 子进程写满 64KB 管道缓冲后与父进程互等死锁
            let stdoutPipe = Pipe()
            task.standardOutput = stdoutPipe
            if feedsStdin {
                // 自定义命令无 {input} 占位符时经 stdin 供给序列
                let stdinPipe = Pipe()
                task.standardInput = stdinPipe
                DispatchQueue.global(qos: .userInitiated).async {
                    // 子进程若不读 stdin 即退出（命令拼错参数的常见后果），
                    // NSFileHandle 写已关闭管道会抛 ObjC 异常，Swift 无 catch 可拦。
                    // 改用 try? + writeabilityHandler 安全写入，失败不崩溃。
                    do {
                        try stdinPipe.fileHandleForWriting.write(contentsOf: fastaData)
                    } catch {
                        // EPIPE 或管道已关闭：静默处理，子进程退出码会给出报错
                    }
                    try? stdinPipe.fileHandleForWriting.close()
                }
            }

            final class TimeoutBox { var timedOut = false }
            let box = TimeoutBox()
            let timeoutWork = DispatchWorkItem { [self] in
                if task.isRunning {
                    box.timedOut = true
                    task.terminate()
                    // 宽限期后升级 SIGKILL，防止比对器忽略 SIGTERM 残留
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5) {
                        if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                    }
                    DispatchQueue.main.async {
                        self.runError = L.s.alignerTimeout
                        self.isRunning = false
                    }
                }
            }
            DispatchQueue.main.async { self.timeoutWork = timeoutWork }
            // 超时可配置。mafft --localpair --maxiterate 1000 在数千条序列上
            // 常态化超过 300 s，固定阈值让用户只能拿到"超时"提示，无法完成 L-INS-i 分析。
            let timeoutSeconds = max(10, AppSettings.externalAlignerTimeoutSeconds)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Double(timeoutSeconds),
                                                                 execute: timeoutWork)

            defer {
                try? FileManager.default.removeItem(at: inputFile)
                try? FileManager.default.removeItem(at: outputFile)
            }
            do {
                try task.run()
            } catch {
                timeoutWork.cancel()
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runError = "\(L.s.alignerFailExec) \(error.localizedDescription)"
                }
                return
            }

            // 并发排空 stdout/stderr（readDataToEndOfFile 读到 EOF 才返回），
            // 与 waitUntilExit 并行执行；先等退出再读是经典的管道死锁写法
            var stdoutData = Data()
            var stderrData = Data()
            let drainGroup = DispatchGroup()
            drainGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                drainGroup.leave()
            }
            drainGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                drainGroup.leave()
            }

            task.waitUntilExit()
            drainGroup.wait()
            timeoutWork.cancel()

            if cancelRequested {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runError = L.s.alignerCancelled
                }
                return
            }
            if box.timedOut {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runError = L.s.alignerTimeout
                }
                return
            }
            if task.terminationStatus != 0 {
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = tail.isEmpty ? "N/A" : String(tail.prefix(200))
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runError = "\(L.s.alignerFailCode) \(task.terminationStatus)): \(detail)"
                }
                return
            }
            // captureStdout（mafft / 自定义）→ 结果取 stdout；否则读 {output} 文件
            let resultData: Data
            if captureStdout {
                resultData = stdoutData
            } else {
                guard let fileData = try? Data(contentsOf: outputFile), !fileData.isEmpty else {
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.runError = L.s.alignerFailRead
                    }
                    return
                }
                resultData = fileData
            }
            // 结果解析（上百 MB 时可达秒级）移入后台，主线程只做窗口打开。
            // 结果格式自动检测（clustalw2 的 -outfile 是 CLUSTAL 格式而非 FASTA）
            guard !resultData.isEmpty else {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runError = L.s.alignerFailRead
                }
                return
            }
            let resultAlign: Alignment
            do {
                // 不再用 try? 吞掉带行号的解析诊断，用户只看到一句笼统的"读取失败"
                resultAlign = try AlignmentParser.parse(resultData)
            } catch {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runError = "\(L.s.alignerFailRead): \(error.localizedDescription)"
                }
                return
            }
            // 与输入快照做一致性校验。MAFFT 异常时会少给序列或重排行序，
            // MUSCLE 会重命名（追加 // 标签）——过去这些都当成"成功的新比对"开进新窗口，
            // 用户以为只是换了算法。
            let mismatches = Self.resultMismatchReport(input: snapshot, output: resultAlign)
            if !mismatches.isEmpty {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runError = "\(L.s.alignerResultMismatch): \(mismatches.joined(separator: "; "))"
                }
                return
            }
            DispatchQueue.main.async {
                self.isRunning = false
                PendingWindowData.prepare(
                    alignment: resultAlign,
                    fileName: ws.currentFileName.isEmpty ? "alignment_result.fasta" : "\(ws.currentFileName) (aligned)",
                    format: .fasta
                )
                self.openWindow(id: "seqalign-main")
                self.isPresented = false
            }
        }
    }

    private func cancelRun() {
        // 竞态防护：不得立刻把 isRunning 置 false——后台块仍在跑
        // （要等到取消检查点才发现 cancelRequested），期间用户可以再次点"运行"，
        // 新任务覆盖 runningTask 后第一个子进程会失去控制句柄（终止按钮再也打不到它）。
        // 现在只发取消信号，isRunning 由后台块收尾时统一置回。
        cancelRequested = true
        runningTask?.terminate()
    }

    /// 比对结果相对输入的一致性判据（序列数 / 名称集合 / 行等长）。
    static func resultMismatchReport(input: Alignment, output: Alignment) -> [String] {
        var problems: [String] = []
        if output.seqCount != input.seqCount {
            problems.append("\(L.s.alignerMismatchCount) (\(input.seqCount) → \(output.seqCount))")
        }
        let before = Set(input.sequences.map { $0.name })
        let after = Set(output.sequences.map { $0.name })
        if before != after {
            let lost = before.subtracting(after).prefix(3).joined(separator: ", ")
            let added = after.subtracting(before).prefix(3).joined(separator: ", ")
            if !lost.isEmpty { problems.append("\(L.s.alignerMismatchMissing): \(lost)") }
            if !added.isEmpty { problems.append("\(L.s.alignerMismatchExtra): \(added)") }
        }
        if Set(output.sequences.map { $0.residues.count }).count > 1 {
            problems.append(L.s.alignerMismatchRagged)
        }
        return problems
    }

    private func locateExecutable(_ name: String) -> URL? {
        let paths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin", "/usr/bin", "/bin"]
        for dir in paths {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = [name]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) else { return nil }
        return URL(fileURLWithPath: out)
    }

    private func parseCommandLine(_ cmd: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inDouble = false
        var inSingle = false
        for char in cmd {
            if char == "\"" && !inSingle {
                inDouble.toggle()
            } else if char == "'" && !inDouble {
                inSingle.toggle()
            } else if (char == " " || char == "\t") && !inDouble && !inSingle {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            args.append(current)
        }
        return args
    }
}
