import Foundation

enum Normalizer {
    /// Traditional characters Vision often returns for simplified report text ("結果", "細胞", "紅").
    static let simplified: [Character: Character] = {
        let pairs = "結结細细紅红醫医廣广東东門门區区學学國国華华衛卫縣县檢检驗验測测價价參参單单號号項项稱称計计數数體体積积濃浓鹼碱"
            + "種种試试陰阴陽阳腎肾膽胆鐵铁鈣钙鉀钾鈉钠鎂镁總总間间時时機机臨临診诊斷断報报狀状態态寬宽錄录審审異异蘭兰"
            + "線线維维脂脂酶酶澱淀粉粉膠胶蛋蛋類类發发過过檢检傳传染染質质鏈链鹽盐氫氢鈾铀蟲虫顆颗"
        var map: [Character: Character] = [:]
        var chars = Array(pairs)
        while chars.count >= 2 {
            let (t, s) = (chars.removeFirst(), chars.removeFirst())
            if t != s { map[t] = s }
        }
        return map
    }()

    /// Full-width ASCII to half-width, unified punctuation, simplified characters, collapsed spaces.
    static func basic(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            if let s = simplified[Character(scalar)] {
                out.append(s)
                continue
            }
            switch scalar.value {
            case 0xFF01...0xFF5E:
                out.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            case 0x3000:
                out.append(" ")
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    }

    /// Removes the ☆ / * markers some hospitals print before mutually recognized items.
    static func cleanName(_ name: String) -> String {
        var s = basic(name)
        s = s.replacingOccurrences(of: #"^[\s☆★✩✰⭐*＊·•]+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        return s
    }

    static func cleanCode(_ code: String) -> String {
        basic(code)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            // OCR reads the letter O as zero inside abbreviations: "MON0%", "E0#", "HC03".
            .replacingOccurrences(of: #"(?<=[A-Za-z])0"#, with: "O", options: .regularExpression)
    }

    /// Cleans a reference text: "208. 0-428.0" → "208.0-428.0", "<1,000:" → "<1.000:", "〈" → "<".
    static func reference(_ raw: String) -> String {
        basic(raw)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "〈", with: "<")
            .replacingOccurrences(of: "〉", with: ">")
            .replacingOccurrences(of: #"(\d)\.\s+(\d)"#, with: "$1.$2", options: .regularExpression)
            // "<1,000:无反应性" is OCR's comma for a decimal point; "4,000-10,000" is a thousands separator.
            .replacingOccurrences(of: #"([<>≤≥至]\s?\d),(\d)"#, with: "$1.$2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d),(\d+\s*[:：])"#, with: "$1.$2", options: .regularExpression)
            // The digit zero read as the letter O: "O.400-0.750".
            .replacingOccurrences(of: #"(?<![A-Za-z])O(?=\.\d)"#, with: "0", options: .regularExpression)
    }

    /// Repairs qualitative words OCR garbles in the unit column ("森反应" for "无反应").
    static func interpretation(_ token: String) -> String {
        if token.contains("有反") { return "有反应性" }
        if token.count <= 4, token.contains("反") || token.hasPrefix("森") {
            return "无反应性"
        }
        return token
    }

    /// Key used to match abbreviations across hospitals and OCR noise: "HIV Duo" → "HIVDUO".
    static func codeKey(_ code: String) -> String {
        basic(code)
            .uppercased()
            .replacingOccurrences(of: #"[\s_]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "％", with: "%")
    }

    /// Unifies common unit spellings and OCR misreads.
    static func unit(_ raw: String) -> String {
        var s = basic(raw).trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return s }
        s = s.replacingOccurrences(of: " ", with: "")
        s = s.replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^10[\^ˆ˜~*'’`]?(9|12)/L$"#, with: "10^$1/L", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^102(9|12)/L$"#, with: "10^$1/L", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^(?:u|µ|μ|F)mol/L$"#, with: "μmol/L", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"^CO[TIl1r]$"#, with: "COI", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "%0", with: "‰")
        s = s.replacingOccurrences(of: #"^(?:u|µ|μ)g/L$"#, with: "μg/L", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "%o", with: "‰")
        s = s.replacingOccurrences(of: "mmol/l", with: "mmol/L")
        s = s.replacingOccurrences(of: "u/L", with: "U/L")
        return s
    }

    static func number(_ text: String) -> Double? {
        let s = basic(text)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"^[<>≤≥]=?"#, with: "", options: .regularExpression)
        return Double(s)
    }

    static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isIdeographic }
    }
}

extension NSRegularExpression {
    func firstMatch(in string: String) -> NSTextCheckingResult? {
        firstMatch(in: string, range: NSRange(string.startIndex..., in: string))
    }
}

extension String {
    func group(_ match: NSTextCheckingResult, _ index: Int) -> String {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: self) else { return "" }
        return String(self[range])
    }
}

/// Text helpers for code outside the parser, e.g. when the user edits a recognized row.
public enum LabText {
    public static func number(_ text: String) -> Double? { Normalizer.number(text) }
    public static func unit(_ text: String) -> String { Normalizer.unit(text) }
}
