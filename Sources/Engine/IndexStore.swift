import Foundation

/// 索引落盘。一个 JSON 文件放在 App 自己的沙盒里，不写相册、不写别人的容器。
///
/// 之所以不用数据库：索引内容全是文本，一万条 JSON 也就几 MB，读写一次几十毫秒，
/// 换来的是零依赖（云端一次编译就能过），也让"导出/清库/排查"变得可读。
enum IndexStore {
    static let version = 1

    private struct Payload: Codable {
        var version: Int
        var records: [String: PhotoRecord]
    }

    private static let fileURL: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("photo-index.json")
    }()

    static func load() -> [String: PhotoRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else { return [:] }
        guard payload.version == version else {
            // 识别规则升级后旧索引不可信，直接重跑。
            reset()
            return [:]
        }
        return payload.records
    }

    static func save(_ records: [String: PhotoRecord]) {
        let payload = Payload(version: version, records: records)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("索引写入失败：\(error.localizedDescription)")
        }
    }

    static func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static var fileByteSize: Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int else { return 0 }
        return size
    }
}
