import Foundation

/// 靠"照片里那行字"来判定证件类型。
///
/// 这是苹果自带相册最弱的一环：它靠画面语义，而证件的关键信息恰恰是文字。
/// 这里用端侧 OCR 文本做加权命中，任何一条规则都不出设备。
enum DocumentClassifier {

    struct Rule {
        let category: DocCategory
        /// (关键词, 权重)。关键词一律用归一化后的形式书写。
        let signals: [(String, Int)]
        /// 至少需要拿到的分数。
        let threshold: Int
        /// 形状提示命中时的加分。
        let hintFragments: [String]
        /// 合适的宽高比区间，命中则加分。
        let aspect: ClosedRange<Double>?
    }

    /// 阈值刻意设得保守：宁可归到"其他文档"，也不要满屏假身份证。
    static let rules: [Rule] = [
        Rule(category: .idCard, signals: [
            ("居民身份证", 70), ("公民身份号码", 60), ("签发机关", 45), ("有效期限", 35),
            ("公安局", 25), ("中华人民共和国身份证", 70), ("身份号码", 40),
            ("中华人民共和国", 12), ("姓名", 10), ("性别", 10), ("民族", 14), ("住址", 12), ("出生", 8)
        ], threshold: 60,
           hintFragments: ["idcard", "idcardfront", "idcardback"],
           aspect: 1.3...1.9),

        Rule(category: .passport, signals: [
            ("中华人民共和国护照", 80), ("护照", 40), ("passport", 45), ("出入境", 30),
            ("证件类型", 15), ("有效期至", 15), ("签发地点", 20)
        ], threshold: 55,
           hintFragments: ["passport"],
           aspect: nil),

        Rule(category: .driverLicense, signals: [
            ("机动车驾驶证", 80), ("准驾车型", 55), ("档案编号", 45), ("驾驶证", 40),
            ("初次领证日期", 50), ("记分", 30), ("驾车", 10)
        ], threshold: 55,
           hintFragments: ["driverlicense", "drivinglicense"],
           aspect: 1.2...2.0),

        Rule(category: .vehicleLicense, signals: [
            ("机动车行驶证", 85), ("行驶证", 45), ("车辆识别代号", 55), ("发动机号码", 45),
            ("核定载人数", 40), ("检验记录", 30), ("号牌号码", 45)
        ], threshold: 55,
           hintFragments: ["vehiclelicense"],
           aspect: 1.2...2.0),

        Rule(category: .householdRegister, signals: [
            ("常住人口登记卡", 85), ("居民户口簿", 85), ("户口", 40), ("户主", 45),
            ("户号", 30), ("与户主关系", 55), ("兵役状况", 35)
        ], threshold: 55,
           hintFragments: [],
           aspect: nil),

        Rule(category: .birthCertificate, signals: [
            ("出生医学证明", 90), ("出生证明", 60), ("新生儿姓名", 55), ("母亲姓名", 45),
            ("父亲姓名", 45), ("出生时间", 25), ("医疗保健机构", 40)
        ], threshold: 55,
           hintFragments: [],
           aspect: nil),

        Rule(category: .marriageCertificate, signals: [
            ("结婚证", 70), ("中华人民共和国结婚证", 90), ("婚姻关系", 40),
            ("持证人", 25), ("登记日期", 25), ("补办", 20)
        ], threshold: 50,
           hintFragments: [],
           aspect: nil),

        Rule(category: .diploma, signals: [
            ("毕业证书", 75), ("学位证书", 70), ("毕业时间", 35), ("专业", 25),
            ("学习期限", 35), ("校名", 20), ("修完", 25)
        ], threshold: 50,
           hintFragments: [],
           aspect: nil),

        Rule(category: .socialSecurityCard, signals: [
            ("社会保障卡", 85), ("社保卡", 60), ("医疗保险", 45), ("社会保障号码", 60),
            ("就诊", 25), ("参保", 35)
        ], threshold: 55,
           hintFragments: ["healthinsurancecard"],
           aspect: 1.3...1.9),

        Rule(category: .bankCard, signals: [
            ("银行卡", 50), ("储蓄卡", 55), ("信用卡", 55), ("借记卡", 60),
            ("unionpay", 40), ("中国银联", 45), ("validthru", 50), ("cvv", 45),
            ("持卡人", 35), ("银行", 20), ("accountno", 30)
        ], threshold: 45,
           hintFragments: [],
           aspect: 1.4...1.7),

        Rule(category: .realEstate, signals: [
            ("不动产权证书", 90), ("房产证", 70), ("房屋所有权", 60), ("土地使用权", 45),
            ("共有情况", 40), ("坐落", 25), ("丘权号", 40)
        ], threshold: 55,
           hintFragments: [],
           aspect: nil),

        Rule(category: .invoice, signals: [
            ("发票", 45), ("增值税", 45), ("税额", 50), ("价税合计", 60),
            ("开票人", 50), ("发票号码", 60), ("纳税人识别号", 55), ("普通发票", 45),
            ("电子发票", 55), ("校验码", 30), ("收款人", 20)
        ], threshold: 50,
           hintFragments: ["medicalbill"],
           aspect: nil),

        Rule(category: .contract, signals: [
            ("合同", 40), ("协议书", 45), ("甲方", 55), ("乙方", 55), ("丙方", 45),
            ("违约责任", 60), ("甲乙双方", 60), ("条款", 25), ("签字盖章", 40), ("本合同", 55)
        ], threshold: 50,
           hintFragments: [],
           aspect: nil),

        Rule(category: .medical, signals: [
            ("门诊病历", 70), ("化验单", 65), ("检验报告", 60), ("检查所见", 50),
            ("诊断", 35), ("临床诊断", 55), ("医院", 20), ("超声", 30),
            ("报告日期", 35), ("样本", 25), ("参考值", 45)
        ], threshold: 50,
           hintFragments: ["prescription", "medicalreport"],
           aspect: nil),

        Rule(category: .vaccine, signals: [
            ("预防接种", 80), ("疫苗接种", 70), ("疫苗", 45), ("接种单位", 55),
            ("免疫规划", 55), ("针次", 40), ("批号", 25)
        ], threshold: 50,
           hintFragments: [],
           aspect: nil),

        Rule(category: .receipt, signals: [
            ("小票", 50), ("收银", 40), ("合计", 25), ("实付", 40), ("订单号", 50),
            ("外卖", 40), ("美团", 35), ("淘宝", 30), ("京东", 30), ("支付成功", 50),
            ("商品名", 40), ("单价", 30), ("二维码", 12)
        ], threshold: 45,
           hintFragments: ["receipt", "shippinglabel", "boardingpass"],
           aspect: nil)
    ]

    /// 场景标签里出现这些词，说明大概率是拍文档/卡片，用来做兑底。
    private static let documentLabelFragments = [
        "identity card", "id card", "paper", "document", "passport", "credit card",
        "bank card", "driver license", "poster", "receipt", "currency", "ticket", "form"
    ]

    struct Decision {
        let category: DocCategory
        let score: Double
        let hits: [String]
    }

    /// - Parameters:
    ///   - haystack: 已经归一化的 OCR 文本
    ///   - labels: Vision 场景标签（英文，保留原样便于中英双检）
    ///   - hints: 文档类型提示
    ///   - aspect: 照片宽高比
    ///   - isScreenshot: 是否系统截图
    static func decide(haystack: String,
                       labels: [String],
                       hints: [String],
                       aspect: Double,
                       isScreenshot: Bool) -> Decision {
        var best: (rule: Rule, score: Int, hits: [String])?

        for rule in rules {
            var score = 0
            var hits = [String]()
            for (keyword, weight) in rule.signals {
                let normalized = TextNormalizer.normalize(keyword)
                guard !normalized.isEmpty else { continue }
                if haystack.contains(normalized) {
                    score += weight
                    hits.append(keyword)
                }
            }
            for fragment in rule.hintFragments {
                if hints.contains(where: { $0.lowercased().contains(fragment) }) {
                    score += 60
                    hits.append("形状:\(fragment)")
                }
            }
            if let aspectRange = rule.aspect, aspectRange.contains(aspect) {
                score += 12
            }
            if score >= rule.threshold, best == nil || score > best!.score {
                best = (rule, score, hits)
            }
        }

        if let best {
            let normalizedScore = min(1.0, Double(best.score) / 140.0)
            return Decision(category: best.rule.category, score: normalizedScore, hits: best.hits)
        }

        // 没有证件级关键词，但画面明显是文字资料。
        let textLength = haystack.count
        let looksLikePaper = labels.contains { label in
            documentLabelFragments.contains(where: { label.lowercased().contains($0) })
        }
        if textLength >= 60 || (looksLikePaper && textLength >= 12) {
            return Decision(category: .otherDocument, score: looksLikePaper ? 0.5 : 0.3, hits: ["文字量:\(textLength)"])
        }
        if isScreenshot && textLength >= 12 {
            return Decision(category: .otherDocument, score: 0.4, hits: ["截图含文字"])
        }
        return Decision(category: .life, score: 0.2, hits: [])
    }
}
