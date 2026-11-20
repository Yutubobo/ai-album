import Foundation

/// 中文检索的基础设施：文本归一化 + bigram 签名。
///
/// 中文没有空格，做全文检索通常要分词。这里刻意不引入任何分词库，改用
/// "相邻两字组成的 bigram + 布隆签名"：既不需要词典，也不会因为分词错误漏召回。
/// 例如"居民身份证"包含 bigram 居民/民身/身份/份证，查询"身份证"只需 身份+份证
/// 两个 bigram 都在里面就能命中，精度由"份证"这种罕见组合保证。
enum TextNormalizer {

    /// 归一化：全角转半角、去音调、大小写统一、只保留字母数字与汉字（含 CJK）。
    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(options: [.widthCaseInsensitive,
                                           .diacriticInsensitive,
                                           .caseInsensitive],
                                 locale: Locale(identifier: "zh_CN"))
        var out = String()
        out.reserveCapacity(folded.count)
        for character in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(character) {
                out.unicodeScalars.append(character)
            }
        }
        return out
    }

    /// 从任意文本里抽出所有 bigram，单字文本退化为单字。
    static func bigrams(of text: String) -> [String] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }
        if chars.count == 1 { return [String(chars[0])] }
        var result = [String]()
        result.reserveCapacity(chars.count - 1)
        for index in 0..<(chars.count - 1) {
            result.append(String([chars[index], chars[index + 1]]))
        }
        return result
    }
}

/// 4096 位定长签名。一张照片的文本不管多长，占用恒定 512 字节。
/// 查询时只要做一次按位与加 popcount，几千张照片的检索在手机上是一毫秒级。
struct TextSignature: Hashable {
    static let bitCount = 4096
    static let wordCount = TextSignature.bitCount / 64

    var words: [UInt64]

    init() {
        words = [UInt64](repeating: 0, count: TextSignature.wordCount)
    }

    init(tokens: some Sequence<String>) {
        self.init()
        for token in tokens { add(token) }
    }

    mutating func add(_ token: String) {
        let hash = TextSignature.fnv1a(token)
        let wordIndex = Int(hash % UInt64(TextSignature.wordCount))
        let bitIndex = UInt64((hash / UInt64(TextSignature.wordCount)) % 64)
        words[wordIndex] |= (UInt64(1) << bitIndex)
    }

    /// 返回 other 里有多少位被 self 覆盖，即查询召回率。
    func coverage(of other: TextSignature) -> Double {
        var total = 0
        var matched = 0
        for index in 0..<TextSignature.wordCount {
            let needed = other.words[index]
            guard needed != 0 else { continue }
            total += needed.nonzeroBitCount
            matched += (needed & words[index]).nonzeroBitCount
        }
        guard total > 0 else { return 0 }
        return Double(matched) / Double(total)
    }

    /// 相似度，用于"找相似照片"。
    func similarity(to other: TextSignature) -> Double {
        var total = 0
        var shared = 0
        for index in 0..<TextSignature.wordCount {
            let a = words[index]
            let b = other.words[index]
            total += max(a.nonzeroBitCount, b.nonzeroBitCount)
            shared += (a & b).nonzeroBitCount
        }
        guard total > 0 else { return 0 }
        return Double(shared) / Double(total)
    }

    private static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

extension TextSignature {
    /// 由一条记录构造检索文本与其签名。
    static func build(for record: PhotoRecord) -> (String, TextSignature) {
        var pieces = [record.ocrText]
        pieces.append(contentsOf: record.labels)
        pieces.append(contentsOf: record.shapeHints)
        pieces.append(record.category.title)
        pieces.append(contentsOf: record.category.searchWords)
        pieces.append(contentsOf: record.idNumbers)
        if record.isScreenshot { pieces.append("截图") }
        if record.isFavorite { pieces.append("收藏") }
        if let takenAt = record.takenAt {
            pieces.append(PhotoRecord.dayFormatter.string(from: takenAt))
            let year = Calendar(identifier: .gregorian).component(.year, from: takenAt)
            pieces.append(String(year))
        }
        let haystack = TextNormalizer.normalize(pieces.joined(separator: " "))
        var signature = TextSignature()
        for bigram in TextNormalizer.bigrams(of: haystack) {
            signature.add(bigram)
        }
        for token in haystack.split(on: CharacterSet.decimalDigits.inverted) {
            signature.add(token)
        }
        return (haystack, signature)
    }
}

extension String {
    /// 按"非数字片段"切开，把连续数字单独取出来做签名，支持号码片段检索。
    fileprivate func split(on separators: CharacterSet) -> [String] {
        var chunks = [String]()
        var current = String()
        for scalar in unicodeScalars {
            if separators.contains(scalar) {
                if !current.isEmpty { chunks.append(current); current = "" }
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
