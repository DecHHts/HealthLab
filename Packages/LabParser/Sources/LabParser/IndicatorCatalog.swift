import Foundation

/// A standard test indicator, used to merge the same test across reports and hospitals.
public struct IndicatorDefinition: Equatable, Sendable {
    /// Stable key, also the display abbreviation ("WBC").
    public let key: String
    public let name: String
    public let category: String
    /// Other abbreviations hospitals (or OCR) use for the same test.
    public let codeAliases: [String]
    /// Other Chinese names hospitals use for the same test.
    public let nameAliases: [String]
}

public final class IndicatorCatalog: Sendable {
    public static let shared = IndicatorCatalog()
    /// Bump whenever definitions or matching rules change, so saved results get regrouped.
    public static let version = 4
    public static let otherCategory = "其他"

    public static let categoryOrder = [
        "血常规", "肝功能", "肾功能", "血糖", "血脂", "电解质", "甲状腺", "传染病", "炎症", "尿常规", otherCategory,
    ]

    public let definitions: [IndicatorDefinition]
    private let byCode: [String: IndicatorDefinition]
    private let byName: [String: IndicatorDefinition]

    init(definitions: [IndicatorDefinition] = IndicatorCatalog.builtIn) {
        self.definitions = definitions
        var byCode: [String: IndicatorDefinition] = [:]
        var byName: [String: IndicatorDefinition] = [:]
        for d in definitions {
            for code in [d.key] + d.codeAliases {
                byCode[Normalizer.codeKey(code)] = d
            }
            for name in [d.name] + d.nameAliases {
                byName[Normalizer.cleanName(name)] = d
            }
        }
        self.byCode = byCode
        self.byName = byName
    }

    /// Finds the standard indicator for a row: by a known name first, otherwise by abbreviation, which
    /// covers names that vary between hospitals ("谷丙转氨酶" vs "丙氨酸氨基转移酶", both ALT).
    /// An abbreviation match is dropped when the printed name looks unrelated, because short codes are
    /// reused ("TP" is 总蛋白 in 生化 but 梅毒螺旋体抗体 in 传染病).
    public func match(name: String, code: String) -> IndicatorDefinition? {
        let cleaned = Normalizer.cleanName(name)
        if let byName = byName[cleaned] { return byName }
        let codeKey = Normalizer.codeKey(code)
        guard !codeKey.isEmpty, let d = byCode[codeKey] else { return nil }
        guard Normalizer.containsHan(cleaned) else { return d }
        let labels = ([d.name] + d.nameAliases).map(Normalizer.cleanName)
        return labels.contains(where: { Self.related(cleaned, $0) }) ? d : nil
    }

    /// Repairs a row's name and abbreviation that OCR garbled, using the closest standard indicator.
    ///
    /// "含平均細胞血紅蛋 (NCH)" becomes "平均红细胞血红蛋白量 (MCH)": the abbreviation is at most one character off
    /// and most of the name's characters appear in order. Rows that match nothing stay as printed.
    public func corrected(_ item: ParsedItem) -> ParsedItem {
        let name = Normalizer.cleanName(item.name)
        guard Normalizer.containsHan(name), byName[name] == nil else { return item }
        let codeKey = Normalizer.codeKey(item.code)

        // "mALB", "rT3", "sdLDL-C", "hsCRP": a lowercase prefix names a different test, not an OCR slip.
        let distinctPrefix = item.code.range(of: #"^(?:m|r|sd|hs)[A-Z]"#, options: .regularExpression) != nil

        var best: (definition: IndicatorDefinition, score: Double, codeDistance: Int)?
        for d in definitions {
            let codeDistance = codeKey.isEmpty ? Int.max
                : ([d.key] + d.codeAliases).map { Self.editDistance(codeKey, Normalizer.codeKey($0)) }.min()!
            let labels = ([d.name] + d.nameAliases).map(Normalizer.cleanName)
            let nameScore = labels.map {
                Double(Self.commonSubsequence(name, $0)) / Double(max($0.count, name.count))
            }.max()!
            if codeDistance != 0 {
                if distinctPrefix { continue }
                // A name much longer or shorter than every label is another test ("尿微量白蛋白" vs "白蛋白").
                guard labels.contains(where: { abs($0.count - name.count) <= 2 }) else { continue }
            }
            let accepted: Bool
            switch codeDistance {
            case 0: accepted = nameScore >= 0.4
            case 1 where codeKey.count >= 3: accepted = nameScore >= (codeKey.count >= 5 ? 0.3 : 0.5)
            case Int.max: accepted = nameScore >= 0.75
            default: accepted = false
            }
            guard accepted else { continue }
            let score = nameScore - 0.3 * Double(min(codeDistance, 2))
            if best == nil || score > best!.score { best = (d, score, codeDistance) }
        }
        guard let best else { return item }

        var item = item
        item.name = best.definition.name
        if best.codeDistance != 0, !codeKey.isEmpty { item.code = best.definition.key }
        return item
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = current
            }
        }
        return row[b.count]
    }

    /// Length of the longest common subsequence: characters shared in the same order.
    static func commonSubsequence(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var row = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            var previous = 0
            for j in 1...b.count {
                let current = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous + 1 : max(row[j], row[j - 1])
                previous = current
            }
        }
        return row[b.count]
    }

    /// Two names are related when one contains the other or they share two consecutive characters.
    static func related(_ a: String, _ b: String) -> Bool {
        if a.contains(b) || b.contains(a) { return true }
        let chars = Array(b)
        guard chars.count >= 2 else { return false }
        return (0..<(chars.count - 1)).contains { a.contains(String(chars[$0...($0 + 1)])) }
    }

    /// The key a result is grouped under for trends. Unknown tests get a key from their abbreviation, or their
    /// name. Urine tests are kept apart from blood tests with the same abbreviation (尿 WBC vs 血 WBC).
    public func indicatorKey(name: String, code: String, specimen: String = "") -> String {
        let key: String
        if let d = match(name: name, code: code) {
            key = d.key
        } else {
            let codeKey = Normalizer.codeKey(code)
            // A code that belongs to an unrelated catalog test must not share that test's key.
            key = codeKey.isEmpty || byCode[codeKey] != nil ? "名称:" + Normalizer.cleanName(name) : codeKey
        }
        return Self.isUrine(specimen) ? "尿:" + key : key
    }

    public func category(name: String, code: String, specimen: String = "") -> String {
        if Self.isUrine(specimen) { return Self.urineCategory }
        return match(name: name, code: code)?.category ?? Self.otherCategory
    }

    public static let urineCategory = "尿常规"

    static func isUrine(_ specimen: String) -> Bool {
        specimen.contains("尿")
    }
}

private func def(
    _ key: String, _ name: String, _ category: String,
    codes: [String] = [], names: [String] = []
) -> IndicatorDefinition {
    IndicatorDefinition(key: key, name: name, category: category, codeAliases: codes, nameAliases: names)
}

extension IndicatorCatalog {
    static let builtIn: [IndicatorDefinition] = [
        // 血常规
        def("WBC", "白细胞计数", "血常规", names: ["白细胞", "白细胞数"]),
        def("RBC", "红细胞计数", "血常规", names: ["红细胞", "红细胞数"]),
        def("HGB", "血红蛋白量", "血常规", codes: ["HB", "Hb"], names: ["血红蛋白", "血红蛋白浓度"]),
        def("HCT", "红细胞比积", "血常规", names: ["红细胞压积", "红细胞比容", "血细胞比容"]),
        def("MCV", "平均红细胞体积", "血常规"),
        def("MCH", "平均红细胞血红蛋白量", "血常规", names: ["平均红细胞血红蛋白含量"]),
        def("MCHC", "平均红细胞血红蛋白浓度", "血常规"),
        def("PLT", "血小板计数", "血常规", names: ["血小板", "血小板数"]),
        def("NEUT%", "中性粒细胞比值", "血常规", codes: ["NEU%", "GRAN%", "NE%"], names: ["中性粒细胞百分比", "中性粒细胞百分数"]),
        def("LYMPH%", "淋巴细胞比值", "血常规", codes: ["LYM%", "LY%"], names: ["淋巴细胞百分比", "淋巴细胞百分数"]),
        def("MONO%", "单核细胞比值", "血常规", codes: ["MON%", "MO%"], names: ["单核细胞百分比", "单核细胞百分数"]),
        def("EO%", "嗜酸性粒细胞比值", "血常规", codes: ["EOS%"], names: ["嗜酸性粒细胞百分比", "嗜酸性粒细胞百分数"]),
        def("BASO%", "嗜碱性粒细胞比值", "血常规", codes: ["BAS%", "BA%"], names: ["嗜碱性粒细胞百分比", "嗜碱性粒细胞百分数"]),
        def("NEUT#", "中性粒细胞计数", "血常规", codes: ["NEU#", "GRAN#", "NE#"], names: ["中性粒细胞绝对值", "中性粒细胞数"]),
        def("LYMPH#", "淋巴细胞计数", "血常规", codes: ["LYM#", "LY#"], names: ["淋巴细胞绝对值", "淋巴细胞数"]),
        def("MONO#", "单核细胞计数", "血常规", codes: ["MON#", "MO#"], names: ["单核细胞绝对值", "单核细胞数"]),
        def("EO#", "嗜酸性粒细胞计数", "血常规", codes: ["EOS#"], names: ["嗜酸性粒细胞绝对值", "嗜酸性粒细胞数"]),
        def("BASO#", "嗜碱性粒细胞计数", "血常规", codes: ["BAS#", "BA#"], names: ["嗜碱性粒细胞绝对值", "嗜碱性粒细胞数"]),
        def("RDW-CV", "红细胞分布宽度CV", "血常规", codes: ["RDWCV", "RDW"], names: ["红细胞体积分布宽度CV", "红细胞分布宽度变异系数"]),
        def("RDW-SD", "红细胞分布宽度SD", "血常规", codes: ["RDWSD"], names: ["红细胞体积分布宽度SD", "红细胞分布宽度标准差"]),
        def("PDW", "血小板分布宽度", "血常规", names: ["血小板体积分布宽度"]),
        def("MPV", "平均血小板体积", "血常规"),
        def("P-LCR", "大血小板比值", "血常规", codes: ["PLCR"], names: ["大型血小板比率", "大血小板比率"]),
        def("PCT", "血小板压积", "血常规", names: ["血小板比积", "血小板比容"]),

        // 肝功能
        def("ALT", "丙氨酸氨基转移酶", "肝功能", codes: ["GPT"], names: ["谷丙转氨酶"]),
        def("AST", "天门冬氨酸氨基转移酶", "肝功能", codes: ["GOT"], names: ["谷草转氨酶", "天冬氨酸氨基转移酶"]),
        def("AST/ALT", "天门冬氨酸氨基转移酶/丙氨酸氨基转移酶", "肝功能", codes: ["AST:ALT", "S/L"], names: ["谷草/谷丙"]),
        def("GGT", "γ-谷氨酰基转移酶", "肝功能", codes: ["γ-GT", "R-GT", "Y-GT", "GT"], names: ["谷氨酰转肽酶", "γ-谷氨酰转移酶", "γ-谷氨酰转肽酶"]),
        def("ALP", "碱性磷酸酶", "肝功能", codes: ["AKP"]),
        def("CHE", "胆碱酯酶", "肝功能"),
        def("TBIL", "总胆红素", "肝功能", codes: ["T-BIL", "TB"]),
        def("DBIL", "直接胆红素", "肝功能", codes: ["D-BIL", "DB"], names: ["结合胆红素"]),
        def("IBIL", "间接胆红素", "肝功能", codes: ["I-BIL", "IB"], names: ["非结合胆红素"]),
        def("TP", "总蛋白", "肝功能"),
        def("ALB", "白蛋白", "肝功能", names: ["清蛋白"]),
        def("GLB", "球蛋白", "肝功能", codes: ["GLO"]),
        def("A/G", "白球比", "肝功能", codes: ["A:G"], names: ["白蛋白/球蛋白", "白/球比值"]),
        def("TBA", "总胆汁酸", "肝功能"),
        def("PA", "前白蛋白", "肝功能", codes: ["PAB", "PALB"]),

        // 肾功能
        def("UREA", "尿素", "肾功能", codes: ["BUN", "UN"], names: ["尿素氮"]),
        def("CR", "肌酐", "肾功能", codes: ["CREA", "CRE", "SCR"]),
        def("UA", "尿酸", "肾功能", codes: ["URIC"]),
        def("CYS-C", "胱抑素C", "肾功能", codes: ["CYSC"]),
        def("MALB", "尿微量白蛋白", "肾功能", codes: ["U-MALB", "MAU"], names: ["微量白蛋白"]),
        def("EGFR", "肾小球滤过率", "肾功能", names: ["估算肾小球滤过率"]),
        def("HCO3", "碳酸氢盐", "电解质", codes: ["HC03", "HCO3-", "CO2", "TCO2"], names: ["二氧化碳", "总二氧化碳"]),

        // 血糖
        def("GLU", "葡萄糖", "血糖", codes: ["FPG"], names: ["血糖", "空腹血糖", "空腹葡萄糖"]),
        def("HBA1C", "糖化血红蛋白", "血糖", codes: ["HbA1c"]),
        def("GA", "糖化白蛋白", "血糖", codes: ["GA%"]),

        // 血脂
        def("TC", "总胆固醇", "血脂", codes: ["CHOL", "T-CHO"]),
        def("TG", "甘油三酯", "血脂", names: ["三酰甘油"]),
        def("HDL-C", "高密度脂蛋白胆固醇", "血脂", codes: ["HDL", "HDLC"]),
        def("LDL-C", "低密度脂蛋白胆固醇", "血脂", codes: ["LDL", "LDLC"]),
        def("APOA1", "载脂蛋白A1", "血脂", codes: ["APO-A1", "APOAI"]),
        def("APOB", "载脂蛋白B", "血脂", codes: ["APO-B"]),
        def("LP(A)", "脂蛋白(a)", "血脂", codes: ["LPA"]),
        def("SDLDL-C", "小而密低密度脂蛋白胆固醇", "血脂", codes: ["SDLDL", "SD-LDL"], names: ["小而密低密度脂蛋白"]),

        // 电解质
        def("K", "钾", "电解质"),
        def("NA", "钠", "电解质"),
        def("CL", "氯", "电解质"),
        def("CA", "钙", "电解质"),
        def("P", "磷", "电解质", codes: ["PHOS"], names: ["无机磷"]),
        def("MG", "镁", "电解质"),

        // 甲状腺
        def("TSH", "促甲状腺激素", "甲状腺"),
        def("FT3", "游离三碘甲状腺原氨酸", "甲状腺"),
        def("FT4", "游离甲状腺素", "甲状腺"),
        def("T3", "总三碘甲状腺原氨酸", "甲状腺", codes: ["TT3"]),
        def("T4", "总甲状腺素", "甲状腺", codes: ["TT4"]),
        def("RT3", "反三碘甲状腺原氨酸", "甲状腺", codes: ["R-T3"]),

        // 传染病
        def("HBSAG", "乙型肝炎表面抗原", "传染病", names: ["乙肝表面抗原"]),
        def("HBSAB", "乙型肝炎表面抗体", "传染病", codes: ["Anti-HBs"], names: ["乙肝表面抗体"]),
        def("HBEAG", "乙型肝炎e抗原", "传染病", names: ["乙肝e抗原"]),
        def("HBEAB", "乙型肝炎e抗体", "传染病", codes: ["Anti-HBe"], names: ["乙肝e抗体"]),
        def("HBCAB", "乙型肝炎核心抗体", "传染病", codes: ["Anti-HBc"], names: ["乙肝核心抗体"]),
        def("HIV DUO", "人类免疫缺陷病毒抗原/抗体联合检测", "传染病", codes: ["HIVAg/Ab"]),
        def("HIV-AG", "人类免疫缺陷病毒抗原(E)", "传染病", names: ["人类免疫缺陷病毒抗原"]),
        def("HIV-AB", "人类免疫缺陷病毒抗体(E)", "传染病", names: ["人类免疫缺陷病毒抗体", "艾滋病抗体"]),
        def("ANTI-HCV", "丙型肝炎病毒抗体", "传染病", codes: ["HCV-AB", "HCVAB"], names: ["丙肝抗体"]),
        def("TP-AB", "梅毒螺旋体特异抗体", "传染病", codes: ["TPAB", "TPPA"], names: ["梅毒螺旋体特异性抗体", "梅毒螺旋体抗体", "抗梅毒螺旋体抗体", "梅毒抗体"]),

        // 炎症
        def("CRP", "C反应蛋白", "炎症", names: ["C-反应蛋白"]),
        def("HS-CRP", "超敏C反应蛋白", "炎症", codes: ["HSCRP"]),
        def("ESR", "红细胞沉降率", "炎症", names: ["血沉"]),
    ]
}
