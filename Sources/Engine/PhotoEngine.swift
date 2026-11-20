import Foundation
import Photos

/// 扫描范围。第一次跑不用把几万张全过一遍，先扫最近三年加所有截图，
/// 证件几乎都混在截图和近照里，等用起来再补全量。
enum ScanScope: String, CaseIterable, Identifiable {
    case recentScreenshots
    case threeYears
    case everything

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentScreenshots: return "近一年 + 全部截图"
        case .threeYears: return "最近三年"
        case .everything: return "整个相册"
        }
    }

    var detail: String {
        switch self {
        case .recentScreenshots: return "最快，证件和票据大多在这里面"
        case .threeYears: return "推荐，覆盖面和时间的平衡点"
        case .everything: return "最全，照片多时耗时较长，可中途停止"
        }
    }

    var monthsBack: Int? {
        switch self {
        case .recentScreenshots: return 12
        case .threeYears: return 36
        case .everything: return nil
        }
    }
}

/// 整个 App 的大脑：权限、扫描、索引、搜索都在这里调度。
@MainActor
final class PhotoEngine: ObservableObject {

    @Published var permission: PHAuthorizationStatus
    @Published var query = ""
    @Published var hits: [SearchHit] = []
    @Published var selectedCategory: DocCategory?
    @Published var paperworkOnly = false
    @Published var scope: ScanScope = .threeYears

    @Published private(set) var records: [String: PhotoRecord] = [:]
    @Published private(set) var docs: [IndexedDoc] = []
    @Published private(set) var isIndexing = false
    @Published private(set) var processed = 0
    @Published private(set) var pendingTotal = 0
    @Published private(set) var lastMessage: String?

    let library = PhotoLibraryService.shared
    let speech = SpeechInput()

    private var indexTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var saveCounter = 0

    init() {
        permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var hasLibraryAccess: Bool {
        permission == .authorized || permission == .limited
    }

    var indexedCount: Int { records.count }
    var libraryCount: Int { library.assets.count }

    var progress: Double {
        guard pendingTotal > 0 else { return isIndexing ? 0 : 1 }
        return min(1, Double(processed) / Double(pendingTotal))
    }

    var isIdleReady: Bool { !isIndexing && hasLibraryAccess && !docs.isEmpty }

    /// 各分类的照片数量，用来在首页做"证件共 12 张"这种一眼可懂的入口。
    var categoryCounts: [(category: DocCategory, count: Int)] {
        var tally: [DocCategory: Int] = [:]
        for document in docs {
            tally[document.record.category, default: 0] += 1
        }
        return tally
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.title < $1.key.title }
            .map { (category: $0.key, count: $0.value) }
    }

    // MARK: - 启动

    func bootstrap() async {
        permission = await library.requestAccess()
        if permission == .denied || permission == .restricted || permission == .notDetermined {
            lastMessage = "没有相册权限就无法识别照片，请在\"设置 > AI相册 > 照片\"里选择\"所有照片\"。"
            return
        }
        if permission == .limited {
            lastMessage = "当前是\"选中照片\"模式，只索引你勾选的那部分；改成\"所有照片\"才能搜全库。"
        }
        library.reload()
        let stored = IndexStore.load()
        if !stored.isEmpty {
            records = stored
            lastMessage = "已载入本机索引 \(stored.count) 条，可直接搜索。"
            await rebuildDocs()
        }
        await speech.prepare()
    }

    /// 从磁盘记录重建内存检索结构（签名和归一化文本不入库，省一半体积）。
    private func rebuildDocs() async {
        let snapshot = Array(records.values)
        let built = await Task.detached(priority: .userInitiated) { () -> [IndexedDoc] in
            snapshot.map { record in
                let (haystack, signature) = TextSignature.build(for: record)
                return IndexedDoc(record: record, haystack: haystack, signature: signature)
            }
        }.value
        docs = built
        refreshSearch(immediate: true)
    }

    // MARK: - 扫描

    func startScan() {
        guard !isIndexing else { return }
        guard hasLibraryAccess else {
            lastMessage = "请先允许访问相册。"
            return
        }
        isIndexing = true
        processed = 0
        indexTask = Task { await runScan() }
    }

    func cancelScan() {
        indexTask?.cancel()
    }

    func clearIndexAndRestart() {
        cancelScan()
        IndexStore.reset()
        records = [:]
        docs = []
        hits = []
        processed = 0
        pendingTotal = 0
        lastMessage = "本机索引已清空，重新开始识别。"
    }

    /// 重新读取相册列表，只补缺失的部分（新拍的照片走这里，成本极低）。
    func refreshLibraryAndScanNew() {
        library.reload()
        startScan()
    }

    private func pendingAssets() -> [PHAsset] {
        let cutoff: Date?
        if let months = scope.monthsBack {
            cutoff = Calendar(identifier: .gregorian).date(byAdding: .month, value: -months, to: Date())
        } else {
            cutoff = nil
        }
        var result = [PHAsset]()
        for asset in library.assets {
            guard records[asset.localIdentifier] == nil else { continue }
            guard asset.mediaType == .image else { continue }
            let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
            if let cutoff {
                // 时间窗之外的截图仍然收进来：证件照十有八九是截图或翻拍。
                let recent = (asset.creationDate ?? .distantPast) >= cutoff
                if !recent && !isScreenshot { continue }
            }
            result.append(asset)
        }
        return result
    }

    private func runScan() async {
        library.reload()
        let targets = pendingAssets()
        pendingTotal = targets.count
        guard !targets.isEmpty else {
            lastMessage = "该范围内没有需要新识别的照片。"
            isIndexing = false
            return
        }

        var batch = [PhotoRecord]()
        batch.reserveCapacity(24)
        var failures = 0

        for asset in targets {
            if Task.isCancelled { break }
            guard let image = await library.cgImage(for: asset, maxDimension: 1600) else {
                failures += 1
                processed += 1
                continue
            }
            let vision = await VisionAnalyzer.analyze(image)
            let hints = DocumentShapeScanner.hints(labels: vision.labels)
            let haystack = TextNormalizer.normalize(vision.text)
            let aspect = Double(asset.pixelWidth) / Double(max(asset.pixelHeight, 1))
            let decision = DocumentClassifier.decide(haystack: haystack,
                                                     labels: vision.labels,
                                                     hints: hints,
                                                     aspect: aspect,
                                                     isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot))

            let record = PhotoRecord(id: asset.localIdentifier,
                                     takenAt: asset.creationDate,
                                     pixelWidth: asset.pixelWidth,
                                     pixelHeight: asset.pixelHeight,
                                     kind: .image,
                                     isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                                     isFavorite: asset.isFavorite,
                                     ocrText: vision.text,
                                     labels: vision.labels,
                                     shapeHints: hints,
                                     category: decision.category,
                                     idNumbers: IdNumber.extract(from: haystack),
                                     categoryScore: decision.score)
            batch.append(record)
            processed += 1

            if batch.count >= 24 {
                flush(batch)
                batch.removeAll(keepingCapacity: true)
                persist()
                await Task.yield()
            }
        }

        if !batch.isEmpty { flush(batch) }
        persist()
        isIndexing = false
        var message = "识别完成，本机已建立 \(records.count) 条索引。"
        if failures > 0 {
            message += "其中 \(failures) 张没取到图（多为 iCloud 未下载），下次扫描会自动重试。"
        }
        lastMessage = message
        refreshSearch(immediate: true)
    }

    private func flush(_ batch: [PhotoRecord]) {
        var appended = [IndexedDoc]()
        appended.reserveCapacity(batch.count)
        for record in batch {
            records[record.id] = record
            let (haystack, signature) = TextSignature.build(for: record)
            appended.append(IndexedDoc(record: record, haystack: haystack, signature: signature))
        }
        docs.append(contentsOf: appended)
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            refreshSearch()
        }
    }

    private func persist() {
        saveCounter += 1
        guard saveCounter % 4 == 0 || processed >= pendingTotal else { return }
        let snapshot = records
        Task.detached(priority: .background) {
            IndexStore.save(snapshot)
        }
    }

    // MARK: - 搜索

    func refreshSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = paperworkOnly ? docs.filter { $0.record.category.isPaperwork } : docs
        let category = selectedCategory
        searchTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { () -> [SearchHit] in
                let parsed = SearchEngine.parse(trimmed)
                if parsed.isEmptyQuery {
                    return SearchEngine.browse(docs: snapshot, category: category)
                }
                return SearchEngine.search(parsed, docs: snapshot, category: category)
            }.value
            guard !Task.isCancelled else { return }
            self?.hits = result
        }
    }

    func useVoiceResult(_ text: String) {
        guard !text.isEmpty else { return }
        query = text
        refreshSearch(immediate: true)
    }
}
