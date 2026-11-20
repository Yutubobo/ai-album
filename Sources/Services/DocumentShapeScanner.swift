import CoreGraphics

/// 给分类器补充"这张图像看起来是张卡片/纸"的旁证。
///
/// 为什么不用 VisionKit 的 ImageAnalyzer：那套 API（Configuration 的枚举名、
/// analyze 的参数标签）在 iOS 16~18 之间改过名，在没有 Mac 本机编译的条件下，
/// 为它赌上整个工程首次构建不划算。这里改用已经在跑的 VNClassifyImageRequest 标签，
/// 它本身就会给出 identity card、passport、credit card 这类版面结论，
/// 转成 hint 后与规则表里的 hintFragments 完全对齐，零新增依赖、零 API 风险。
enum DocumentShapeScanner {

    /// (Vision 标签片段, 要产出的 hint)。
    private static let mappings: [([String], String)] = [
        (["identity card", "id card", "identification"], "idcard"),
        (["passport"], "passport"),
        (["driver license", "driving licence", "driverlicense"], "driverlicense"),
        (["vehicle registration", "license plate", "number plate"], "vehiclelicense"),
        (["health insurance card", "social security", "insurance card"], "healthinsurancecard"),
        (["bank card", "credit card", "debit card"], "bankcard"),
        (["medical bill", "prescription", "medical report"], "medicalbill"),
        (["receipt", "invoice", "cash register"], "receipt"),
        (["shipping label", "boarding pass", "ticket"], "shippinglabel"),
        (["document", "paper", "poster", "form", "scan"], "document")
    ]

    static func hints(labels: [String]) -> [String] {
        var result = [String]()
        for label in labels {
            let lowered = label.lowercased()
            for (fragments, hint) in mappings where result.count < 6 {
                if fragments.contains(where: { lowered.contains($0) }), !result.contains(hint) {
                    result.append(hint)
                }
            }
        }
        return result
    }
}
