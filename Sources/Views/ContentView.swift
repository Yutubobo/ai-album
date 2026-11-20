import Photos
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var engine: PhotoEngine
    @State private var presentedHit: SearchHit?
    @State private var showInfo = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if !engine.hasLibraryAccess {
                    PermissionGate()
                } else if engine.docs.isEmpty && !engine.isIndexing {
                    EmptyLibraryHint()
                } else {
                    content
                }
            }
            .navigationTitle("AI相册")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        engine.refreshLibraryAndScanNew()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("补扫新拍的照片")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "lock.shield")
                    }
                }
            }
            .sheet(isPresented: $showInfo) { PrivacySheet() }
            .fullScreenCover(item: $presentedHit) { hit in
                PhotoDetailView(hit: hit)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            VoiceAwareSearchBar(speech: engine.speech)
            CategoryFilterBar()
                .padding(.vertical, 6)
            IndexStatusStrip()
                .padding(.bottom, 6)
            results
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: engine.query) { _, _ in
            engine.refreshSearch()
        }
    }

    private var results: some View {
        ScrollView {
            if engine.query.isEmpty {
                SuggestionRow()
            }
            if engine.hits.isEmpty {
                EmptyResultHint()
            } else {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(engine.hits) { hit in
                        Button {
                            presentedHit = hit
                        } label: {
                            PhotoCell(hit: hit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 3)
            }
        }
    }
}

// MARK: - 搜索框 + 语音

/// 单独把语音状态包一层，是因为 SpeechInput 是独立的可观察对象：
/// 只有在这里订阅它，麦克风按钮和实时字幕才会跟着变。
private struct VoiceAwareSearchBar: View {
    @EnvironmentObject private var engine: PhotoEngine
    @ObservedObject private var speech: SpeechInput

    init(speech: SpeechInput) {
        self.speech = speech
    }

    var body: some View {
        VStack(spacing: 4) {
            SearchField(query: $engine.query, listening: speech.isListening, onMic: toggle)
            if let note = note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .onChange(of: speech.transcript) { _, text in
            if speech.isListening, !text.isEmpty {
                engine.query = text
            }
        }
        .onChange(of: speech.isListening) { _, listening in
            if !listening {
                engine.useVoiceResult(speech.transcript)
            }
        }
    }

    private var note: String? {
        if speech.isListening {
            return "正在听，说完再点一下麦克风。"
        }
        if !speech.isReady {
            return speech.message
        }
        return nil
    }

    private func toggle() {
        if speech.isListening {
            speech.stop()
        } else {
            speech.start()
        }
    }
}

private struct SearchField: View {
    @Binding var query: String
    let listening: Bool
    let onMic: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                ZStack(alignment: .leading) {
                    if query.isEmpty {
                        Text("身份证、合同、去年海边、尾号1234")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                    }
                    TextField("", text: $query)
                        .font(.system(size: 15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

            Button(action: onMic) {
                Image(systemName: listening ? "mic.fill" : "mic.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(listening ? Color.red : Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(listening ? "停止说话" : "用语音搜索")
        }
        .animation(.easeInOut(duration: 0.15), value: listening)
    }
}

// MARK: - 分类筛选

private struct CategoryFilterBar: View {
    @EnvironmentObject private var engine: PhotoEngine

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", symbol: "square.grid.2x2",
                     isOn: !engine.paperworkOnly && engine.selectedCategory == nil) {
                    engine.paperworkOnly = false
                    engine.selectedCategory = nil
                    engine.refreshSearch(immediate: true)
                }
                chip(title: "只看证件", symbol: "checklist", isOn: engine.paperworkOnly) {
                    engine.paperworkOnly.toggle()
                    engine.selectedCategory = nil
                    engine.refreshSearch(immediate: true)
                }
                ForEach(engine.categoryCounts, id: \.category) { entry in
                    chip(title: "\(entry.category.title) \(entry.count)",
                         symbol: entry.category.symbol,
                         isOn: engine.selectedCategory == entry.category) {
                        if engine.selectedCategory == entry.category {
                            engine.selectedCategory = nil
                        } else {
                            engine.selectedCategory = entry.category
                            engine.paperworkOnly = false
                        }
                        engine.refreshSearch(immediate: true)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 13, weight: isOn ? .semibold : .regular))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isOn ? Color.accentColor.opacity(0.16) : Color(.secondarySystemGroupedBackground),
                        in: Capsule())
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 索引状态

private struct IndexStatusStrip: View {
    @EnvironmentObject private var engine: PhotoEngine

    var body: some View {
        HStack(spacing: 10) {
            if engine.isIndexing {
                ProgressView(value: engine.progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 90)
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if engine.isIndexing {
                Button("停止") { engine.cancelScan() }
                    .font(.system(size: 12))
            } else {
                Button(engine.docs.isEmpty ? "开始识别" : "补扫新增") {
                    engine.startScan()
                }
                .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private var summary: String {
        if engine.isIndexing {
            return "本机识别中 \(engine.processed)/\(engine.pendingTotal)"
        }
        let paperwork = engine.docs.filter { $0.record.category.isPaperwork }.count
        return "已索引 \(engine.docs.count) 张 · 证件票据 \(paperwork) 张"
    }
}

// MARK: - 常用搜索

private struct SuggestionRow: View {
    @EnvironmentObject private var engine: PhotoEngine

    private let words = ["身份证", "护照", "驾驶证", "合同", "发票", "户口本", "出生证明", "疫苗本", "银行卡", "去年拍的车"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("试试这些说法")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            FlowWords(words: words) { word in
                engine.query = word
                engine.refreshSearch(immediate: true)
            }
            Text("点一下就能搜，或者直接说给旁边的麦克风听。左上角的刷新按钮可以补扫新拍的照片。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
    }
}

private struct FlowWords: View {
    let words: [String]
    let onPick: (String) -> Void

    var body: some View {
        // 用自适应栅格代替自定义布局，不为一个小细节引入不稳定的 API。
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(words, id: \.self) { word in
                Button {
                    onPick(word)
                } label: {
                    Text(word)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct EmptyResultHint: View {
    @EnvironmentObject private var engine: PhotoEngine

    var body: some View {
        ContentUnavailableView {
            Label("没找到", systemImage: "questionmark.folder")
        } description: {
            Text(hint)
        }
        .padding(.top, 40)
    }

    private var hint: String {
        if engine.docs.isEmpty {
            return "还没有索引，先点上面的\"开始识别\"。"
        }
        if engine.isIndexing {
            return "正在识别中，可能那张照片还没轮到，已看完 \(engine.processed) 张。"
        }
        return "已在 \(engine.docs.count) 张照片里找过\"\(engine.query)\"。换个说法试试，比如证件上实际印的字。"
    }
}

// MARK: - 网格单元

private struct PhotoCell: View {
    let hit: SearchHit

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ThumbnailView(identifier: hit.record.id)
            if hit.record.category.isPaperwork {
                Label(hit.record.category.title, systemImage: hit.record.category.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(3)
            }
        }
    }
}

struct ThumbnailView: View {
    let identifier: String
    @State private var image: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: identifier) {
                image = await PhotoLibraryService.shared.thumbnail(for: identifier,
                                                                  targetSize: CGSize(width: 320, height: 320))
            }
    }
}

// MARK: - 空状态与权限

private struct PermissionGate: View {
    @EnvironmentObject private var engine: PhotoEngine

    var body: some View {
        ContentUnavailableView {
            Label("需要相册读取权限", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("识别和搜索都在这台手机里完成，照片不会上传到任何服务器。权限只用于读取，不删除、不改写相册内容。")
        } actions: {
            Button("去设置里开启") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)

            Button("我已开启，重新检查") {
                Task { await engine.bootstrap() }
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct EmptyLibraryHint: View {
    @EnvironmentObject private var engine: PhotoEngine

    var body: some View {
        ContentUnavailableView {
            Label("先让手机自己看一遍相册", systemImage: "text.viewfinder")
        } description: {
            Text("第一次会逐张在本地识别画面里的文字和场景，之后搜索就只是本机比对了。中途可以随时停，进度会保存。")
        } actions: {
            Button("开始识别") {
                engine.startScan()
            }
            .buttonStyle(.borderedProminent)
            Picker("扫描范围", selection: $engine.scope) {
                ForEach(ScanScope.allCases) { value in
                    VStack(alignment: .leading) {
                        Text(value.title)
                        Text(value.detail)
                            .font(.system(size: 11))
                    }
                    .tag(value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var engine: PhotoEngine

    var body: some View {
        NavigationStack {
            List {
                Section("怎么工作的") {
                    Label("PhotoKit 读取相册（只读）", systemImage: "photo.on.rectangle")
                    Label("Vision 在本机识别文字与场景", systemImage: "text.viewfinder")
                    Label("索引进本地文件，几 MB 大小", systemImage: "internaldrive")
                    Label(speechLabel, systemImage: "mic")
                    Picker("扫描范围", selection: $engine.scope) {
                        ForEach(ScanScope.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                }
                Section("不会做的事") {
                    Label("不上传任何一张照片", systemImage: "arrow.up.circle.slash")
                        .foregroundStyle(.red)
                    Label("不接入任何云端视觉模型", systemImage: "globe.slash")
                        .foregroundStyle(.red)
                    Label("不删除、不修改相册内容", systemImage: "trash.slash")
                        .foregroundStyle(.red)
                }
                Section("状态") {
                    LabeledContent("已索引", value: "\(engine.docs.count) 张")
                    LabeledContent("相册总数", value: "\(engine.library.assets.count) 项")
                    LabeledContent("索引文件",
                                   value: ByteCountFormatter.string(fromByteCount: Int64(IndexStore.fileByteSize),
                                                                    countStyle: .file))
                    if let message = engine.lastMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Button("清空本机索引", role: .destructive) {
                        engine.clearIndexAndRestart()
                    }
                }
            }
            .navigationTitle("隐私与状态")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var speechLabel: String {
        if engine.speech.usesOnDevice {
            return "语音识别在本机完成"
        }
        return "语音识别需联网（识别文字仅用于搜索）"
    }
}
