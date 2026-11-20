import Foundation

/// 把用户的口语说法翻译成机器能搜的关键词。
///
/// "帮我找身份证"这句话里真正有用的是"居民身份证/公民身份号码"这些证件上实际印着的字。
/// 这一步做的是同一件事的检索版：把口语展开成证件版面上会出现的词，再一起去问索引。
enum QueryExpander {

    private static let table: [[String]] = [
        ["身份证", "居民身份证", "公民身份号码", "身份号码", "签发机关", "证件", "卡片"],
        ["身份证正面", "身份证", "居民身份证", "姓名", "公民身份号码"],
        ["身份证反面", "身份证", "居民身份证", "签发机关", "有效期限"],
        ["护照", "中华人民共和国护照", "passport", "出入境", "证件"],
        ["驾照", "驾驶证", "机动车驾驶证", "准驾车型", "档案编号", "证件"],
        ["行驶证", "机动车行驶证", "车辆识别代号", "号牌号码", "证件"],
        ["户口", "户口本", "居民户口簿", "常住人口登记卡", "户主", "证件"],
        ["出生证明", "出生医学证明", "新生儿", "母亲姓名", "父亲姓名", "证件", "宝宝"],
        ["结婚证", "中华人民共和国结婚证", "持证人", "登记日期", "证件"],
        ["毕业证", "毕业证书", "学位证书", "学习期限", "证件"],
        ["社保卡", "社会保障卡", "社会保障号码", "医疗保险", "证件", "卡片"],
        ["银行卡", "储蓄卡", "信用卡", "借记卡", "中国银联", "unionpay", "卡片"],
        ["房产证", "不动产权证书", "房屋所有权", "土地使用权", "证件"],
        ["发票", "增值税", "税额", "价税合计", "开票人", "发票号码", "纳税人识别号"],
        ["报销", "发票", "增值税", "小票", "订单"],
        ["合同", "协议书", "甲方", "乙方", "违约责任", "签字盖章"],
        ["病历", "门诊病历", "化验单", "检验报告", "临床诊断", "医院"],
        ["疫苗", "预防接种", "疫苗接种", "接种单位", "免疫规划", "宝宝"],
        ["小票", "收银", "实付", "订单号", "支付成功", "外卖"],
        ["截图", "屏幕", "截屏"],
        ["宝宝", "婴儿", "幼儿", "儿子", "女儿", "小朋友", "孩子"],
        ["全家福", "家人", "合影", "一家"],
        ["海边", "沙滩", "海", "游泳", "度假"],
        ["车", "汽车", "轿车", "车牌", "停车位"],
        ["宠物", "猫", "狗", "小狗", "小猫"],
        ["文件", "文档", "扫描件", "资料", "表格"],
        ["密码", "账号", "验证码", "账号密码"],
        ["机票", "登机牌", "火车票", "高铁", "车票"],
        ["快递", "运单", "收件", "包裹"],
        ["工作", "会议", "白板", "投影", "ppt"]
    ]

    /// 返回归一化后的候选词，最长优先，保证"居民身份证"这种长词先命中并给出理由。
    static func expand(_ rawQuery: String) -> [String] {
        let normalized = TextNormalizer.normalize(rawQuery)
        guard !normalized.isEmpty else { return [] }
        var candidates = Set<String>([normalized])

        // 直接包含某个说法时，把它整行同义词全部拿出来。
        for group in table {
            if group.contains(where: { TextNormalizer.normalize($0) == normalized })
                || normalized.contains(TextNormalizer.normalize(group[0])) {
                for word in group { candidates.insert(TextNormalizer.normalize(word)) }
            }
        }
        // 分类名反查：搜"证件"时铺开所有证件分类的标题与同义词。
        if normalized.contains("证件") || normalized.contains("卡片") || normalized.contains("证明") {
            for category in DocCategory.allCases where category.isPaperwork {
                candidates.insert(TextNormalizer.normalize(category.title))
                for word in category.searchWords {
                    candidates.insert(TextNormalizer.normalize(word))
                }
            }
        }
        if normalized.contains("视频") { candidates.insert(TextNormalizer.normalize("视频")) }

        return candidates
            .filter { !$0.isEmpty && $0.count >= 2 }
            .sorted { $0.count > $1.count }
    }

    /// 从查询里解析时间意图，用于给结果排序加权重。
    struct TimeIntent {
        let range: ClosedRange<Date>
        let label: String
    }

    /// 扫描文本里所有连续数字段，"2024年3月" 会得到 [2024, 3]。
    private static func digitRuns(in text: String) -> [Int] {
        var runs = [Int]()
        var current = ""
        for character in text {
            if let value = character.wholeNumberValue, (0...9).contains(value) {
                current.append(character)
            } else if !current.isEmpty {
                if let number = Int(current) { runs.append(number) }
                current = ""
            }
        }
        if let number = Int(current) { runs.append(number) }
        return runs
    }

    static func timeIntent(of query: String) -> TimeIntent? {
        let normalized = TextNormalizer.normalize(query)
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()

        func make(_ start: Date, _ end: Date, _ label: String) -> TimeIntent {
            TimeIntent(range: min(start, end)...max(start, end), label: label)
        }

        // 相对说法。
        if normalized.contains("去年") {
            return monthRange(year: calendar.component(.year, from: now) - 1, month: nil, label: "去年")
        }
        if normalized.contains("前年") {
            return monthRange(year: calendar.component(.year, from: now) - 2, month: nil, label: "前年")
        }
        if normalized.contains("今年") {
            return monthRange(year: calendar.component(.year, from: now), month: nil, label: "今年")
        }
        if normalized.contains("上个月") {
            if let shifted = calendar.date(byAdding: .month, value: -1, to: now) {
                return monthRange(year: calendar.component(.year, from: shifted),
                                  month: calendar.component(.month, from: shifted),
                                  label: "上个月")
            }
        }
        if normalized.contains("本月") || normalized.contains("这个月") {
            return monthRange(year: calendar.component(.year, from: now),
                              month: calendar.component(.month, from: now),
                              label: "本月")
        }
        if normalized.contains("最近") {
            guard let start = calendar.date(byAdding: .month, value: -3, to: now) else { return nil }
            return make(start, now, "最近三个月")
        }

        // 明确年月：2024年3月 / 2024年 / 3月。
        let runs = digitRuns(in: normalized)
        if let year = runs.first(where: { (1980...2100).contains($0) }), normalized.contains("年") {
            let months = runs.filter { (1...12).contains($0) && $0 != year }
            if normalized.contains("月"), let month = months.first {
                return monthRange(year: year, month: month, label: "\(year)年\(month)月")
            }
            return monthRange(year: year, month: nil, label: "\(year)年")
        }
        if normalized.contains("月") {
            for number in runs where (1...12).contains(number) {
                return monthRange(year: calendar.component(.year, from: now), month: number, label: "\(number)月")
            }
        }
        return nil
    }

    private static func monthRange(year: Int, month: Int?, label: String) -> TimeIntent? {
        let calendar = Calendar(identifier: .gregorian)
        guard let janFirst = calendar.date(from: DateComponents(year: year, month: month ?? 1, day: 1)) else {
            return nil
        }
        let end: Date
        if month == nil {
            guard let nextYear = calendar.date(byAdding: .year, value: 1, to: janFirst) else { return nil }
            end = nextYear.addingTimeInterval(-1)
        } else {
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: janFirst) else { return nil }
            end = nextMonth.addingTimeInterval(-1)
        }
        return TimeIntent(range: janFirst...end, label: label)
    }
}
