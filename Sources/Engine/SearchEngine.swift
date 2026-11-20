import Foundation

struct SearchHit: Identifiable {
    let doc: IndexedDoc
    let score: Double
    let reasons: [String]

    var id: String { doc.record.id }
    var record: PhotoRecord { doc.record }
}

struct ParsedQuery {
    let raw: String
    let normalized: String
    let candidates: [String]
    let signature: TextSignature
    let digitRuns: [String]
    let timeIntent: QueryExpander.TimeIntent?

    var isEmptyQuery: Bool { normalized.isEmpty }
}

/// 纯内存排序检索。一万张照片一次全量打分在 A15 上大约十几毫秒，
/// 因此不需要预建倒排索引，也就不需要任何数据库依赖。
enum SearchEngine {

    static func parse(_ raw: String) -> ParsedQuery {
        let normalized = TextNormalizer.normalize(raw)
        let candidates = QueryExpander.expand(raw)
        var signature = TextSignature()
        for bigram in TextNormalizer.bigrams(of: normalized) {
            signature.add(bigram)
        }
        var runs = [String]()
        var current = ""
        for character in normalized {
            if let value = character.wholeNumberValue, (0...9).contains(value) {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }

        return ParsedQuery(raw: raw,
                           normalized: normalized,
                           candidates: candidates,
                           signature: signature,
                           digitRuns: runs,
                           timeIntent: QueryExpander.timeIntent(of: raw))
    }

    static func search(_ query: ParsedQuery,
                       docs: [IndexedDoc],
                       category: DocCategory?,
                       limit: Int = 600) -> [SearchHit] {
        guard !query.isEmptyQuery else { return [] }
        var hits = [SearchHit]()
        hits.reserveCapacity(docs.count)

        for doc in docs {
            if let category, doc.record.category != category { continue }
            if let hit = score(doc, with: query) {
                hits.append(hit)
            }
        }

        let sorted = hits.sorted {
            $0.score != $1.score
                ? $0.score > $1.score
                : ($0.record.takenAt ?? .distantPast) > ($1.record.takenAt ?? .distantPast)
        }
        return Array(sorted.prefix(limit))
    }

    /// 全量按时间倒序，用于空查询时浏览。
    static func browse(docs: [IndexedDoc], category: DocCategory?, limit: Int = 600) -> [SearchHit] {
        let filtered = category.map { value in docs.filter { $0.record.category == value } } ?? docs
        return filtered
            .sorted { ($0.record.takenAt ?? .distantPast) > ($1.record.takenAt ?? .distantPast) }
            .prefix(limit)
            .map { SearchHit(doc: $0, score: 0, reasons: []) }
    }

    private static func score(_ doc: IndexedDoc, with query: ParsedQuery) -> SearchHit? {
        var score = 0.0
        var reasons = [String]()
        let haystack = doc.haystack
        let record = doc.record

        for candidate in query.candidates where candidate.count >= 2 {
            if haystack.contains(candidate) {
                score += 900 + Double(candidate.count) * 60
                if reasons.count < 4 { reasons.append("命中「\(candidate)」") }
            }
        }

        let coverage = doc.signature.coverage(of: query.signature)
        if coverage > 0 {
            score += coverage * 240
            if coverage >= 0.99, reasons.isEmpty { reasons.append("内容匹配") }
        }

        for run in query.digitRuns where run.count >= 3 {
            if let matched = record.idNumbers.first(where: { $0.contains(run) }) {
                score += 1400
                reasons.append("证件号含 \(run)（\(masked(matched))）")
            } else if haystack.contains(run) {
                score += 260
                if reasons.count < 4 { reasons.append("文字含 \(run)") }
            }
        }

        if query.normalized.contains("截图"), record.isScreenshot {
            score += 300
            reasons.append("系统截图")
        }
        if query.normalized.contains("收藏"), record.isFavorite {
            score += 250
            reasons.append("已收藏")
        }

        if let intent = query.timeIntent {
            if let takenAt = record.takenAt, intent.range.contains(takenAt) {
                score += 200
                reasons.append(intent.label)
            } else {
                score *= 0.35
            }
        }

        // 没有明确说找视频时，图片优先。
        if record.kind == .video, !query.normalized.contains("视频"), !query.normalized.contains("录像") {
            score -= 120
        }

        guard score > 60 else { return nil }
        return SearchHit(doc: doc, score: score, reasons: unique(reasons).prefix(3).map { $0 })
    }

    /// 保持顺序去重，让最重要的命中理由排在前面。
    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result = [String]()
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    /// 展示证件号时中间打码，避免肩头有人看到全部号码。
    private static func masked(_ idNumber: String) -> String {
        guard idNumber.count == 18 else { return idNumber }
        let head = idNumber.prefix(6)
        let tail = idNumber.suffix(4)
        return "\(head)********\(tail)"
    }
}
