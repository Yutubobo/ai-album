import Foundation

/// 照片的媒体类型。视频不做文字识别，只按时间与类别检索。
enum MediaKind: String, Codable {
    case image
    case video
}

/// 本机识别出来的照片类别。所有判定都在设备上完成，不依赖任何网络服务。
enum DocCategory: String, Codable, CaseIterable, Identifiable {
    case idCard
    case passport
    case driverLicense
    case vehicleLicense
    case householdRegister
    case birthCertificate
    case marriageCertificate
    case diploma
    case socialSecurityCard
    case bankCard
    case realEstate
    case invoice
    case contract
    case medical
    case vaccine
    case receipt
    case otherDocument
    case life
    case video
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idCard: return "身份证"
        case .passport: return "护照"
        case .driverLicense: return "驾驶证"
        case .vehicleLicense: return "行驶证"
        case .householdRegister: return "户口本"
        case .birthCertificate: return "出生证明"
        case .marriageCertificate: return "结婚证"
        case .diploma: return "毕业证照"
        case .socialSecurityCard: return "社保卡"
        case .bankCard: return "银行卡"
        case .realEstate: return "房产证明"
        case .invoice: return "发票票据"
        case .contract: return "合同协议"
        case .medical: return "病历化验"
        case .vaccine: return "疫苗本"
        case .receipt: return "小票订单"
        case .otherDocument: return "其他文档"
        case .life: return "生活照片"
        case .video: return "视频"
        case .unknown: return "未分类"
        }
    }

    /// SF Symbols 图标名，用于分类芯片。
    var symbol: String {
        switch self {
        case .idCard: return "person.text.rectangle"
        case .passport: return "book.closed"
        case .driverLicense: return "car"
        case .vehicleLicense: return "truck.box"
        case .householdRegister: return "house.and.flag"
        case .birthCertificate: return "figure.child"
        case .marriageCertificate: return "heart.text.square"
        case .diploma: return "graduationcap"
        case .socialSecurityCard: return "cross.case"
        case .bankCard: return "creditcard"
        case .realEstate: return "building.2"
        case .invoice: return "doc.text"
        case .contract: return "doc.plaintext"
        case .medical: return "stethoscope"
        case .vaccine: return "syringe"
        case .receipt: return "cart"
        case .otherDocument: return "doc.viewfinder"
        case .life: return "photo.on.rectangle"
        case .video: return "video"
        case .unknown: return "questionmark.folder"
        }
    }

    /// 是否属于"证件/票据"这一族，界面上用来一键只看证件。
    var isPaperwork: Bool {
        switch self {
        case .idCard, .passport, .driverLicense, .vehicleLicense, .householdRegister,
             .birthCertificate, .marriageCertificate, .diploma, .socialSecurityCard,
             .bankCard, .realEstate, .invoice, .contract, .medical, .vaccine, .receipt:
            return true
        default:
            return false
        }
    }

    /// 写进检索文本的同义词，让"证件""卡片""证明"这类宽泛说法也能命中。
    var searchWords: [String] {
        switch self {
        case .idCard: return ["身份证", "证件", "卡片", "身份证明", "身份证正面", "身份证反面"]
        case .passport: return ["护照", "证件", "旅行证件", "出入境"]
        case .driverLicense: return ["驾照", "驾驶证", "证件", "开车"]
        case .vehicleLicense: return ["行驶证", "车辆", "证件", "车牌"]
        case .householdRegister: return ["户口本", "户口", "户籍", "证件"]
        case .birthCertificate: return ["出生证明", "出生医学证明", "宝宝", "证件"]
        case .marriageCertificate: return ["结婚证", "婚姻", "证件"]
        case .diploma: return ["毕业证", "学位证", "学历", "证书"]
        case .socialSecurityCard: return ["社保卡", "医保", "社保", "卡片"]
        case .bankCard: return ["银行卡", "储蓄卡", "信用卡", "卡片", "账号"]
        case .realEstate: return ["房产证", "不动产", "房子", "产权"]
        case .invoice: return ["发票", "报销", "票据"]
        case .contract: return ["合同", "协议", "签署"]
        case .medical: return ["病历", "化验单", "检查报告", "医院", "诊断"]
        case .vaccine: return ["疫苗", "预防接种", "接种证", "宝宝"]
        case .receipt: return ["小票", "收据", "订单", "购物"]
        case .otherDocument: return ["文档", "扫描件", "文字", "资料"]
        case .life: return ["照片", "生活"]
        case .video: return ["视频", "录像"]
        case .unknown: return []
        }
    }
}

/// 一张照片在本机索引里落盘的全部内容。
struct PhotoRecord: Codable, Identifiable, Hashable {
    /// PHAsset.localIdentifier，重装 App 后同一相册里保持稳定。
    let id: String
    var takenAt: Date?
    var pixelWidth: Int
    var pixelHeight: Int
    var kind: MediaKind
    var isScreenshot: Bool
    var isFavorite: Bool
    /// Vision 在本机识别出的全部文字。
    var ocrText: String
    /// VNClassifyImageRequest 的场景与物体标签（英文标识）。
    var labels: [String]
    /// 文档形状提示（用字符串记录，避免枚举名变更导致编译失败）。
    var shapeHints: [String]
    var category: DocCategory
    /// 校验通过的身份证号，用于"尾号 1234"这种检索。
    var idNumbers: [String]
    /// 分类置信度，0 到 1。
    var categoryScore: Double
    var analyzedAt: Date

    init(id: String,
         takenAt: Date?,
         pixelWidth: Int,
         pixelHeight: Int,
         kind: MediaKind,
         isScreenshot: Bool,
         isFavorite: Bool,
         ocrText: String = "",
         labels: [String] = [],
         shapeHints: [String] = [],
         category: DocCategory = .unknown,
         idNumbers: [String] = [],
         categoryScore: Double = 0,
         analyzedAt: Date = Date()) {
        self.id = id
        self.takenAt = takenAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.kind = kind
        self.isScreenshot = isScreenshot
        self.isFavorite = isFavorite
        self.ocrText = ocrText
        self.labels = labels
        self.shapeHints = shapeHints
        self.category = category
        self.idNumbers = idNumbers
        self.categoryScore = categoryScore
        self.analyzedAt = analyzedAt
    }

    /// 比例接近身份证（85.6 : 54 ≈ 1.586）时给证件判定加分。
    var aspectRatio: Double {
        guard pixelHeight > 0 else { return 0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    var dateTitle: String {
        guard let takenAt else { return "时间未知" }
        return PhotoRecord.dayFormatter.string(from: takenAt)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()
}

/// 索引完成后常驻内存的检索单元：预归一化的文本 + 签名，避免每次查询重复计算。
struct IndexedDoc {
    let record: PhotoRecord
    let haystack: String
    let signature: TextSignature
}
