//  Localization.swift
//  SeqAlignMac — 中英文国际化系统
//
//  提供 LanguageManager（ObservableObject）管理当前语言（中文/英文），
//  AppStrings 持有全部 UI 字符串的双语版本。所有视图/菜单消费 L.s.xxx 获取当前语言文本。

import AppKit
import SwiftUI

// MARK: - 语言枚举

enum AppLanguage: String, CaseIterable {
    case zh
    case en

    var displayName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    var systemImage: String {
        switch self {
        case .zh: return "character.bubble"
        case .en: return "globe"
        }
    }
}

// MARK: - 语言管理器

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    static let key = "SeqAlignMac.language"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.key)
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            // 首启动按系统首选语言决定默认值
            let preferred = Locale.preferredLanguages.first ?? "en"
            language = preferred.lowercased().hasPrefix("zh") ? .zh : .en
        }
    }

    func toggle() {
        language = (language == .zh) ? .en : .zh
    }

    func set(_ lang: AppLanguage) {
        language = lang
    }
}

// MARK: - 字符串表

enum L {
    static var s: AppStrings {
        LanguageManager.shared.language == .zh ? .zh : .en
    }
}

/// 改为 final class——struct 版本在每次 `L.s` 访问时复制约 400 个字段，
/// 一个 body 内访问 40 次 ≈ 1.6 万次引用计数操作；class 引用语义消除该成本
/// （全部字段为 let，只读消费，无值语义依赖）。
final class AppStrings {

    /// class 不合成 memberwise init，显式定义（参数顺序与属性声明一致）
    init(
        close: String,
        cancel: String,
        ok: String,
        unnamed: String,
        search: String,
        toolbarOpen: String,
        toolbarSave: String,
        toolbarExample: String,
        toolbarAlign: String,
        toolbarTranslate: String,
        toolbarPrimer: String,
        toolbarQuality: String,
        toolbarLegend: String,
        toolbarSearch: String,
        toolbarUndo: String,
        toolbarRedo: String,
        toolbarExport: String,
        toolbarSettings: String,
        toolbarCommandPalette: String,
        toolbarMore: String,
        toolbarColorScheme: String,
        toolbarZoom: String,
        toolbarZoomIn: String,
        toolbarZoomOut: String,
        toolbarZoomReset: String,
        toolbarAppearance: String,
        toolbarLanguage: String,
        toolbarNewTab: String,
        sidebarGroupFile: String,
        sidebarGroupEdit: String,
        sidebarGroupAnalysis: String,
        sidebarGroupView: String,
        sidebarGroupExport: String,
        sidebarGroupSystem: String,
        schemeMinimal: String,
        schemeClustalX: String,
        schemeZappo: String,
        schemeSeaView: String,
        schemeDefault: String,
        schemeTransitionTransversion: String,
        clustalXThreshold: String,
        clustalXThresholdHint: String,
        ctxRenameSeq: String,
        ctxDeleteSeq: String,
        ctxMoveTop: String,
        ctxMoveBottom: String,
        ctxSortBy: String,
        ctxSortByName: String,
        ctxSortBySimilarity: String,
        ctxSortByGC: String,
        ctxSortByLength: String,
        ctxSortByLengthNoGaps: String,
        ctxCopySelection: String,
        ctxColorScheme: String,
        ctxTranslate: String,
        ctxReverseComplement: String,
        ctxInsertGap: String,
        ctxPaste: String,
        ctxAddSeq: String,
        ctxRemoveAllGapCols: String,
        ctxRemoveHighGapCols: String,
        ctxGapTrimming: String,
        ctxSelectCodonPos: String,
        ctxCodonPos1: String,
        ctxCodonPos2: String,
        ctxCodonPos3: String,
        statsPhyloInfo: String,
        statsVariableSites: String,
        statsParsimonySites: String,
        statsSingletonSites: String,
        statsSamplingHint: String,
        consensusMode: String,
        consensusMajority: String,
        consensusIUPAC: String,
        consensusStrict: String,
        settingsCodonTriplet: String,
        translateNameOption: String,
        translateKeepOriginal: String,
        translateAddSuffix: String,
        translateSixFrameOverview: String,
        translateHighlightStop: String,
        translateHighlightStart: String,
        exportSequence: String,
        exportImage: String,
        exportFASTA: String,
        exportNEXUS: String,
        exportPHYLIP: String,
        exportCLUSTAL: String,
        exportMSF: String,
        toolbarRunMSA: String,
        helpRunMSA: String,
        helpTranslateDisabled: String,
        helpPrimerDisabled: String,
        toastGapColsRemoved: String,
        toastHighGapColsRemoved: String,
        toastSortByName: String,
        toastSortBySimilarity: String,
        toastSortByGC: String,
        toastSortByLength: String,
        toastSortByLengthNoGaps: String,
        toastReverseComplement: String,
        searchPlaceholderContent: String,
        searchPlaceholderContentRegex: String,
        searchPlaceholderName: String,
        searchPlaceholderNameRegex: String,
        searchFind: String,
        searchPrev: String,
        searchNext: String,
        searchNoMatch: String,
        searchComputing: String,
        searchClose: String,
        searchScopeContent: String,
        searchScopeName: String,
        searchOptions: String,
        searchRegex: String,
        searchRegexOn: String,
        searchRegexOff: String,
        statusSeqCount: String,
        statusColCount: String,
        statusPosition: String,
        statusResidue: String,
        statusIdentity: String,
        statusType: String,
        statusCharset: String,
        statusNucleic: String,
        statusAmino: String,
        statusNoFile: String,
        statsTitle: String,
        statsOverview: String,
        statsFile: String,
        statsFormat: String,
        statsSeqCount: String,
        statsColCount: String,
        statsType: String,
        statsQuality: String,
        statsMeanPairwise: String,
        statsMeanColIdentity: String,
        statsMinColIdentity: String,
        statsMaxColIdentity: String,
        statsGapCols: String,
        statsTotalCols: String,
        statsConservation: String,
        statsHighConserved: String,
        statsConservationHint: String,
        statsConsensus: String,
        statsConsensusCopy: String,
        statsConsensusCopied: String,
        statsCursor: String,
        statsEmptyTitle: String,
        statsEmptyDesc: String,
        statsNoData: String,
        statsComputing: String,
        emptyTitle: String,
        emptyDesc1: String,
        emptyDesc2: String,
        emptyOpenFile: String,
        emptyLoadExample: String,
        aboutTitle: String,
        aboutVersion: String,
        aboutDesc: String,
        aboutFeatures: String,
        aboutRefs: String,
        aboutLicense: String,
        guideTitle: String,
        guideStart: String,
        qualityTitle: String,
        qualityNoFile: String,
        qualityCharset: String,
        settingsTitle: String,
        settingsAppearance: String,
        settingsLight: String,
        settingsDark: String,
        settingsSystem: String,
        settingsColorScheme: String,
        settingsFontSize: String,
        settingsShowConsensus: String,
        settingsHighContrast: String,
        settingsFocusDim: String,
        settingsDone: String,
        renameTitle: String,
        renamePlaceholder: String,
        renameConfirm: String,
        moveTitle: String,
        moveCount: String,
        moveFrom: String,
        moveTo: String,
        moveConfirm: String,
        alignerTitle: String,
        alignerDesc: String,
        alignerLabel: String,
        alignerPlaceholder: String,
        alignerExample: String,
        alignerRunning: String,
        alignerRun: String,
        alignerTerminate: String,
        alignerTimeout: String,
        alignerCancelled: String,
        alignerFailCode: String,
        alignerFailRead: String,
        alignerFailExec: String,
        alignerTempWriteFail: String,
        alignerNotFound: String,
        alignerEnterCmd: String,
        primerTitle: String,
        primerSeqA: String,
        primerSeqB: String,
        primerPlaceholderA: String,
        primerPlaceholderB: String,
        primerFromSel: String,
        primerCalcTm: String,
        primerCalcGC: String,
        primerSelfDimer: String,
        primerHeteroDimer: String,
        primerResultPlaceholder: String,
        primerTmLabel: String,
        primerTmRange: String,
        primerParams: String,
        primerNa: String,
        primerMg: String,
        primerOligo: String,
        primerGC: String,
        primerSelfDimerTitle: String,
        primerHeteroTitle: String,
        primerDG: String,
        primerSeq: String,
        primerSeqALbl: String,
        primerSeqBLbl: String,
        primerWarnDimer: String,
        primerSafeDimer: String,
        primerCalcFail: String,
        primerError: String,
        primerNeedSeqA: String,
        primerNeedSeqB: String,
        translateTitle: String,
        translateCodeTable: String,
        translateFrame: String,
        translateMode: String,
        translateModeCodon: String,
        translateModeAA: String,
        translateModeBoth: String,
        translateModeIgnoreGaps: String,
        translateNewWindow: String,
        translateBtn: String,
        unsavedTitle: String,
        unsavedDesc: String,
        unsavedSave: String,
        unsavedDontSave: String,
        cmdPaletteTitle: String,
        cmdPalettePlaceholder: String,
        cmdPaletteNoMatch: String,
        legendTitle: String,
        legendCanvasOps: String,
        legendOp1: String,
        legendOp2: String,
        legendOp3: String,
        legendOp4: String,
        legendOp5: String,
        legendOp6: String,
        legendDarkNote: String,
        menuNewTab: String,
        menuNewWindow: String,
        menuOpen: String,
        menuCloseWindow: String,
        menuCloseTab: String,
        menuOpenRecent: String,
        menuNoRecent: String,
        menuSave: String,
        menuSaveAs: String,
        menuExportPNG: String,
        menuExportPDF: String,
        menuExportSVG: String,
        menuUndo: String,
        menuRedo: String,
        menuCut: String,
        menuCopy: String,
        menuPaste: String,
        menuSelectAll: String,
        menuRevComp: String,
        menuInsertGap: String,
        menuDeleteSeq: String,
        menuMoveSeq: String,
        menuRenameSeq: String,
        menuView: String,
        menuTools: String,
        menuAppearance: String,
        menuLanguage: String,
        menuSettings: String,
        menuHelp: String,
        menuGuide: String,
        menuLoadExample: String,
        menuAbout: String,
        menuRunAlign: String,
        menuTranslate: String,
        menuPrimer: String,
        menuQuality: String,
        menuSearch: String,
        menuFindNext: String,
        menuFindPrev: String,
        menuCmdPalette: String,
        menuExport: String,
        menuZoom: String,
        menuLight: String,
        menuDark: String,
        menuFollowSystem: String,
        menuChinese: String,
        menuEnglish: String,
        menuToggleConsensus: String,
        toastSaved: String,
        toastExported: String,
        toastClipboardEmpty: String,
        toastCopied: String,
        toastPasted: String,
        toastUndo: String,
        toastRedo: String,
        toastReplaceTranslated: String,
        toastFirstRun: String,
        loadingText: String,
        loadingCancel: String,
        errorSaveFail: String,
        errorExportFail: String,
        errorRegexInvalid: String,
        errorClipboardUnrecognized: String,
        quitTitle: String,
        quitSingleDesc: String,
        quitMultiDesc: String,
        quitSaveExit: String,
        windowTitleUnnamed: String,
        windowTitlePrefix: String,
        alignerPresetMafft: String,
        alignerPresetMuscle: String,
        alignerPresetClustal: String,
        alignerPresetCustom: String,
        cmdOpen: String,
        cmdSave: String,
        cmdSaveAs: String,
        cmdRunAlign: String,
        cmdTranslate: String,
        cmdPrimer: String,
        cmdQuality: String,
        cmdSearch: String,
        cmdCopy: String,
        cmdSelectAll: String,
        cmdRevComp: String,
        cmdInsertGap: String,
        cmdDeleteSeq: String,
        cmdMoveSeq: String,
        cmdRenameSeq: String,
        cmdSchemeMinimal: String,
        cmdSchemeClustalX: String,
        cmdSchemeZappo: String,
        cmdSchemeSeaView: String,
        cmdSchemeDefault: String,
        cmdSchemeTransitionTransversion: String,
        cmdZoomIn: String,
        cmdZoomOut: String,
        cmdZoomReset: String,
        cmdToggleConsensus: String,
        cmdThemeLight: String,
        cmdThemeDark: String,
        cmdThemeSystem: String,
        cmdSettings: String,
        cmdGuide: String,
        cmdLoadExample: String,
        cmdAbout: String,
        cmdAddSeq: String,
        cmdBatchReplace: String,
        cmdReplaceAlignment: String,
        cmdTransaction: String,
        schemeOkabeIto: String,
        fastqQuality: String,
        fastqMeanPhred: String,
        fastqMinPhred: String,
        fastqQ20: String,
        fastqQ30: String,
        statsMethodNote: String,
        logoTitle: String,
        logoHint: String,
        treeTitle: String,
        treeHint: String,
        treeCopyNewick: String,
        windowTitle: String,
        windowSize: String,
        annotTitle: String,
        annotLoad: String,
        annotLoadFailRead: String,
        annotLoadEmpty: String,
        annotLoaded: String,
        annotSeqidNotFound: String,
        annotNone: String,
        annotSeq: String,
        annotType: String,
        annotRange: String,
        annotName: String,
        annotJump: String,
        toolbarDifference: String,
        helpDifference: String,
        toolbarLogo: String,
        toolbarTree: String,
        toolbarWindowChart: String,
        toolbarAnnotation: String,
        aboutCitation: String,
        tooltipCloseTab: String,
        tooltipNewTab: String,
        helpOpenFile: String,
        helpSave: String,
        helpExample: String,
        helpTranslate: String,
        helpPrimer: String,
        helpQuality: String,
        helpLegend: String,
        helpUndo: String,
        helpRedo: String,
        helpExport: String,
        helpSettings: String,
        helpCmdPalette: String,
        helpColorScheme: String,
        helpZoomReset: String,
        helpZoomIn: String,
        helpZoomOut: String,
        helpAppearance: String,
        helpLanguage: String,
        helpSearch: String,
        helpRegexOn: String,
        helpRegexOff: String,
        exportOnlySelection: String,
        exportPNG: String,
        exportPDF: String,
        exportSVG: String,
        exportPreviewTitle: String,
        exportPreviewFormat: String,
        exportPreviewSize: String,
        exportPreviewDarkMode: String,
        exportPreviewExportBtn: String,
        savingText: String,
        exportingText: String,
        exportPreviewFailed: String
    ) {
        self.close = close
        self.cancel = cancel
        self.ok = ok
        self.unnamed = unnamed
        self.search = search
        self.toolbarOpen = toolbarOpen
        self.toolbarSave = toolbarSave
        self.toolbarExample = toolbarExample
        self.toolbarAlign = toolbarAlign
        self.toolbarTranslate = toolbarTranslate
        self.toolbarPrimer = toolbarPrimer
        self.toolbarQuality = toolbarQuality
        self.toolbarLegend = toolbarLegend
        self.toolbarSearch = toolbarSearch
        self.toolbarUndo = toolbarUndo
        self.toolbarRedo = toolbarRedo
        self.toolbarExport = toolbarExport
        self.toolbarSettings = toolbarSettings
        self.toolbarCommandPalette = toolbarCommandPalette
        self.toolbarMore = toolbarMore
        self.toolbarColorScheme = toolbarColorScheme
        self.toolbarZoom = toolbarZoom
        self.toolbarZoomIn = toolbarZoomIn
        self.toolbarZoomOut = toolbarZoomOut
        self.toolbarZoomReset = toolbarZoomReset
        self.toolbarAppearance = toolbarAppearance
        self.toolbarLanguage = toolbarLanguage
        self.toolbarNewTab = toolbarNewTab
        self.sidebarGroupFile = sidebarGroupFile
        self.sidebarGroupEdit = sidebarGroupEdit
        self.sidebarGroupAnalysis = sidebarGroupAnalysis
        self.sidebarGroupView = sidebarGroupView
        self.sidebarGroupExport = sidebarGroupExport
        self.sidebarGroupSystem = sidebarGroupSystem
        self.schemeMinimal = schemeMinimal
        self.schemeClustalX = schemeClustalX
        self.schemeZappo = schemeZappo
        self.schemeSeaView = schemeSeaView
        self.schemeDefault = schemeDefault
        self.schemeTransitionTransversion = schemeTransitionTransversion
        self.clustalXThreshold = clustalXThreshold
        self.clustalXThresholdHint = clustalXThresholdHint
        self.ctxRenameSeq = ctxRenameSeq
        self.ctxDeleteSeq = ctxDeleteSeq
        self.ctxMoveTop = ctxMoveTop
        self.ctxMoveBottom = ctxMoveBottom
        self.ctxSortBy = ctxSortBy
        self.ctxSortByName = ctxSortByName
        self.ctxSortBySimilarity = ctxSortBySimilarity
        self.ctxSortByGC = ctxSortByGC
        self.ctxSortByLength = ctxSortByLength
        self.ctxSortByLengthNoGaps = ctxSortByLengthNoGaps
        self.ctxCopySelection = ctxCopySelection
        self.ctxColorScheme = ctxColorScheme
        self.ctxTranslate = ctxTranslate
        self.ctxReverseComplement = ctxReverseComplement
        self.ctxInsertGap = ctxInsertGap
        self.ctxPaste = ctxPaste
        self.ctxAddSeq = ctxAddSeq
        self.ctxRemoveAllGapCols = ctxRemoveAllGapCols
        self.ctxRemoveHighGapCols = ctxRemoveHighGapCols
        self.ctxGapTrimming = ctxGapTrimming
        self.ctxSelectCodonPos = ctxSelectCodonPos
        self.ctxCodonPos1 = ctxCodonPos1
        self.ctxCodonPos2 = ctxCodonPos2
        self.ctxCodonPos3 = ctxCodonPos3
        self.statsPhyloInfo = statsPhyloInfo
        self.statsVariableSites = statsVariableSites
        self.statsParsimonySites = statsParsimonySites
        self.statsSingletonSites = statsSingletonSites
        self.statsSamplingHint = statsSamplingHint
        self.consensusMode = consensusMode
        self.consensusMajority = consensusMajority
        self.consensusIUPAC = consensusIUPAC
        self.consensusStrict = consensusStrict
        self.settingsCodonTriplet = settingsCodonTriplet
        self.translateNameOption = translateNameOption
        self.translateKeepOriginal = translateKeepOriginal
        self.translateAddSuffix = translateAddSuffix
        self.translateSixFrameOverview = translateSixFrameOverview
        self.translateHighlightStop = translateHighlightStop
        self.translateHighlightStart = translateHighlightStart
        self.exportSequence = exportSequence
        self.exportImage = exportImage
        self.exportFASTA = exportFASTA
        self.exportNEXUS = exportNEXUS
        self.exportPHYLIP = exportPHYLIP
        self.exportCLUSTAL = exportCLUSTAL
        self.exportMSF = exportMSF
        self.toolbarRunMSA = toolbarRunMSA
        self.helpRunMSA = helpRunMSA
        self.helpTranslateDisabled = helpTranslateDisabled
        self.helpPrimerDisabled = helpPrimerDisabled
        self.toastGapColsRemoved = toastGapColsRemoved
        self.toastHighGapColsRemoved = toastHighGapColsRemoved
        self.toastSortByName = toastSortByName
        self.toastSortBySimilarity = toastSortBySimilarity
        self.toastSortByGC = toastSortByGC
        self.toastSortByLength = toastSortByLength
        self.toastSortByLengthNoGaps = toastSortByLengthNoGaps
        self.toastReverseComplement = toastReverseComplement
        self.searchPlaceholderContent = searchPlaceholderContent
        self.searchPlaceholderContentRegex = searchPlaceholderContentRegex
        self.searchPlaceholderName = searchPlaceholderName
        self.searchPlaceholderNameRegex = searchPlaceholderNameRegex
        self.searchFind = searchFind
        self.searchPrev = searchPrev
        self.searchNext = searchNext
        self.searchNoMatch = searchNoMatch
        self.searchComputing = searchComputing
        self.searchClose = searchClose
        self.searchScopeContent = searchScopeContent
        self.searchScopeName = searchScopeName
        self.searchOptions = searchOptions
        self.searchRegex = searchRegex
        self.searchRegexOn = searchRegexOn
        self.searchRegexOff = searchRegexOff
        self.statusSeqCount = statusSeqCount
        self.statusColCount = statusColCount
        self.statusPosition = statusPosition
        self.statusResidue = statusResidue
        self.statusIdentity = statusIdentity
        self.statusType = statusType
        self.statusCharset = statusCharset
        self.statusNucleic = statusNucleic
        self.statusAmino = statusAmino
        self.statusNoFile = statusNoFile
        self.statsTitle = statsTitle
        self.statsOverview = statsOverview
        self.statsFile = statsFile
        self.statsFormat = statsFormat
        self.statsSeqCount = statsSeqCount
        self.statsColCount = statsColCount
        self.statsType = statsType
        self.statsQuality = statsQuality
        self.statsMeanPairwise = statsMeanPairwise
        self.statsMeanColIdentity = statsMeanColIdentity
        self.statsMinColIdentity = statsMinColIdentity
        self.statsMaxColIdentity = statsMaxColIdentity
        self.statsGapCols = statsGapCols
        self.statsTotalCols = statsTotalCols
        self.statsConservation = statsConservation
        self.statsHighConserved = statsHighConserved
        self.statsConservationHint = statsConservationHint
        self.statsConsensus = statsConsensus
        self.statsConsensusCopy = statsConsensusCopy
        self.statsConsensusCopied = statsConsensusCopied
        self.statsCursor = statsCursor
        self.statsEmptyTitle = statsEmptyTitle
        self.statsEmptyDesc = statsEmptyDesc
        self.statsNoData = statsNoData
        self.statsComputing = statsComputing
        self.emptyTitle = emptyTitle
        self.emptyDesc1 = emptyDesc1
        self.emptyDesc2 = emptyDesc2
        self.emptyOpenFile = emptyOpenFile
        self.emptyLoadExample = emptyLoadExample
        self.aboutTitle = aboutTitle
        self.aboutVersion = aboutVersion
        self.aboutDesc = aboutDesc
        self.aboutFeatures = aboutFeatures
        self.aboutRefs = aboutRefs
        self.aboutLicense = aboutLicense
        self.guideTitle = guideTitle
        self.guideStart = guideStart
        self.qualityTitle = qualityTitle
        self.qualityNoFile = qualityNoFile
        self.qualityCharset = qualityCharset
        self.settingsTitle = settingsTitle
        self.settingsAppearance = settingsAppearance
        self.settingsLight = settingsLight
        self.settingsDark = settingsDark
        self.settingsSystem = settingsSystem
        self.settingsColorScheme = settingsColorScheme
        self.settingsFontSize = settingsFontSize
        self.settingsShowConsensus = settingsShowConsensus
        self.settingsHighContrast = settingsHighContrast
        self.settingsFocusDim = settingsFocusDim
        self.settingsDone = settingsDone
        self.renameTitle = renameTitle
        self.renamePlaceholder = renamePlaceholder
        self.renameConfirm = renameConfirm
        self.moveTitle = moveTitle
        self.moveCount = moveCount
        self.moveFrom = moveFrom
        self.moveTo = moveTo
        self.moveConfirm = moveConfirm
        self.alignerTitle = alignerTitle
        self.alignerDesc = alignerDesc
        self.alignerLabel = alignerLabel
        self.alignerPlaceholder = alignerPlaceholder
        self.alignerExample = alignerExample
        self.alignerRunning = alignerRunning
        self.alignerRun = alignerRun
        self.alignerTerminate = alignerTerminate
        self.alignerTimeout = alignerTimeout
        self.alignerCancelled = alignerCancelled
        self.alignerFailCode = alignerFailCode
        self.alignerFailRead = alignerFailRead
        self.alignerFailExec = alignerFailExec
        self.alignerTempWriteFail = alignerTempWriteFail
        self.alignerNotFound = alignerNotFound
        self.alignerEnterCmd = alignerEnterCmd
        self.primerTitle = primerTitle
        self.primerSeqA = primerSeqA
        self.primerSeqB = primerSeqB
        self.primerPlaceholderA = primerPlaceholderA
        self.primerPlaceholderB = primerPlaceholderB
        self.primerFromSel = primerFromSel
        self.primerCalcTm = primerCalcTm
        self.primerCalcGC = primerCalcGC
        self.primerSelfDimer = primerSelfDimer
        self.primerHeteroDimer = primerHeteroDimer
        self.primerResultPlaceholder = primerResultPlaceholder
        self.primerTmLabel = primerTmLabel
        self.primerTmRange = primerTmRange
        self.primerParams = primerParams
        self.primerNa = primerNa
        self.primerMg = primerMg
        self.primerOligo = primerOligo
        self.primerGC = primerGC
        self.primerSelfDimerTitle = primerSelfDimerTitle
        self.primerHeteroTitle = primerHeteroTitle
        self.primerDG = primerDG
        self.primerSeq = primerSeq
        self.primerSeqALbl = primerSeqALbl
        self.primerSeqBLbl = primerSeqBLbl
        self.primerWarnDimer = primerWarnDimer
        self.primerSafeDimer = primerSafeDimer
        self.primerCalcFail = primerCalcFail
        self.primerError = primerError
        self.primerNeedSeqA = primerNeedSeqA
        self.primerNeedSeqB = primerNeedSeqB
        self.translateTitle = translateTitle
        self.translateCodeTable = translateCodeTable
        self.translateFrame = translateFrame
        self.translateMode = translateMode
        self.translateModeCodon = translateModeCodon
        self.translateModeAA = translateModeAA
        self.translateModeBoth = translateModeBoth
        self.translateModeIgnoreGaps = translateModeIgnoreGaps
        self.translateNewWindow = translateNewWindow
        self.translateBtn = translateBtn
        self.unsavedTitle = unsavedTitle
        self.unsavedDesc = unsavedDesc
        self.unsavedSave = unsavedSave
        self.unsavedDontSave = unsavedDontSave
        self.cmdPaletteTitle = cmdPaletteTitle
        self.cmdPalettePlaceholder = cmdPalettePlaceholder
        self.cmdPaletteNoMatch = cmdPaletteNoMatch
        self.legendTitle = legendTitle
        self.legendCanvasOps = legendCanvasOps
        self.legendOp1 = legendOp1
        self.legendOp2 = legendOp2
        self.legendOp3 = legendOp3
        self.legendOp4 = legendOp4
        self.legendOp5 = legendOp5
        self.legendOp6 = legendOp6
        self.legendDarkNote = legendDarkNote
        self.menuNewTab = menuNewTab
        self.menuNewWindow = menuNewWindow
        self.menuOpen = menuOpen
        self.menuCloseWindow = menuCloseWindow
        self.menuCloseTab = menuCloseTab
        self.menuOpenRecent = menuOpenRecent
        self.menuNoRecent = menuNoRecent
        self.menuSave = menuSave
        self.menuSaveAs = menuSaveAs
        self.menuExportPNG = menuExportPNG
        self.menuExportPDF = menuExportPDF
        self.menuExportSVG = menuExportSVG
        self.menuUndo = menuUndo
        self.menuRedo = menuRedo
        self.menuCut = menuCut
        self.menuCopy = menuCopy
        self.menuPaste = menuPaste
        self.menuSelectAll = menuSelectAll
        self.menuRevComp = menuRevComp
        self.menuInsertGap = menuInsertGap
        self.menuDeleteSeq = menuDeleteSeq
        self.menuMoveSeq = menuMoveSeq
        self.menuRenameSeq = menuRenameSeq
        self.menuView = menuView
        self.menuTools = menuTools
        self.menuAppearance = menuAppearance
        self.menuLanguage = menuLanguage
        self.menuSettings = menuSettings
        self.menuHelp = menuHelp
        self.menuGuide = menuGuide
        self.menuLoadExample = menuLoadExample
        self.menuAbout = menuAbout
        self.menuRunAlign = menuRunAlign
        self.menuTranslate = menuTranslate
        self.menuPrimer = menuPrimer
        self.menuQuality = menuQuality
        self.menuSearch = menuSearch
        self.menuFindNext = menuFindNext
        self.menuFindPrev = menuFindPrev
        self.menuCmdPalette = menuCmdPalette
        self.menuExport = menuExport
        self.menuZoom = menuZoom
        self.menuLight = menuLight
        self.menuDark = menuDark
        self.menuFollowSystem = menuFollowSystem
        self.menuChinese = menuChinese
        self.menuEnglish = menuEnglish
        self.menuToggleConsensus = menuToggleConsensus
        self.toastSaved = toastSaved
        self.toastExported = toastExported
        self.toastClipboardEmpty = toastClipboardEmpty
        self.toastCopied = toastCopied
        self.toastPasted = toastPasted
        self.toastUndo = toastUndo
        self.toastRedo = toastRedo
        self.toastReplaceTranslated = toastReplaceTranslated
        self.toastFirstRun = toastFirstRun
        self.loadingText = loadingText
        self.loadingCancel = loadingCancel
        self.errorSaveFail = errorSaveFail
        self.errorExportFail = errorExportFail
        self.errorRegexInvalid = errorRegexInvalid
        self.errorClipboardUnrecognized = errorClipboardUnrecognized
        self.quitTitle = quitTitle
        self.quitSingleDesc = quitSingleDesc
        self.quitMultiDesc = quitMultiDesc
        self.quitSaveExit = quitSaveExit
        self.windowTitleUnnamed = windowTitleUnnamed
        self.windowTitlePrefix = windowTitlePrefix
        self.alignerPresetMafft = alignerPresetMafft
        self.alignerPresetMuscle = alignerPresetMuscle
        self.alignerPresetClustal = alignerPresetClustal
        self.alignerPresetCustom = alignerPresetCustom
        self.cmdOpen = cmdOpen
        self.cmdSave = cmdSave
        self.cmdSaveAs = cmdSaveAs
        self.cmdRunAlign = cmdRunAlign
        self.cmdTranslate = cmdTranslate
        self.cmdPrimer = cmdPrimer
        self.cmdQuality = cmdQuality
        self.cmdSearch = cmdSearch
        self.cmdCopy = cmdCopy
        self.cmdSelectAll = cmdSelectAll
        self.cmdRevComp = cmdRevComp
        self.cmdInsertGap = cmdInsertGap
        self.cmdDeleteSeq = cmdDeleteSeq
        self.cmdMoveSeq = cmdMoveSeq
        self.cmdRenameSeq = cmdRenameSeq
        self.cmdSchemeMinimal = cmdSchemeMinimal
        self.cmdSchemeClustalX = cmdSchemeClustalX
        self.cmdSchemeZappo = cmdSchemeZappo
        self.cmdSchemeSeaView = cmdSchemeSeaView
        self.cmdSchemeDefault = cmdSchemeDefault
        self.cmdSchemeTransitionTransversion = cmdSchemeTransitionTransversion
        self.cmdZoomIn = cmdZoomIn
        self.cmdZoomOut = cmdZoomOut
        self.cmdZoomReset = cmdZoomReset
        self.cmdToggleConsensus = cmdToggleConsensus
        self.cmdThemeLight = cmdThemeLight
        self.cmdThemeDark = cmdThemeDark
        self.cmdThemeSystem = cmdThemeSystem
        self.cmdSettings = cmdSettings
        self.cmdGuide = cmdGuide
        self.cmdLoadExample = cmdLoadExample
        self.cmdAbout = cmdAbout
        self.cmdAddSeq = cmdAddSeq
        self.cmdBatchReplace = cmdBatchReplace
        self.cmdReplaceAlignment = cmdReplaceAlignment
        self.cmdTransaction = cmdTransaction
        self.schemeOkabeIto = schemeOkabeIto
        self.fastqQuality = fastqQuality
        self.fastqMeanPhred = fastqMeanPhred
        self.fastqMinPhred = fastqMinPhred
        self.fastqQ20 = fastqQ20
        self.fastqQ30 = fastqQ30
        self.statsMethodNote = statsMethodNote
        self.logoTitle = logoTitle
        self.logoHint = logoHint
        self.treeTitle = treeTitle
        self.treeHint = treeHint
        self.treeCopyNewick = treeCopyNewick
        self.windowTitle = windowTitle
        self.windowSize = windowSize
        self.annotTitle = annotTitle
        self.annotLoad = annotLoad
        self.annotLoadFailRead = annotLoadFailRead
        self.annotLoadEmpty = annotLoadEmpty
        self.annotLoaded = annotLoaded
        self.annotSeqidNotFound = annotSeqidNotFound
        self.annotNone = annotNone
        self.annotSeq = annotSeq
        self.annotType = annotType
        self.annotRange = annotRange
        self.annotName = annotName
        self.annotJump = annotJump
        self.toolbarDifference = toolbarDifference
        self.helpDifference = helpDifference
        self.toolbarLogo = toolbarLogo
        self.toolbarTree = toolbarTree
        self.toolbarWindowChart = toolbarWindowChart
        self.toolbarAnnotation = toolbarAnnotation
        self.aboutCitation = aboutCitation
        self.tooltipCloseTab = tooltipCloseTab
        self.tooltipNewTab = tooltipNewTab
        self.helpOpenFile = helpOpenFile
        self.helpSave = helpSave
        self.helpExample = helpExample
        self.helpTranslate = helpTranslate
        self.helpPrimer = helpPrimer
        self.helpQuality = helpQuality
        self.helpLegend = helpLegend
        self.helpUndo = helpUndo
        self.helpRedo = helpRedo
        self.helpExport = helpExport
        self.helpSettings = helpSettings
        self.helpCmdPalette = helpCmdPalette
        self.helpColorScheme = helpColorScheme
        self.helpZoomReset = helpZoomReset
        self.helpZoomIn = helpZoomIn
        self.helpZoomOut = helpZoomOut
        self.helpAppearance = helpAppearance
        self.helpLanguage = helpLanguage
        self.helpSearch = helpSearch
        self.helpRegexOn = helpRegexOn
        self.helpRegexOff = helpRegexOff
        self.exportOnlySelection = exportOnlySelection
        self.exportPNG = exportPNG
        self.exportPDF = exportPDF
        self.exportSVG = exportSVG
        self.exportPreviewTitle = exportPreviewTitle
        self.exportPreviewFormat = exportPreviewFormat
        self.exportPreviewSize = exportPreviewSize
        self.exportPreviewDarkMode = exportPreviewDarkMode
        self.exportPreviewExportBtn = exportPreviewExportBtn
        self.savingText = savingText
        self.exportingText = exportingText
        self.exportPreviewFailed = exportPreviewFailed
    }

    // MARK: 通用（zh/en 双表；中文界面保存/关闭弹窗不得出现小写英文 "close"/"cancel"/"unnamed"）
    let close: String
    let cancel: String
    let ok: String
    let unnamed: String
    let search: String

    // MARK: 工具栏 / 左侧栏
    let toolbarOpen: String
    let toolbarSave: String
    let toolbarExample: String
    let toolbarAlign: String
    let toolbarTranslate: String
    let toolbarPrimer: String
    let toolbarQuality: String
    let toolbarLegend: String
    let toolbarSearch: String
    let toolbarUndo: String
    let toolbarRedo: String
    let toolbarExport: String
    let toolbarSettings: String
    let toolbarCommandPalette: String
    let toolbarMore: String
    let toolbarColorScheme: String
    let toolbarZoom: String
    let toolbarZoomIn: String
    let toolbarZoomOut: String
    let toolbarZoomReset: String
    let toolbarAppearance: String
    let toolbarLanguage: String
    let toolbarNewTab: String

    // MARK: 侧栏分组标题
    let sidebarGroupFile: String
    let sidebarGroupEdit: String
    let sidebarGroupAnalysis: String
    let sidebarGroupView: String
    let sidebarGroupExport: String
    let sidebarGroupSystem: String

    // MARK: 配色方案
    let schemeMinimal: String
    let schemeClustalX: String
    let schemeZappo: String
    let schemeSeaView: String
    let schemeDefault: String
    let schemeTransitionTransversion: String

    // MARK: ClustalX 阈值
    let clustalXThreshold: String
    let clustalXThresholdHint: String

    // MARK: 右键上下文菜单
    let ctxRenameSeq: String
    let ctxDeleteSeq: String
    let ctxMoveTop: String
    let ctxMoveBottom: String
    let ctxSortBy: String
    let ctxSortByName: String
    let ctxSortBySimilarity: String
    let ctxSortByGC: String
    let ctxSortByLength: String
    let ctxSortByLengthNoGaps: String
    let ctxCopySelection: String
    let ctxColorScheme: String
    let ctxTranslate: String
    let ctxReverseComplement: String
    let ctxInsertGap: String
    let ctxPaste: String
    let ctxAddSeq: String
    let ctxRemoveAllGapCols: String
    let ctxRemoveHighGapCols: String
    let ctxGapTrimming: String
    let ctxSelectCodonPos: String
    let ctxCodonPos1: String
    let ctxCodonPos2: String
    let ctxCodonPos3: String

    // MARK: 系统发育统计
    let statsPhyloInfo: String
    let statsVariableSites: String
    let statsParsimonySites: String
    let statsSingletonSites: String
    let statsSamplingHint: String

    // MARK: 共识模式
    let consensusMode: String
    let consensusMajority: String
    let consensusIUPAC: String
    let consensusStrict: String

    // MARK: 密码子三联体
    let settingsCodonTriplet: String

    // MARK: 翻译选项增强
    let translateNameOption: String
    let translateKeepOriginal: String
    let translateAddSuffix: String
    let translateSixFrameOverview: String
    let translateHighlightStop: String
    let translateHighlightStart: String

    // MARK: 导出序列格式
    let exportSequence: String
    let exportImage: String
    let exportFASTA: String
    let exportNEXUS: String
    let exportPHYLIP: String
    let exportCLUSTAL: String
    let exportMSF: String

    // MARK: 按钮重命名
    let toolbarRunMSA: String
    let helpRunMSA: String
    let helpTranslateDisabled: String
    let helpPrimerDisabled: String

    // MARK: 空位精简
    let toastGapColsRemoved: String
    let toastHighGapColsRemoved: String

    // MARK: 排序 Toast
    let toastSortByName: String
    let toastSortBySimilarity: String
    let toastSortByGC: String
    let toastSortByLength: String
    let toastSortByLengthNoGaps: String
    let toastReverseComplement: String

    // MARK: 搜索
    let searchPlaceholderContent: String
    let searchPlaceholderContentRegex: String
    let searchPlaceholderName: String
    let searchPlaceholderNameRegex: String
    let searchFind: String
    let searchPrev: String
    let searchNext: String
    let searchNoMatch: String
    let searchComputing: String
    let searchClose: String
    let searchScopeContent: String
    let searchScopeName: String
    let searchOptions: String
    let searchRegex: String
    let searchRegexOn: String
    let searchRegexOff: String

    // MARK: 状态栏
    let statusSeqCount: String
    let statusColCount: String
    let statusPosition: String
    let statusResidue: String
    let statusIdentity: String
    let statusType: String
    let statusCharset: String
    let statusNucleic: String
    let statusAmino: String
    let statusNoFile: String

    // MARK: 统计面板
    let statsTitle: String
    let statsOverview: String
    let statsFile: String
    let statsFormat: String
    let statsSeqCount: String
    let statsColCount: String
    let statsType: String
    let statsQuality: String
    let statsMeanPairwise: String
    let statsMeanColIdentity: String
    let statsMinColIdentity: String
    let statsMaxColIdentity: String
    let statsGapCols: String
    let statsTotalCols: String
    let statsConservation: String
    let statsHighConserved: String
    let statsConservationHint: String
    let statsConsensus: String
    let statsConsensusCopy: String
    let statsConsensusCopied: String
    let statsCursor: String
    let statsEmptyTitle: String
    let statsEmptyDesc: String
    let statsNoData: String
    let statsComputing: String

    // MARK: 空状态
    let emptyTitle: String
    let emptyDesc1: String
    let emptyDesc2: String
    let emptyOpenFile: String
    let emptyLoadExample: String

    // MARK: 弹窗
    let aboutTitle: String
    let aboutVersion: String
    let aboutDesc: String
    let aboutFeatures: String
    let aboutRefs: String
    let aboutLicense: String

    let guideTitle: String
    let guideStart: String

    let qualityTitle: String
    let qualityNoFile: String
    let qualityCharset: String

    let settingsTitle: String
    let settingsAppearance: String
    let settingsLight: String
    let settingsDark: String
    let settingsSystem: String
    let settingsColorScheme: String
    let settingsFontSize: String
    let settingsShowConsensus: String
    let settingsHighContrast: String
    let settingsFocusDim: String
    let settingsDone: String

    let renameTitle: String
    let renamePlaceholder: String
    let renameConfirm: String

    let moveTitle: String
    let moveCount: String
    let moveFrom: String
    let moveTo: String
    let moveConfirm: String

    let alignerTitle: String
    let alignerDesc: String
    let alignerLabel: String
    let alignerPlaceholder: String
    let alignerExample: String
    let alignerRunning: String
    let alignerRun: String
    let alignerTerminate: String
    let alignerTimeout: String
    let alignerCancelled: String
    let alignerFailCode: String
    let alignerFailRead: String
    let alignerFailExec: String
    let alignerTempWriteFail: String
    let alignerNotFound: String
    let alignerEnterCmd: String

    let primerTitle: String
    let primerSeqA: String
    let primerSeqB: String
    let primerPlaceholderA: String
    let primerPlaceholderB: String
    let primerFromSel: String
    let primerCalcTm: String
    let primerCalcGC: String
    let primerSelfDimer: String
    let primerHeteroDimer: String
    let primerResultPlaceholder: String
    let primerTmLabel: String
    let primerTmRange: String
    let primerParams: String
    let primerNa: String
    let primerMg: String
    let primerOligo: String
    let primerGC: String
    let primerSelfDimerTitle: String
    let primerHeteroTitle: String
    let primerDG: String
    let primerSeq: String
    let primerSeqALbl: String
    let primerSeqBLbl: String
    let primerWarnDimer: String
    let primerSafeDimer: String
    let primerCalcFail: String
    let primerError: String
    let primerNeedSeqA: String
    let primerNeedSeqB: String

    let translateTitle: String
    let translateCodeTable: String
    let translateFrame: String
    let translateMode: String
    let translateModeCodon: String
    let translateModeAA: String
    let translateModeBoth: String
    let translateModeIgnoreGaps: String
    let translateNewWindow: String
    let translateBtn: String

    let unsavedTitle: String
    let unsavedDesc: String
    let unsavedSave: String
    let unsavedDontSave: String

    let cmdPaletteTitle: String
    let cmdPalettePlaceholder: String
    let cmdPaletteNoMatch: String

    let legendTitle: String
    let legendCanvasOps: String
    let legendOp1: String
    let legendOp2: String
    let legendOp3: String
    let legendOp4: String
    let legendOp5: String
    let legendOp6: String
    let legendDarkNote: String

    // MARK: 菜单
    let menuNewTab: String
    let menuNewWindow: String
    let menuOpen: String
    let menuCloseWindow: String
    let menuCloseTab: String
    let menuOpenRecent: String
    let menuNoRecent: String
    let menuSave: String
    let menuSaveAs: String
    let menuExportPNG: String
    let menuExportPDF: String
    let menuExportSVG: String
    let menuUndo: String
    let menuRedo: String
    let menuCut: String
    let menuCopy: String
    let menuPaste: String
    let menuSelectAll: String
    let menuRevComp: String
    let menuInsertGap: String
    let menuDeleteSeq: String
    let menuMoveSeq: String
    let menuRenameSeq: String
    let menuView: String
    let menuTools: String
    let menuAppearance: String
    let menuLanguage: String
    let menuSettings: String
    let menuHelp: String
    let menuGuide: String
    let menuLoadExample: String
    let menuAbout: String
    let menuRunAlign: String
    let menuTranslate: String
    let menuPrimer: String
    let menuQuality: String
    let menuSearch: String
    let menuFindNext: String
    let menuFindPrev: String
    let menuCmdPalette: String
    let menuExport: String
    let menuZoom: String
    let menuLight: String
    let menuDark: String
    let menuFollowSystem: String
    let menuChinese: String
    let menuEnglish: String
    let menuToggleConsensus: String

    // MARK: Toast
    let toastSaved: String
    let toastExported: String
    let toastClipboardEmpty: String
    let toastCopied: String
    let toastPasted: String
    let toastUndo: String
    let toastRedo: String
    let toastReplaceTranslated: String
    let toastFirstRun: String

    // MARK: 加载/错误
    let loadingText: String
    let loadingCancel: String
    let errorSaveFail: String
    let errorExportFail: String
    let errorRegexInvalid: String
    let errorClipboardUnrecognized: String

    // MARK: 退出守卫
    let quitTitle: String
    let quitSingleDesc: String
    let quitMultiDesc: String
    let quitSaveExit: String

    // MARK: 窗口标题
    let windowTitleUnnamed: String
    let windowTitlePrefix: String

    // MARK: 外部比对器预设
    let alignerPresetMafft: String
    let alignerPresetMuscle: String
    let alignerPresetClustal: String
    let alignerPresetCustom: String

    // MARK: 图例操作
    let cmdOpen: String
    let cmdSave: String
    let cmdSaveAs: String
    let cmdRunAlign: String
    let cmdTranslate: String
    let cmdPrimer: String
    let cmdQuality: String
    let cmdSearch: String
    let cmdCopy: String
    let cmdSelectAll: String
    let cmdRevComp: String
    let cmdInsertGap: String
    let cmdDeleteSeq: String
    let cmdMoveSeq: String
    let cmdRenameSeq: String
    let cmdSchemeMinimal: String
    let cmdSchemeClustalX: String
    let cmdSchemeZappo: String
    let cmdSchemeSeaView: String
    let cmdSchemeDefault: String
    let cmdSchemeTransitionTransversion: String
    let cmdZoomIn: String
    let cmdZoomOut: String
    let cmdZoomReset: String
    let cmdToggleConsensus: String
    let cmdThemeLight: String
    let cmdThemeDark: String
    let cmdThemeSystem: String
    let cmdSettings: String
    let cmdGuide: String
    let cmdLoadExample: String
    let cmdAbout: String
    // 撤销/重做 Toast 用的命令描述（核心库 EditCommand 无法访问本地化，由 App 层映射）
    let cmdAddSeq: String
    let cmdBatchReplace: String
    let cmdReplaceAlignment: String
    let cmdTransaction: String

    // MARK: 新分析工具 / 质量 / 差异 / 注释 / CLI / 引用
    let schemeOkabeIto: String
    let fastqQuality: String
    let fastqMeanPhred: String
    let fastqMinPhred: String
    let fastqQ20: String
    let fastqQ30: String
    let statsMethodNote: String
    let logoTitle: String
    let logoHint: String
    let treeTitle: String
    let treeHint: String
    let treeCopyNewick: String
    let windowTitle: String
    let windowSize: String
    let annotTitle: String
    let annotLoad: String
    let annotLoadFailRead: String
    let annotLoadEmpty: String
    let annotLoaded: String
    let annotSeqidNotFound: String
    let annotNone: String
    let annotSeq: String
    let annotType: String
    let annotRange: String
    let annotName: String
    let annotJump: String
    let toolbarDifference: String
    let helpDifference: String
    let toolbarLogo: String
    let toolbarTree: String
    let toolbarWindowChart: String
    let toolbarAnnotation: String
    let aboutCitation: String

    // MARK: Tooltip
    let tooltipCloseTab: String
    let tooltipNewTab: String

    // MARK: 帮助说明
    let helpOpenFile: String
    let helpSave: String
    let helpExample: String
    let helpTranslate: String
    let helpPrimer: String
    let helpQuality: String
    let helpLegend: String
    let helpUndo: String
    let helpRedo: String
    let helpExport: String
    let helpSettings: String
    let helpCmdPalette: String
    let helpColorScheme: String
    let helpZoomReset: String
    let helpZoomIn: String
    let helpZoomOut: String
    let helpAppearance: String
    let helpLanguage: String
    let helpSearch: String
    let helpRegexOn: String
    let helpRegexOff: String

    // MARK: 导出
    let exportOnlySelection: String
    let exportPNG: String
    let exportPDF: String
    let exportSVG: String
    let exportPreviewTitle: String
    let exportPreviewFormat: String
    let exportPreviewSize: String
    let exportPreviewDarkMode: String
    let exportPreviewExportBtn: String

    // MARK: 保存/导出进行时（后台化期间的状态提示）
    let savingText: String
    let exportingText: String
    let exportPreviewFailed: String

    static let zh = AppStrings(
        close: "关闭", cancel: "取消", ok: "确定", unnamed: "未命名", search: "搜索",
        toolbarOpen: "打开", toolbarSave: "保存", toolbarExample: "载入示例",
        toolbarAlign: "比对", toolbarTranslate: "翻译", toolbarPrimer: "引物计算",
        toolbarQuality: "比对质量", toolbarLegend: "图例", toolbarSearch: "搜索", toolbarUndo: "撤销", toolbarRedo: "重做",
        toolbarExport: "导出", toolbarSettings: "设置", toolbarCommandPalette: "命令面板",
        toolbarMore: "更多", toolbarColorScheme: "配色", toolbarZoom: "缩放",
        toolbarZoomIn: "放大", toolbarZoomOut: "缩小", toolbarZoomReset: "重置缩放",
        toolbarAppearance: "外观", toolbarLanguage: "语言", toolbarNewTab: "新建标签页",
        sidebarGroupFile: "文件", sidebarGroupEdit: "编辑", sidebarGroupAnalysis: "分析",
        sidebarGroupView: "显示", sidebarGroupExport: "导出", sidebarGroupSystem: "系统",
        schemeMinimal: "极简", schemeClustalX: "ClustalX", schemeZappo: "Zappo",
        schemeSeaView: "SeaView", schemeDefault: "默认",
        schemeTransitionTransversion: "过渡/颠换",
        clustalXThreshold: "保守度阈值", clustalXThresholdHint: "低于此阈值的列不着色",
        ctxRenameSeq: "重命名序列", ctxDeleteSeq: "删除序列",
        ctxMoveTop: "移动到顶部", ctxMoveBottom: "移动到底部",
        ctxSortBy: "排序方式", ctxSortByName: "按名称排序",
        ctxSortBySimilarity: "按与共识相似度排序", ctxSortByGC: "按 GC 含量排序",
        ctxSortByLength: "按序列长度排序（含空位）", ctxSortByLengthNoGaps: "按序列长度排序（不含空位）",
        ctxCopySelection: "复制选中区域", ctxColorScheme: "配色方案",
        ctxTranslate: "翻译…", ctxReverseComplement: "反向互补",
        ctxInsertGap: "插入空位", ctxPaste: "粘贴", ctxAddSeq: "添加序列…",
        ctxRemoveAllGapCols: "去除全空位列", ctxRemoveHighGapCols: "去除空位富集列 (>50%)",
        ctxGapTrimming: "空位精简",
        ctxSelectCodonPos: "选择密码子位", ctxCodonPos1: "第 1 位",
        ctxCodonPos2: "第 2 位", ctxCodonPos3: "第 3 位",
        statsPhyloInfo: "系统发育信息量", statsVariableSites: "变异位点数",
        statsParsimonySites: "简约信息位点数", statsSingletonSites: "单态位点数",
        statsSamplingHint: "序列数 >200，已采样 200 条近似计算",
        consensusMode: "共识模式", consensusMajority: "多数规则",
        consensusIUPAC: "IUPAC 简并", consensusStrict: "严格共识",
        settingsCodonTriplet: "密码子三联体显示（每 3 列分组）",
        translateNameOption: "序列名处理:", translateKeepOriginal: "保留原名",
        translateAddSuffix: "加 _AA 后缀", translateSixFrameOverview: "六阅读框概览",
        translateHighlightStop: "高亮终止密码子", translateHighlightStart: "高亮起始密码子",
        exportSequence: "序列", exportImage: "图像",
        exportFASTA: "FASTA", exportNEXUS: "NEXUS", exportPHYLIP: "PHYLIP",
        exportCLUSTAL: "CLUSTAL", exportMSF: "MSF",
        toolbarRunMSA: "对齐", helpRunMSA: "调用外部比对器对未比对序列进行多重比对 (Cmd+Shift+B)",
        helpTranslateDisabled: "仅适用于核酸序列", helpPrimerDisabled: "仅适用于核酸序列",
        toastGapColsRemoved: "已去除全空位列", toastHighGapColsRemoved: "已去除高空位列 (>50%)",
        toastSortByName: "已按名称排序", toastSortBySimilarity: "已按相似度排序",
        toastSortByGC: "已按 GC 含量排序", toastSortByLength: "已按长度排序",
        toastSortByLengthNoGaps: "已按无空位长度排序", toastReverseComplement: "已反向互补",
        searchPlaceholderContent: "搜索残基或简并模式",
        searchPlaceholderContentRegex: "残基正则表达式",
        searchPlaceholderName: "搜索序列名称",
        searchPlaceholderNameRegex: "名称正则表达式",
        searchFind: "查找", searchPrev: "上一处", searchNext: "下一处",
        searchNoMatch: "无匹配", searchComputing: "检索中", searchClose: "关闭搜索",
        searchScopeContent: "残基", searchScopeName: "名称", searchOptions: "搜索选项",
        searchRegex: "正则表达式", searchRegexOn: "正则模式已开启",
        searchRegexOff: "开启正则模式",
        statusSeqCount: "序列数", statusColCount: "列数", statusPosition: "位置",
        statusResidue: "残基", statusIdentity: "一致度", statusType: "类型",
        statusCharset: "字符集",
        statusNucleic: "核酸", statusAmino: "蛋白", statusNoFile: "未打开文件",
        statsTitle: "统计", statsOverview: "概览", statsFile: "文件", statsFormat: "格式",
        statsSeqCount: "序列数", statsColCount: "列数", statsType: "类型",
        statsQuality: "一致度", statsMeanPairwise: "位点加权一致度",
        statsMeanColIdentity: "平均列一致度", statsMinColIdentity: "最低列一致度",
        statsMaxColIdentity: "最高列一致度", statsGapCols: "含空位列",
        statsTotalCols: "总列数", statsConservation: "保守度分布",
        statsHighConserved: "高保守列 ≥80%", statsConservationHint: "每列一致度五档分布，灰阶越深保守度越高",
        statsConsensus: "共识序列", statsConsensusCopy: "复制共识序列", statsConsensusCopied: "共识序列已复制", statsCursor: "光标",
        statsEmptyTitle: "未打开比对", statsEmptyDesc: "",
        statsNoData: "无数据", statsComputing: "计算中",
        emptyTitle: "打开序列文件",
        emptyDesc1: "支持 FASTA、NEXUS、PHYLIP、CLUSTAL、MSF、Stockholm 与 FASTQ",
        emptyDesc2: "未比对序列可通过「运行比对」调用本机 MAFFT 或 MUSCLE",
        emptyOpenFile: "打开文件", emptyLoadExample: "载入示例",
        aboutTitle: "SeqAlignMac", aboutVersion: "版本 0.1.0",
        aboutDesc: "多序列比对查看与编辑",
        aboutFeatures: "导入与导出 7 种格式，支持配色、六框翻译、引物 Tm、检索、撤销重做与矢量导出",
        aboutRefs: "Tm 计算依据 SantaLucia 1998；密码子表来自 NCBI",
        aboutLicense: "MIT 许可证",
        guideTitle: "新手向导", guideStart: "开始",
        qualityTitle: "比对质量", qualityNoFile: "未打开比对文件", qualityCharset: "NEXUS 字符集",
        settingsTitle: "偏好设置", settingsAppearance: "外观",
        settingsLight: "浅色", settingsDark: "深色", settingsSystem: "跟随系统",
        settingsColorScheme: "默认配色", settingsFontSize: "默认字号",
        settingsShowConsensus: "显示共识序列",
        settingsHighContrast: "高对比模式",
        settingsFocusDim: "聚焦变暗", settingsDone: "完成",
        renameTitle: "重命名序列", renamePlaceholder: "新名称", renameConfirm: "确定",
        moveTitle: "移动序列", moveCount: "共", moveFrom: "从：", moveTo: "到：", moveConfirm: "确定",
        alignerTitle: "外部比对器",
        alignerDesc: "调用本机 MAFFT、MUSCLE 或 ClustalW，结果在新窗口打开",
        alignerLabel: "命令", alignerPlaceholder: "命令或完整路径",
        alignerExample: "%1$@ 输入文件，%2$@ 输出文件",
        alignerRunning: "比对中，超过 5 分钟将自动终止",
        alignerRun: "运行", alignerTerminate: "终止",
        alignerTimeout: "比对超时（5 分钟），已终止。请减少序列数或长度后重试。",
        alignerCancelled: "已取消比对。",
        alignerFailCode: "比对失败（退出码",
        alignerFailRead: "比对完成，但无法读取结果文件。",
        alignerFailExec: "外部比对器执行失败：",
        alignerTempWriteFail: "无法写入临时输入文件：",
        alignerNotFound: "未找到比对器：",
        alignerEnterCmd: "请输入比对器命令或完整路径",
        primerTitle: "引物计算", primerSeqA: "序列 A", primerSeqB: "序列 B",
        primerPlaceholderA: "正向引物，如 ATGCTAGCTAGCTAGCTAGC", primerPlaceholderB: "可选，用于异源二聚体检查",
        primerFromSel: "从选区填入", primerCalcTm: "计算", primerCalcGC: "GC 含量",
        primerSelfDimer: "自身二聚体", primerHeteroDimer: "异源二聚体",
        primerResultPlaceholder: "输入引物后计算",
        primerTmLabel: "最近邻法（SantaLucia 1998）",
        primerTmRange: "Tm 范围", primerParams: "条件",
        primerNa: "Na⁺", primerMg: "Mg²⁺", primerOligo: "引物浓度",
        primerGC: "GC 含量", primerSelfDimerTitle: "自身二聚体",
        primerHeteroTitle: "异源二聚体", primerDG: "ΔG", primerSeq: "序列",
        primerSeqALbl: "序列 A", primerSeqBLbl: "序列 B",
        primerWarnDimer: "二聚体倾向显著", primerSafeDimer: "无显著二聚体",
        primerCalcFail: "计算失败", primerError: "错误",
        primerNeedSeqA: "请输入序列 A", primerNeedSeqB: "请输入序列 B",
        translateTitle: "翻译", translateCodeTable: "遗传密码表",
        translateFrame: "阅读框", translateMode: "显示",
        translateModeCodon: "密码子", translateModeAA: "氨基酸",
        translateModeBoth: "密码子与氨基酸", translateModeIgnoreGaps: "忽略空位",
        translateNewWindow: "在新窗口打开",
        translateBtn: "翻译",
        unsavedTitle: "未保存的更改",
        unsavedDesc: "有未保存的编辑，是否保存？",
        unsavedSave: "保存", unsavedDontSave: "不保存",
        cmdPaletteTitle: "命令面板", cmdPalettePlaceholder: "输入命令或快捷键…",
        cmdPaletteNoMatch: "无匹配命令",
        legendTitle: "图例", legendCanvasOps: "画布操作",
        legendOp1: "拖动名称列右侧分隔线，调整名称列宽度",
        legendOp2: "点击或拖动顶部保守度轨道，跳转到对应列",
        legendOp3: "Option 拖拽框选列块；Option 加方向键从锚点扩展选区",
        legendOp4: "⌘ 滚轮或捏合缩放；方向键移动光标；Esc 清除选区",
        legendOp5: "⌘A 全选，⌘C 复制选中区域",
        legendOp6: "右键数据区，打开编辑与配色菜单",
        legendDarkNote: "深色外观下数据色板自动反相，类别对应关系不变。",
        menuNewTab: "新建标签页", menuNewWindow: "新建窗口", menuOpen: "打开文件…",
        menuCloseWindow: "关闭窗口", menuCloseTab: "关闭标签页", menuOpenRecent: "打开最近", menuNoRecent: "无最近文件",
        menuSave: "保存", menuSaveAs: "另存为…",
        menuExportPNG: "导出为 PNG", menuExportPDF: "导出为 PDF", menuExportSVG: "导出为 SVG",
        menuUndo: "撤销", menuRedo: "重做", menuCut: "剪切", menuCopy: "复制",
        menuPaste: "粘贴", menuSelectAll: "全选", menuRevComp: "反向互补",
        menuInsertGap: "插入空位", menuDeleteSeq: "删除选中序列",
        menuMoveSeq: "移动序列", menuRenameSeq: "重命名序列",
        menuView: "视图", menuTools: "工具", menuAppearance: "外观", menuLanguage: "语言",
        menuSettings: "偏好设置…", menuHelp: "帮助", menuGuide: "新手向导",
        menuLoadExample: "载入示例", menuAbout: "关于 SeqAlignMac",
        menuRunAlign: "运行比对", menuTranslate: "翻译", menuPrimer: "引物计算",
        menuQuality: "比对质量", menuSearch: "搜索", menuFindNext: "查找下一处",
        menuFindPrev: "查找上一处", menuCmdPalette: "命令面板",
        menuExport: "导出", menuZoom: "缩放",
        menuLight: "浅色", menuDark: "深色", menuFollowSystem: "跟随系统",
        menuChinese: "中文", menuEnglish: "English", menuToggleConsensus: "显示/隐藏共识序列",
        toastSaved: "已保存", toastExported: "已导出", toastClipboardEmpty: "剪贴板为空",
        toastCopied: "已复制", toastPasted: "粘贴", toastUndo: "撤销", toastRedo: "重做",
        toastReplaceTranslated: "已替换为翻译结果，⌘Z 可撤销",
        toastFirstRun: "提示：拖动名称列分隔线可调整宽度，点击顶部轨道可跳转列",
        loadingText: "正在解析文件…", loadingCancel: "取消",
        errorSaveFail: "保存失败：", errorExportFail: "导出失败：",
        errorRegexInvalid: "正则表达式无效：",
        errorClipboardUnrecognized: "无法识别剪贴板内容：请粘贴 FASTA 或纯序列",
        quitTitle: "有未保存的更改", quitSingleDesc: "有未保存的编辑。",
        quitMultiDesc: " 个窗口有未保存的编辑。", quitSaveExit: "保存并退出",
        windowTitleUnnamed: "SeqAlignMac（未命名）", windowTitlePrefix: "SeqAlignMac",
        alignerPresetMafft: "MAFFT", alignerPresetMuscle: "MUSCLE",
        alignerPresetClustal: "ClustalW", alignerPresetCustom: "自定义",
        cmdOpen: "打开文件…", cmdSave: "保存", cmdSaveAs: "另存为…",
        cmdRunAlign: "运行比对", cmdTranslate: "翻译",
        cmdPrimer: "引物计算", cmdQuality: "比对质量", cmdSearch: "搜索",
        cmdCopy: "复制选中区域", cmdSelectAll: "全选", cmdRevComp: "反向互补",
        cmdInsertGap: "插入空位", cmdDeleteSeq: "删除选中序列", cmdMoveSeq: "移动序列",
        cmdRenameSeq: "重命名序列", cmdSchemeMinimal: "配色：极简",
        cmdSchemeClustalX: "配色：ClustalX", cmdSchemeZappo: "配色：Zappo",
        cmdSchemeSeaView: "配色：SeaView",
        cmdSchemeDefault: "配色：默认",
        cmdSchemeTransitionTransversion: "配色：过渡/颠换",
        cmdZoomIn: "缩放：放大", cmdZoomOut: "缩放：缩小", cmdZoomReset: "缩放：重置",
        cmdToggleConsensus: "显示/隐藏共识序列",
        cmdThemeLight: "主题：浅色", cmdThemeDark: "主题：深色",
        cmdThemeSystem: "主题：跟随系统",
        cmdSettings: "偏好设置…", cmdGuide: "新手向导", cmdLoadExample: "载入示例",
        cmdAbout: "关于 SeqAlignMac",
        cmdAddSeq: "添加序列", cmdBatchReplace: "批量替换", cmdReplaceAlignment: "替换比对",
        cmdTransaction: "事务（%d 步）",
        schemeOkabeIto: "Okabe-Ito（色觉无障碍）",
        fastqQuality: "测序质量", fastqMeanPhred: "平均 Phred", fastqMinPhred: "最低 Phred",
        fastqQ20: "≥Q20 碱基占比", fastqQ30: "≥Q30 碱基占比",
        statsMethodNote: "列一致度按主频残基占比计算，空位不计。",
        logoTitle: "序列 Logo", logoHint: "字母高度表示该残基占比与列信息量的乘积，空位不计。",
        treeTitle: "NJ 系统发育树", treeHint: "Neighbor-Joining，未校正 p-distance；序列数超过 200 时等距抽取。",
        treeCopyNewick: "复制 Newick",
        windowTitle: "滑动窗口一致度", windowSize: "窗口宽度",
        annotTitle: "注释", annotLoad: "导入 GFF3",
        annotLoadFailRead: "无法读取注释文件。",
        annotLoadEmpty: "注释文件解析结果为空（格式错误或无特征）。",
        annotLoaded: "已导入",
        annotSeqidNotFound: "比对内未找到序列：", annotNone: "尚未导入注释文件",
        annotSeq: "序列", annotType: "类型", annotRange: "列范围", annotName: "名称", annotJump: "跳转",
        toolbarDifference: "差异", helpDifference: "与光标行相同的残基淡化显示",
        toolbarLogo: "序列 Logo", toolbarTree: "NJ 树", toolbarWindowChart: "滑动窗口", toolbarAnnotation: "注释浏览",
        aboutCitation: "引用（BibTeX）",
        tooltipCloseTab: "关闭", tooltipNewTab: "新建标签页 (⌘T)",
        helpOpenFile: "打开文件 (⌘O)", helpSave: "保存 (⌘S)",
        helpExample: "载入示例",
        helpTranslate: "翻译 (⇧⌘T)", helpPrimer: "引物计算",
        helpQuality: "比对质量", helpLegend: "图例",
        helpUndo: "撤销 (⌘Z)", helpRedo: "重做 (⇧⌘Z)",
        helpExport: "导出为 PNG / PDF / SVG", helpSettings: "偏好设置 (⌘,)",
        helpCmdPalette: "命令面板 (⇧⌘P)",
        helpColorScheme: "配色 (⇧⌘1/2/3/4)",
        helpZoomReset: "当前缩放比例，点击重置 (⇧⌘0)",
        helpZoomIn: "放大 (⌘+ 或 ⌘滚轮)", helpZoomOut: "缩小 (⌘- 或 ⌘滚轮)",
        helpAppearance: "外观", helpLanguage: "语言",
        helpSearch: "搜索 (⌘F)",
        helpRegexOn: "正则模式已开启",
        helpRegexOff: "开启正则模式",
        exportOnlySelection: "仅导出选中区域",
        exportPNG: "导出为 PNG", exportPDF: "导出为 PDF", exportSVG: "导出为 SVG",
        exportPreviewTitle: "导出预览", exportPreviewFormat: "格式",
        exportPreviewSize: "预估尺寸", exportPreviewDarkMode: "深色模式导出",
        exportPreviewExportBtn: "导出…",
        savingText: "保存中…",
        exportingText: "正在导出…",
        exportPreviewFailed: "预览无法生成（比对过大或渲染失败）"
    )

    static let en = AppStrings(
        close: "Close", cancel: "Cancel", ok: "OK", unnamed: "Unnamed", search: "Search",
        toolbarOpen: "Open", toolbarSave: "Save", toolbarExample: "Load Example",
        toolbarAlign: "Align", toolbarTranslate: "Translate", toolbarPrimer: "Primer",
        toolbarQuality: "Quality", toolbarLegend: "Legend", toolbarSearch: "Search", toolbarUndo: "Undo", toolbarRedo: "Redo",
        toolbarExport: "Export", toolbarSettings: "Settings", toolbarCommandPalette: "Command Palette",
        toolbarMore: "More", toolbarColorScheme: "Colors", toolbarZoom: "Zoom",
        toolbarZoomIn: "Zoom In", toolbarZoomOut: "Zoom Out", toolbarZoomReset: "Reset Zoom",
        toolbarAppearance: "Appearance", toolbarLanguage: "Language", toolbarNewTab: "New Tab",
        sidebarGroupFile: "File", sidebarGroupEdit: "Edit", sidebarGroupAnalysis: "Analysis",
        sidebarGroupView: "View", sidebarGroupExport: "Export", sidebarGroupSystem: "System",
        schemeMinimal: "Minimal", schemeClustalX: "ClustalX", schemeZappo: "Zappo",
        schemeSeaView: "SeaView", schemeDefault: "Default",
        schemeTransitionTransversion: "Ti/Tv",
        clustalXThreshold: "Conservation Threshold", clustalXThresholdHint: "Columns below this threshold are not colored",
        ctxRenameSeq: "Rename Sequence", ctxDeleteSeq: "Delete Sequence",
        ctxMoveTop: "Move to Top", ctxMoveBottom: "Move to Bottom",
        ctxSortBy: "Sort By", ctxSortByName: "Sort by Name",
        ctxSortBySimilarity: "Sort by Similarity to Consensus", ctxSortByGC: "Sort by GC Content",
        ctxSortByLength: "Sort by Length (with gaps)", ctxSortByLengthNoGaps: "Sort by Length (no gaps)",
        ctxCopySelection: "Copy Selection", ctxColorScheme: "Color Scheme",
        ctxTranslate: "Translate…", ctxReverseComplement: "Reverse Complement",
        ctxInsertGap: "Insert Gap", ctxPaste: "Paste", ctxAddSeq: "Add Sequence…",
        ctxRemoveAllGapCols: "Remove All-Gap Columns", ctxRemoveHighGapCols: "Remove High-Gap Columns (>50%)",
        ctxGapTrimming: "Gap Trimming",
        ctxSelectCodonPos: "Select Codon Position", ctxCodonPos1: "Position 1",
        ctxCodonPos2: "Position 2", ctxCodonPos3: "Position 3",
        statsPhyloInfo: "Phylogenetic Information", statsVariableSites: "Variable Sites",
        statsParsimonySites: "Parsimony-Informative Sites", statsSingletonSites: "Singleton Sites",
        statsSamplingHint: "Seqs >200, sampled 200 for approximate calculation",
        consensusMode: "Consensus Mode", consensusMajority: "Majority Rule",
        consensusIUPAC: "IUPAC Degenerate", consensusStrict: "Strict",
        settingsCodonTriplet: "Codon Triplet Display (group every 3 cols)",
        translateNameOption: "Sequence Name:", translateKeepOriginal: "Keep Original",
        translateAddSuffix: "Add _AA Suffix", translateSixFrameOverview: "Six-Frame Overview",
        translateHighlightStop: "Highlight Stop Codons", translateHighlightStart: "Highlight Start Codons",
        exportSequence: "Sequence", exportImage: "Image",
        exportFASTA: "FASTA", exportNEXUS: "NEXUS", exportPHYLIP: "PHYLIP",
        exportCLUSTAL: "CLUSTAL", exportMSF: "MSF",
        toolbarRunMSA: "Align", helpRunMSA: "Run external aligner on unaligned sequences (Cmd+Shift+B)",
        helpTranslateDisabled: "Only applicable to nucleotide sequences", helpPrimerDisabled: "Only applicable to nucleotide sequences",
        toastGapColsRemoved: "Removed all-gap columns", toastHighGapColsRemoved: "Removed high-gap columns (>50%)",
        toastSortByName: "Sorted by name", toastSortBySimilarity: "Sorted by similarity",
        toastSortByGC: "Sorted by GC content", toastSortByLength: "Sorted by length",
        toastSortByLengthNoGaps: "Sorted by gapless length", toastReverseComplement: "Reverse complemented",
        searchPlaceholderContent: "Residue or IUPAC pattern",
        searchPlaceholderContentRegex: "Residue regular expression",
        searchPlaceholderName: "Sequence name",
        searchPlaceholderNameRegex: "Name regular expression",
        searchFind: "Find", searchPrev: "Previous", searchNext: "Next",
        searchNoMatch: "No matches", searchComputing: "Searching", searchClose: "Close search",
        searchScopeContent: "Residues", searchScopeName: "Names", searchOptions: "Search options",
        searchRegex: "Regular expression", searchRegexOn: "Regular expression on",
        searchRegexOff: "Enable regular expression",
        statusSeqCount: "Sequences", statusColCount: "Columns", statusPosition: "Pos",
        statusResidue: "Residue", statusIdentity: "Identity", statusType: "Type",
        statusCharset: "Charsets",
        statusNucleic: "Nucleotide", statusAmino: "Protein", statusNoFile: "No file open",
        statsTitle: "Statistics", statsOverview: "Overview", statsFile: "File", statsFormat: "Format",
        statsSeqCount: "Sequences", statsColCount: "Columns", statsType: "Type",
        statsQuality: "Identity", statsMeanPairwise: "Site-weighted identity",

        statsMeanColIdentity: "Mean column identity", statsMinColIdentity: "Lowest column identity",
        statsMaxColIdentity: "Highest column identity", statsGapCols: "Columns with gaps",
        statsTotalCols: "Total columns", statsConservation: "Conservation",
        statsHighConserved: "Highly conserved ≥80%", statsConservationHint: "Five-bin identity distribution; darker bins are more conserved",
        statsConsensus: "Consensus", statsConsensusCopy: "Copy consensus", statsConsensusCopied: "Consensus copied", statsCursor: "Cursor",
        statsEmptyTitle: "No alignment open", statsEmptyDesc: "",
        statsNoData: "No data", statsComputing: "Computing",
        emptyTitle: "Open a sequence file",
        emptyDesc1: "FASTA, NEXUS, PHYLIP, CLUSTAL, MSF, Stockholm and FASTQ",
        emptyDesc2: "Unaligned sequences can be aligned with a local MAFFT or MUSCLE install",
        emptyOpenFile: "Open File", emptyLoadExample: "Load Example",
        aboutTitle: "SeqAlignMac", aboutVersion: "Version 0.1.0",
        aboutDesc: "Multiple sequence alignment viewer and editor",
        aboutFeatures: "Imports and exports seven formats, with color schemes, six-frame translation, primer Tm, search, undo, and vector export",
        aboutRefs: "Tm calculation follows SantaLucia 1998; codon tables from NCBI",
        aboutLicense: "MIT License",
        guideTitle: "Quick Guide", guideStart: "Start",
        qualityTitle: "Alignment Quality", qualityNoFile: "No alignment file open", qualityCharset: "NEXUS charsets",
        settingsTitle: "Preferences", settingsAppearance: "Appearance",
        settingsLight: "Light", settingsDark: "Dark", settingsSystem: "System",
        settingsColorScheme: "Default scheme", settingsFontSize: "Default size",
        settingsShowConsensus: "Show consensus",
        settingsHighContrast: "High contrast",
        settingsFocusDim: "Focus dim", settingsDone: "Done",
        renameTitle: "Rename Sequence", renamePlaceholder: "New name", renameConfirm: "OK",
        moveTitle: "Move Sequence", moveCount: "Total", moveFrom: "From: ", moveTo: "To: ", moveConfirm: "OK",
        alignerTitle: "External Aligner",
        alignerDesc: "Runs a local MAFFT, MUSCLE or ClustalW install; results open in a new window",
        alignerLabel: "Command", alignerPlaceholder: "Command or full path",
        alignerExample: "%1$@ input file, %2$@ output file",
        alignerRunning: "Aligning, cancelled automatically after 5 minutes",
        alignerRun: "Run", alignerTerminate: "Terminate",
        alignerTimeout: "Alignment timed out (5 min). Reduce the number or length of sequences and retry.",
        alignerCancelled: "Alignment cancelled.",
        alignerFailCode: "Alignment failed (exit code",
        alignerFailRead: "Alignment finished, but the result file could not be read.",
        alignerFailExec: "External aligner failed:",
        alignerTempWriteFail: "Failed to write temporary input file: ",
        alignerNotFound: "Aligner not found:",
        alignerEnterCmd: "Enter the aligner command or full path",
        primerTitle: "Primer", primerSeqA: "Sequence A", primerSeqB: "Sequence B",
        primerPlaceholderA: "Forward primer, e.g. ATGCTAGCTAGCTAGCTAGC", primerPlaceholderB: "Optional, for heterodimer check",
        primerFromSel: "Fill from selection", primerCalcTm: "Calculate", primerCalcGC: "GC content",
        primerSelfDimer: "Self-dimer", primerHeteroDimer: "Hetero-dimer",
        primerResultPlaceholder: "Enter a primer to calculate",
        primerTmLabel: "Nearest-neighbor (SantaLucia 1998)",
        primerTmRange: "Tm range", primerParams: "Conditions",
        primerNa: "Na⁺", primerMg: "Mg²⁺", primerOligo: "Primer conc.",
        primerGC: "GC content", primerSelfDimerTitle: "Self-dimer",
        primerHeteroTitle: "Hetero-dimer", primerDG: "ΔG", primerSeq: "Sequence",
        primerSeqALbl: "Sequence A", primerSeqBLbl: "Sequence B",
        primerWarnDimer: "Strong dimer tendency", primerSafeDimer: "No significant dimer",
        primerCalcFail: "Calculation failed", primerError: "Error",
        primerNeedSeqA: "Enter sequence A", primerNeedSeqB: "Enter sequence B",
        translateTitle: "Translate", translateCodeTable: "Genetic code",
        translateFrame: "Reading frame", translateMode: "Display",
        translateModeCodon: "Codons", translateModeAA: "Amino acids",
        translateModeBoth: "Codons and amino acids", translateModeIgnoreGaps: "Ignore gaps",
        translateNewWindow: "Open in new window",
        translateBtn: "Translate",
        unsavedTitle: "Unsaved Changes",
        unsavedDesc: "has unsaved edits. Save?",
        unsavedSave: "Save", unsavedDontSave: "Don't Save",
        cmdPaletteTitle: "Command Palette", cmdPalettePlaceholder: "Type a command or shortcut…",
        cmdPaletteNoMatch: "No matching commands",
        legendTitle: "Legend", legendCanvasOps: "Canvas Operations",
        legendOp1: "Drag the name column divider to adjust its width",
        legendOp2: "Click or drag the top conservation track to jump to a column",
        legendOp3: "Option-drag selects column blocks; Option plus arrows extends the selection from the anchor",
        legendOp4: "⌘-scroll or pinch to zoom; arrow keys move the cursor; Esc clears the selection",
        legendOp5: "⌘A selects all, ⌘C copies the selection",
        legendOp6: "Right-click the data area for editing and color menus",
        legendDarkNote: "In dark appearance the data palette inverts, preserving category correspondence.",
        menuNewTab: "New Tab", menuNewWindow: "New Window", menuOpen: "Open File…",
        menuCloseWindow: "Close Window", menuCloseTab: "Close Tab", menuOpenRecent: "Open Recent", menuNoRecent: "No recent files",
        menuSave: "Save", menuSaveAs: "Save As…",
        menuExportPNG: "Export as PNG", menuExportPDF: "Export as PDF", menuExportSVG: "Export as SVG",
        menuUndo: "Undo", menuRedo: "Redo", menuCut: "Cut", menuCopy: "Copy",
        menuPaste: "Paste", menuSelectAll: "Select All", menuRevComp: "Reverse Complement",
        menuInsertGap: "Insert Gap", menuDeleteSeq: "Delete Selected Sequence",
        menuMoveSeq: "Move Sequence", menuRenameSeq: "Rename Sequence",
        menuView: "View", menuTools: "Tools", menuAppearance: "Appearance", menuLanguage: "Language",
        menuSettings: "Preferences…", menuHelp: "Help", menuGuide: "Quick Guide",
        menuLoadExample: "Load Example", menuAbout: "About SeqAlignMac",
        menuRunAlign: "Run Alignment", menuTranslate: "Translate", menuPrimer: "Primer",
        menuQuality: "Alignment Quality", menuSearch: "Search", menuFindNext: "Find Next",
        menuFindPrev: "Find Previous", menuCmdPalette: "Command Palette",
        menuExport: "Export", menuZoom: "Zoom",
        menuLight: "Light", menuDark: "Dark", menuFollowSystem: "Follow System",
        menuChinese: "中文", menuEnglish: "English", menuToggleConsensus: "Show/Hide Consensus",
        toastSaved: "Saved", toastExported: "Exported", toastClipboardEmpty: "Clipboard is empty",
        toastCopied: "Copied", toastPasted: "Pasted", toastUndo: "Undo", toastRedo: "Redo",
        toastReplaceTranslated: "Replaced with the translation; ⌘Z to undo",
        toastFirstRun: "Tip: drag the name column divider to resize, or click the top track to jump to a column",
        loadingText: "Parsing file…", loadingCancel: "Cancel",
        errorSaveFail: "Save failed: ", errorExportFail: "Export failed: ",
        errorRegexInvalid: "Invalid regex: ",
        errorClipboardUnrecognized: "Cannot parse clipboard: please paste FASTA or raw sequences",
        quitTitle: "Unsaved Changes", quitSingleDesc: " has unsaved edits.",
        quitMultiDesc: " windows have unsaved edits.", quitSaveExit: "Save and Quit",
        windowTitleUnnamed: "SeqAlignMac (Untitled)", windowTitlePrefix: "SeqAlignMac",
        alignerPresetMafft: "MAFFT", alignerPresetMuscle: "MUSCLE",
        alignerPresetClustal: "ClustalW", alignerPresetCustom: "Custom",
        cmdOpen: "Open File…", cmdSave: "Save", cmdSaveAs: "Save As…",
        cmdRunAlign: "Run Alignment", cmdTranslate: "Translate",
        cmdPrimer: "Primer", cmdQuality: "Alignment Quality", cmdSearch: "Search",
        cmdCopy: "Copy Selection", cmdSelectAll: "Select All", cmdRevComp: "Reverse Complement",
        cmdInsertGap: "Insert Gap", cmdDeleteSeq: "Delete Selected Sequence", cmdMoveSeq: "Move Sequence",
        cmdRenameSeq: "Rename Sequence", cmdSchemeMinimal: "Scheme: Minimal",
        cmdSchemeClustalX: "Scheme: ClustalX", cmdSchemeZappo: "Scheme: Zappo",
        cmdSchemeSeaView: "Scheme: SeaView",
        cmdSchemeDefault: "Scheme: Default",
        cmdSchemeTransitionTransversion: "Scheme: Ti/Tv",
        cmdZoomIn: "Zoom: In", cmdZoomOut: "Zoom: Out", cmdZoomReset: "Zoom: Reset",
        cmdToggleConsensus: "Show/Hide Consensus",
        cmdThemeLight: "Theme: Light", cmdThemeDark: "Theme: Dark",
        cmdThemeSystem: "Theme: System",
        cmdSettings: "Preferences…", cmdGuide: "Quick Guide", cmdLoadExample: "Load Example",
        cmdAbout: "About SeqAlignMac",
        cmdAddSeq: "Add sequence", cmdBatchReplace: "Batch replace", cmdReplaceAlignment: "Replace alignment",
        cmdTransaction: "Transaction (%d steps)",
        schemeOkabeIto: "Okabe-Ito (CVD-safe)",
        fastqQuality: "Read Quality", fastqMeanPhred: "Mean Phred", fastqMinPhred: "Min Phred",
        fastqQ20: "≥Q20 bases", fastqQ30: "≥Q30 bases",
        statsMethodNote: "Column identity is the fraction of the most frequent residue; gaps excluded.",
        logoTitle: "Sequence Logo", logoHint: "Letter height is residue fraction times column information content; gaps excluded.",
        treeTitle: "NJ Phylogenetic Tree", treeHint: "Neighbor-Joining with uncorrected p-distance; evenly sampled when more than 200 sequences.",
        treeCopyNewick: "Copy Newick",
        windowTitle: "Sliding-Window Identity", windowSize: "Window size",
        annotTitle: "Annotations", annotLoad: "Import GFF3",
        annotLoadFailRead: "Could not read annotation file.",
        annotLoadEmpty: "Annotation file parsed 0 features (wrong format or empty).",
        annotLoaded: "Loaded",
        annotSeqidNotFound: "Sequence not found in alignment: ", annotNone: "No annotation file loaded",
        annotSeq: "Sequence", annotType: "Type", annotRange: "Columns", annotName: "Name", annotJump: "Jump",
        toolbarDifference: "Diff", helpDifference: "Dim residues identical to the cursor row",
        toolbarLogo: "Sequence Logo", toolbarTree: "NJ Tree", toolbarWindowChart: "Sliding Window", toolbarAnnotation: "Annotations",
        aboutCitation: "Cite (BibTeX)",
        tooltipCloseTab: "Close", tooltipNewTab: "New Tab (⌘T)",
        helpOpenFile: "Open file (⌘O)", helpSave: "Save (⌘S)",
        helpExample: "Load example",
        helpTranslate: "Translate (⇧⌘T)", helpPrimer: "Primer calculation",
        helpQuality: "Alignment quality", helpLegend: "Legend",
        helpUndo: "Undo (⌘Z)", helpRedo: "Redo (⇧⌘Z)",
        helpExport: "Export as PNG / PDF / SVG", helpSettings: "Preferences (⌘,)",
        helpCmdPalette: "Command palette (⇧⌘P)",
        helpColorScheme: "Colors (⇧⌘1/2/3/4)",
        helpZoomReset: "Current zoom, click to reset (⇧⌘0)",
        helpZoomIn: "Zoom in (⌘+ or ⌘scroll)", helpZoomOut: "Zoom out (⌘- or ⌘scroll)",
        helpAppearance: "Appearance", helpLanguage: "Language",
        helpSearch: "Search (⌘F)",
        helpRegexOn: "Regular expression on",
        helpRegexOff: "Enable regular expression",
        exportOnlySelection: "Export selection only",
        exportPNG: "Export as PNG", exportPDF: "Export as PDF", exportSVG: "Export as SVG",
        exportPreviewTitle: "Export Preview", exportPreviewFormat: "Format",
        exportPreviewSize: "Estimated Size", exportPreviewDarkMode: "Dark Mode Export",
        exportPreviewExportBtn: "Export…",
        savingText: "Saving…",
        exportingText: "Exporting…",
        exportPreviewFailed: "Preview unavailable (alignment too large or render failed)"
    )

    // MARK: 静态不变的格式名
    static let formatFASTA = "FASTA"
    static let formatFASTQ = "FASTQ"
    static let formatNEXUS = "NEXUS"
    static let formatPHYLIP = "PHYLIP"
    static let formatCLUSTAL = "CLUSTAL"
    static let formatMSF = "MSF"
    static let formatStockholm = "Stockholm"
    static let formatUnknown = "Unknown"
    static let formatUnknownZh = "未知"

    static func formatName(_ f: AlignmentFormat, zh: Bool) -> String {
        switch f {
        case .fasta: return formatFASTA
        case .fastq: return formatFASTQ
        case .nexus: return formatNEXUS
        case .phylip: return formatPHYLIP
        case .clustal: return formatCLUSTAL
        case .msf: return formatMSF
        case .stockholm: return formatStockholm
        case .unknown: return zh ? formatUnknownZh : formatUnknown
        }
    }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
}

// MARK: - 独立维护的文案（双语；集中在此，不与 400 字段初始化器纠缠）
extension AppStrings {
    private var isZh: Bool { LanguageManager.shared.language == .zh }

    var translationNeedsNucleotide: String {
        isZh ? "翻译仅适用于核酸比对" : "Translation is only available for nucleotide alignments"
    }
    var translationFrameshift: String {
        isZh ? "以下序列含非 3 倍数的缺失，其后读框已错位（相应位置以 X 表示）"
             : "These sequences contain indels that are not multiples of 3; the downstream reading frame is out of phase (shown as X)"
    }
    var translationMixedTrack: String {
        isZh ? "密码子+氨基酸混排轨仅用于显示，不可用于统计或建树"
             : "The codon + amino-acid track is for display only; it cannot be used for statistics or tree building"
    }
    var translationRagged: String {
        isZh ? "忽略空位模式产出行长参差，与源比对列脱钩，不可用于系统发育"
             : "Gap-ignoring mode yields ragged rows decoupled from the source alignment columns; not usable for phylogenetics"
    }
    var translationLengthNotMultipleOfThree: String {
        isZh ? "比对长度不是 3 的倍数：末尾已补空位后再翻译"
             : "Alignment length is not a multiple of three: padded before translation"
    }
    var logoTruncated: String {
        isZh ? "序列 Logo 仅计算前 4000 列，省略列数："
             : "Sequence logo computed for the first 4000 columns only; columns omitted:"
    }
    var gffFeatureNotInAlignment: String {
        isZh ? "注释区间落在该序列残基范围之外，无法跳转"
             : "The annotated range lies outside this sequence; cannot jump"
    }
    var treeModelUncorrected: String {
        isZh ? "距离模型：未校正 p-distance + NJ，仅适用于低分化近缘序列"
             : "Distance model: uncorrected p-distance + NJ, appropriate only for closely related sequences"
    }
    var treeClampedBranches: String {
        isZh ? "负分支长度被钳零的次数：" : "Negative branch lengths clamped to zero:"
    }
    var unalignedWarning: String {
        isZh ? "输入序列长度不等：已右补空位呈现，但列同源性不成立"
             : "Input sequences differ in length: padded for display, but column homology does not hold"
    }
    var statsUnalignedBanner: String {
        isZh ? "非比对输入：列统计与建树结果不可信，请先运行比对"
             : "Unaligned input: column statistics and trees are unreliable - align first"
    }
    /// 导出图中的共识序列标签不再硬编码中文（PNG/PDF/SVG 三条路径共用本值）
    var alignerResultMismatch: String {
        isZh ? "比对结果与输入不一致，已拒绝载入" : "Alignment result is inconsistent with the input; refused"
    }
    var alignerMismatchCount: String {
        isZh ? "序列数变化" : "sequence count changed"
    }
    var alignerMismatchMissing: String {
        isZh ? "缺少序列" : "missing sequences"
    }
    var alignerMismatchExtra: String {
        isZh ? "多出序列" : "unexpected sequences"
    }
    var alignerMismatchRagged: String {
        isZh ? "结果行长不齐" : "result rows have differing lengths"
    }
    var treeSampledNote: String {
        isZh ? "抽样建树（等距）：" : "NJ tree built from an even sample:"
    }
    var settingsAlignerTimeout: String {
        isZh ? "比对器超时" : "Aligner timeout"
    }
    var exportConsensusLabel: String {
        isZh ? "共识序列" : "Consensus"
    }
    var alignerPresetLabel: String {
        isZh ? "预设" : "Preset"
    }
    var alignerTimeoutLabel: String {
        isZh ? "超时" : "Timeout"
    }

}
