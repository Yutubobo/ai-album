import Photos
import UIKit

/// 只在需要时把回调"兑现一次"的工具，避免 PhotoKit 多次回调造成 continuation 重复 resume。
final class SingleResume {
    private let lock = NSLock()
    private var claimed = false

    /// 第一次调用返回 true，之后永远返回 false。
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return false == false ? true : false
    }
}

/// 相册读取。全程只申请读取权限，代码里不做任何删除与改写。
@MainActor
final class PhotoLibraryService: ObservableObject {
    static let shared = PhotoLibraryService()

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private let manager = PHImageManager.default()
    private var lookup: [String: PHAsset] = [:]

    func requestAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else {
            status = current
            return current
        }
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { result in
                continuation.resume(returning: result)
            }
        }
        status = granted
        return granted
    }

    var hasAccess: Bool {
        status == .authorized || status == .limited
    }

    /// 重新拉取全库资源列表。照片数量再多也只是元数据，成本很低。
    func reload() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: options)
        var collected = [PHAsset]()
        collected.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            collected.append(asset)
        }
        assets = collected
        lookup = Dictionary(uniqueKeysWithValues: collected.map { ($0.localIdentifier, $0) })
    }

    func asset(for identifier: String) -> PHAsset? {
        lookup[identifier]
    }

    /// 交给 Vision 做识别用的中等尺寸图。1600 像素足够读清证件上的小字，
    /// 又不会像原图那样把内存吃满；iCloud 里没下载的照片会按需取一次。
    func cgImage(for asset: PHAsset, maxDimension: CGFloat = 1600) async -> CGImage? {
        let scale = maxDimension / CGFloat(max(asset.pixelWidth, asset.pixelHeight, 1))
        let target = CGSize(width: CGFloat(asset.pixelWidth) * scale,
                            height: CGFloat(asset.pixelHeight) * scale)
        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFrame
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            let once = SingleResume()
            manager.requestImage(for: asset,
                                 targetSize: target,
                                 contentMode: .default,
                                 options: options) { image, _ in
                if once.claim() {
                    continuation.resume(returning: image?.cgImage)
                }
            }
        }
    }

    /// 给缩略图网格用，小尺寸、允许降级返回。
    /// opportunistic 模式会先回一张模糊的再回清晰的，这里只在"非降级"那一次兑现结果。
    func thumbnail(for identifier: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = asset(for: identifier) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            let once = SingleResume()
            manager.requestImage(for: asset,
                                 targetSize: targetSize,
                                 contentMode: .aspectFill,
                                 options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded, once.claim() {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    /// 全屏看原图。
    func fullImage(for identifier: String) async -> UIImage? {
        guard let asset = asset(for: identifier) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFrame
            options.isNetworkAccessAllowed = true
            options.version = .original
            let once = SingleResume()
            manager.requestImage(for: asset,
                                 targetSize: PHImageManagerMaximumSize,
                                 contentMode: .default,
                                 options: options) { image, _ in
                if once.claim() { continuation.resume(returning: image) }
            }
        }
    }

    /// 导出原始数据用于分享（保留原格式）。
    func exportImage(for identifier: String) async -> UIImage? {
        guard let asset = asset(for: identifier) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFrame
            options.isNetworkAccessAllowed = true
            options.version = .current
            let once = SingleResume()
            manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                if once.claim() {
                    continuation.resume(returning: data.flatMap { UIImage(data: $0) })
                }
            }
        }
    }
}
