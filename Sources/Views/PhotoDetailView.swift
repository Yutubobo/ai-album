import Photos
import SwiftUI
import UIKit

/// 详情页：大图 + 本机识别到的内容 + 为什么被搜到 + 分享/跳转系统相册。
/// 按约定的范围，这里不做建相簿、编辑、删除，只负责"找出来并看一眼、给出去"。
@MainActor
struct PhotoDetailView: View {
    let hit: SearchHit

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var showDetails = true
    @State private var shareItem: ShareItem?
    @State private var note: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                imageArea
                details
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(hit.record.category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            openInSystemPhotos()
                        } label: {
                            Label("在系统相册中打开", systemImage: "photo")
                        }
                        Button {
                            Task { await prepareShare() }
                        } label: {
                            Label("分享这张照片", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            copyOcrText()
                        } label: {
                            Label("复制识别出的文字", systemImage: "doc.on.doc")
                        }
                        Button {
                            showDetails.toggle()
                        } label: {
                            Label(showDetails ? "收起识别信息" : "展开识别信息",
                                  systemImage: showDetails ? "chevron.down" : "chevron.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
            .overlay {
                if let note {
                    Text(note)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }
            }
        }
        .task {
            image = await PhotoLibraryService.shared.fullImage(for: hit.record.id)
        }
    }

    // MARK: - 大图

    private var imageArea: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: showDetails ? .fit : .fill)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { showDetails.toggle() }
        }
    }

    // MARK: - 识别信息

    @ViewBuilder
    private var details: some View {
        if showDetails {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !hit.reasons.isEmpty {
                        card(title: "为什么被搜到", symbol: "magnifyingglass.circle") {
                            ForEach(hit.reasons, id: \.self) { reason in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.green)
                                    Text(reason)
                                        .font(.system(size: 13))
                                }
                            }
                        }
                    }

                    card(title: "照片信息", symbol: "info.circle") {
                        row("类别", hit.record.category.title)
                        row("拍摄时间", hit.record.dateTitle)
                        row("尺寸", "\(hit.record.pixelWidth) × \(hit.record.pixelHeight)")
                        if hit.record.isScreenshot { row("来源", "系统截图") }
                        if hit.record.isFavorite { row("收藏", "已收藏") }
                        if !hit.record.labels.isEmpty {
                            row("画面标签", hit.record.labels.prefix(8).joined(separator: "、"))
                        }
                    }

                    if !hit.record.idNumbers.isEmpty {
                        card(title: "识别到证件号（已打码）", symbol: "number.circle") {
                            ForEach(hit.record.idNumbers, id: \.self) { value in
                                Text(mask(value))
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            Text("完整号码只存在这台手机的本地索引里，本页也只展示打码结果。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if hit.record.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        card(title: "本机读到的文字", symbol: "text.viewfinder") {
                            Text("这张照片没有识别出文字（可能是纯画面照片，或字迹太糊）。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        card(title: "本机读到的文字", symbol: "text.viewfinder") {
                            Text(hit.record.ocrText)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 18)
            }
            .frame(maxHeight: 300)
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func card<Content: View>(title: String, symbol: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 与检索层一致的打码规则：只显示前 6 后 4。
    private func mask(_ value: String) -> String {
        guard value.count == 18 else { return value }
        return "\(value.prefix(6))********\(value.suffix(4))"
    }

    // MARK: - 动作

    private func openInSystemPhotos() {
        // PhotoKit 没有官方"定位到系统相册某一张"的接口，这里用业界公认的私有 scheme，
        // 打不开就退回打开相册 App，并在屏幕上说实话，不谎报成功。
        let identifier = hit.record.id
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        guard let direct = URL(string: "ph-asset://A/\(encoded)") else { return }
        UIApplication.shared.open(direct) { success in
            Task { @MainActor in
                if success {
                    flash("已交给系统相册定位这张照片", seconds: 1.6)
                } else if let root = URL(string: "photos-redirect://") {
                    UIApplication.shared.open(root) { opened in
                        Task { @MainActor in
                            flash(opened ? "系统相册不支持直接定位，已打开相册" : "无法打开系统相册",
                                  seconds: 2.0)
                        }
                    }
                }
            }
        }
    }

    private func prepareShare() async {
        let exported = await PhotoLibraryService.shared.exportImage(for: hit.record.id)
        let target = exported ?? image
        guard let target else {
            flash("这张照片取不到原图（多为 iCloud 未下载）", seconds: 2.4)
            return
        }
        shareItem = ShareItem(items: [target])
    }

    private func copyOcrText() {
        let text = hit.record.ocrText
        UIPasteboard.general.string = text
        flash(text.isEmpty ? "这张没有可复制的文字" : "已复制 \(text.count) 个字", seconds: 1.6)
    }

    private func flash(_ message: String, seconds: Double) {
        note = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            note = nil
        }
    }
}

/// sheet(item:) 需要一个 Identifiable 载体。
struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
