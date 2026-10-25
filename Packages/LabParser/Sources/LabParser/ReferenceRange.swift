import Foundation

/// A numeric reference interval parsed from text such as "3.50-9.50", "<0.900:无反应性" or "≥90".
public struct ReferenceRange: Equatable, Codable, Sendable {
    public var low: Double?
    public var high: Double?
    /// true when the upper bound itself is outside the range ("<1.000").
    public var highExclusive: Bool
    /// true when the lower bound itself is outside the range (">0.5").
    public var lowExclusive: Bool

    public init(low: Double?, high: Double?, lowExclusive: Bool = false, highExclusive: Bool = false) {
        self.low = low
        self.high = high
        self.lowExclusive = lowExclusive
        self.highExclusive = highExclusive
    }

    public func classify(_ value: Double) -> ResultFlag {
        if let low {
            if value < low || (lowExclusive && value == low) { return .low }
        }
        if let high {
            if value > high || (highExclusive && value == high) { return .high }
        }
        return .normal
    }

    private static let number = #"(\d+(?:\.\d+)?)"#
    private static let rangePattern = try! NSRegularExpression(
        pattern: #"^(?:[\p{Han}]{1,4}[:：]\s*)?"# + number + #"\s*(?:-|~|～|—|–|至)\s*"# + number
    )
    private static let boundPattern = try! NSRegularExpression(
        pattern: #"^(?:[\p{Han}]{1,4}[:：]\s*)?(<=|>=|≤|≥|<|>|＜|＞)\s*"# + number
    )

    /// Parses the first line of a reference text. Returns nil when no numeric interval is found.
    public static func parse(_ text: String) -> ReferenceRange? {
        let firstLine = Normalizer.basic(text)
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        guard !firstLine.isEmpty else { return nil }

        if let m = rangePattern.firstMatch(in: firstLine),
           let low = Double(firstLine.group(m, 1)), let high = Double(firstLine.group(m, 2)) {
            return ReferenceRange(low: low, high: high)
        }
        if let m = boundPattern.firstMatch(in: firstLine), let bound = Double(firstLine.group(m, 2)) {
            switch firstLine.group(m, 1) {
            case "<", "＜": return ReferenceRange(low: nil, high: bound, highExclusive: true)
            case "<=", "≤": return ReferenceRange(low: nil, high: bound)
            case ">", "＞": return ReferenceRange(low: bound, high: nil, lowExclusive: true)
            default: return ReferenceRange(low: bound, high: nil)
            }
        }
        return nil
    }
}

public enum LabFlagging {
    static let positiveWords = ["阳性", "有反应", "检出", "异常"]
    static let negativeWords = ["阴性", "无反应", "未检出", "正常"]
    static let negativeSymbols: Set<String> = ["-", "(-)", "−", "(−)"]

    public static func flag(
        reported: ResultFlag?,
        value: Double?,
        valueText: String,
        interpretation: String,
        range: ReferenceRange?
    ) -> ResultFlag {
        if let reported { return reported }
        let words = valueText + interpretation
        // "未检出" contains "检出", so negatives are checked first.
        if negativeWords.contains(where: { words.contains($0) }) || negativeSymbols.contains(valueText) { return .normal }
        if positiveWords.contains(where: { words.contains($0) }) || valueText.contains("+") || valueText.contains("±") {
            return .positive
        }
        if let value, let range { return range.classify(value) }
        return .unknown
    }
}
