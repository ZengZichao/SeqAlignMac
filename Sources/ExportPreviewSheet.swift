//  ExportPreviewSheet.swift
//  SeqAlignMac — 导出预览面板（UI10：导出格式选择与选项面板）
//
//  在导出图像前提供一个预览 Sheet，让用户：
//  1. 选择导出格式（PNG / PDF / SVG）
//  2. 切换选项（仅选中区域 / 深色模式导出）
//  3. 查看预估输出尺寸
//  4. 点击「导出…」打开系统保存面板

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 导出预览模型

final class ExportPreviewModel: ObservableObject {
    @Published var format: ExportFormat = .png
    @Published var selectionOnly: Bool = false
    @Published var darkMode: Bool = false
    @Published var previewImage: NSImage?
    /// 预览失败显式提示
    @Published var previewFailed = false
    /// 导出进行中反馈（按钮转 spinner、防重复点击）
    @Published var exporting = false

    private var align: Alignment?
    private var scheme: ColorScheme = .minimal
    private var fontSize: CGFloat = 13
    private var selection: SelectionRange?
    /// 预览代次号：快速切换选项时丢弃乱序完成的旧渲染结果
    private var previewGeneration = 0

    func configure(alignment: Alignment, scheme: ColorScheme, fontSize: CGFloat,
                   selection: SelectionRange?, darkMode: Bool) {
        self.align = alignment
        self.scheme = scheme
        self.fontSize = fontSize
        self.selection = selection
        self.darkMode = darkMode
        self.selectionOnly = selection != nil
        generatePreview()
    }

    func generatePreview() {
        guard let align = align else { return }
        var options = ExportOptions(format: .png,
                                    colorScheme: scheme, dark: darkMode)
        if selectionOnly, let sel = selection {
            options.rowRange = sel.rowStart...sel.rowEnd
            options.colRange = sel.colStart...sel.colEnd
        }
        let savedNameW = UserDefaults.standard.double(forKey: "SeqAlignMac.nameColWidth")
        let nameW = savedNameW > 0 ? CGFloat(savedNameW) : 150
        options.fontSize = fontSize
        options.nameColWidth = nameW
        options.showConsensus = true
        // 预览限宽 1600px：若按 300 DPI 全尺寸渲染，数十秒无反馈，
        // 超大比对还会撞 2GB 位图上限后静默失败；320×240 缩略框用不到全尺寸
        options.maxPixelWidth = 1600

        previewGeneration += 1
        let generation = previewGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            // 后台渲染必须持快照（B3 约定）：活引用 + 主线程编辑 = 数组竞争崩溃
            let snapshot = align.snapshot()
            do {
                let data = try ExportManager.exportImage(snapshot, options: options)
                DispatchQueue.main.async {
                    guard self.previewGeneration == generation else { return }
                    self.previewImage = NSImage(data: data)
                    self.previewFailed = self.previewImage == nil
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.previewGeneration == generation else { return }
                    self.previewImage = nil
                    self.previewFailed = true
                }
            }
        }
    }

    func estimatedSizeDescription() -> String {
        guard let align = align else { return "—" }
        let savedNameW = UserDefaults.standard.double(forKey: "SeqAlignMac.nameColWidth")
        let nameWidth = savedNameW > 0 ? CGFloat(savedNameW) : 150
        let geo = AlignmentRenderGeometry.make(fontSize: fontSize, nameColWidth: nameWidth, showConsensus: true)
        let rows: ClosedRange<Int>
        let cols: ClosedRange<Int>
        if selectionOnly, let sel = selection {
            // 过期选区可能越界，复用 effectiveRowRange 的钳制逻辑
            rows = max(0, sel.rowStart)...min(sel.rowEnd, max(0, align.seqCount - 1))
            cols = max(0, sel.colStart)...min(sel.colEnd, max(0, align.length - 1))
        } else {
            rows = 0...max(0, align.seqCount - 1)
            cols = 0...max(0, align.length - 1)
        }
        let (width, height) = geo.layoutSize(rows: rows, cols: cols)
        switch format {
        case .png:
            let scale = 300.0 / 72.0
            return String(format: "%.0f × %.0f px (300 DPI)", width * scale, height * scale)
        case .pdf, .svg:
            return String(format: "%.0f × %.0f pt", width, height)
        }
    }

    func performExport() {
        guard let align = align, !exporting else { return }
        let panel = NSSavePanel()
        switch format {
        case .png: panel.allowedContentTypes = [.png]
        case .pdf: panel.allowedContentTypes = [.pdf]
        case .svg: panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .plainText]
        }

        let baseName = ((WindowRegistry.shared.activeForAction?.currentFileName ?? "alignment") as NSString).deletingPathExtension
        let ext: String
        switch format {
        case .png: ext = "png"
        case .pdf: ext = "pdf"
        case .svg: ext = "svg"
        }
        let fileName = baseName.isEmpty ? "alignment" : baseName
        panel.nameFieldStringValue = "\(fileName)_alignment.\(ext)"

        if panel.runModal() == .OK, let url = panel.url {
            var options = ExportOptions(format: format,
                                        colorScheme: scheme, dark: darkMode)
            if selectionOnly, let sel = selection {
                options.rowRange = sel.rowStart...sel.rowEnd
                options.colRange = sel.colStart...sel.colEnd
            }
            let savedNameW = UserDefaults.standard.double(forKey: "SeqAlignMac.nameColWidth")
            let nameW = savedNameW > 0 ? CGFloat(savedNameW) : 150
            options.fontSize = fontSize
            options.nameColWidth = nameW
            options.showConsensus = true

            // 导出期间给出进行中反馈
            exporting = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let snapshot = align.snapshot()
                    let data = try ExportManager.exportImage(snapshot, options: options)
                    try data.write(to: url)
                    DispatchQueue.main.async {
                        self.exporting = false
                        WindowRegistry.shared.activeForAction?.showToast("\(L.s.toastExported) \(url.lastPathComponent)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.exporting = false
                        WindowRegistry.shared.activeForAction?.errorMessage = "\(L.s.errorExportFail)\(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

// MARK: - 导出预览视图

struct ExportPreviewSheet: View {
    @ObservedObject var model: ExportPreviewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.s.exportPreviewTitle)
                .font(.system(size: Minimal.fontXL, weight: .semibold))

            HStack(alignment: .top, spacing: 20) {
                // 预览缩略图
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.s.exportImage)
                        .font(.system(size: Minimal.fontSM, weight: .semibold))
                        .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    ScrollView {
                        if let img = model.previewImage {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 320, maxHeight: 240)
                                .background(RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(Minimal.card(dark: isDarkAppearance))))
                                .overlay(RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
                        } else if model.previewFailed {
                            // 预览失败显式文案
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 22))
                                    .foregroundColor(Color(Minimal.textFaint(dark: isDarkAppearance)))
                                Text(L.s.exportPreviewFailed)
                                    .font(.system(size: Minimal.fontXS))
                                    .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 320, height: 240)
                        } else {
                            ProgressView()
                                .frame(width: 320, height: 240)
                        }
                    }
                    .frame(width: 336, height: 256)
                    .background(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                        .fill(Color(Minimal.card(dark: isDarkAppearance))))
                    .overlay(RoundedRectangle(cornerRadius: Minimal.radiusSM)
                        .stroke(Color(Minimal.border(dark: isDarkAppearance)), lineWidth: 1))
                }

                // 选项面板
                VStack(alignment: .leading, spacing: 14) {
                    // 格式选择
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.s.exportPreviewFormat)
                            .font(.system(size: Minimal.fontSM, weight: .semibold))
                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                        Picker("", selection: $model.format) {
                            Text("PNG").tag(ExportFormat.png)
                            Text("PDF").tag(ExportFormat.pdf)
                            Text("SVG").tag(ExportFormat.svg)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .tint(Color(Minimal.primary(dark: isDarkAppearance)))
                    }

                    Divider()
                        .background(Color(Minimal.border(dark: isDarkAppearance)))

                    // 选项
                    Toggle(L.s.exportOnlySelection, isOn: $model.selectionOnly)
                        .font(.system(size: Minimal.fontSM))
                        .disabled(WindowRegistry.shared.activeForAction?.currentSelection == nil)
                        .onChange(of: model.selectionOnly) { _, _ in model.generatePreview() }

                    Toggle(L.s.exportPreviewDarkMode, isOn: $model.darkMode)
                        .font(.system(size: Minimal.fontSM))
                        .onChange(of: model.darkMode) { _, _ in model.generatePreview() }

                    Divider()
                        .background(Color(Minimal.border(dark: isDarkAppearance)))

                    // 预估尺寸
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.s.exportPreviewSize)
                            .font(.system(size: Minimal.fontSM, weight: .semibold))
                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                        Text(model.estimatedSizeDescription())
                            .font(.system(size: Minimal.fontSM, design: .monospaced))
                            .foregroundColor(Color(Minimal.text(dark: isDarkAppearance)))
                    }
                }
                .frame(width: 220, alignment: .leading)
            }

            Spacer()

            HStack {
                Spacer()
                if model.exporting {
                    // 导出进行中反馈
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L.s.exportingText)
                            .font(.system(size: Minimal.fontXS))
                            .foregroundColor(Color(Minimal.textMuted(dark: isDarkAppearance)))
                    }
                }
                MinimalSecondaryButton(title: L.s.cancel) { isPresented = false }
                    .keyboardShortcut(.escape)
                MinimalPrimaryButton(title: L.s.exportPreviewExportBtn) {
                    model.performExport()
                }
                .disabled(model.exporting)
                .keyboardShortcut(.return)
            }
        }
        .padding(Minimal.space5)
        .frame(width: 620, height: 420)
        .minimalSheetContainer()
    }
}
