import Foundation

/// A rectangle in normalized image coordinates (0...1), origin at the top-left, y grows downward.
public struct Box: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midY: Double { y + height / 2 }
}

/// One recognized piece of text, as produced by an OCR engine.
public struct TextBlock: Equatable, Codable, Sendable {
    public var text: String
    public var box: Box
    public var confidence: Double

    public init(text: String, box: Box, confidence: Double = 1) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

public enum ResultFlag: String, Codable, Sendable, CaseIterable {
    case normal
    case high
    case low
    case positive
    case unknown

    public var symbol: String {
        switch self {
        case .high: return "↑"
        case .low: return "↓"
        case .positive: return "+"
        case .normal, .unknown: return ""
        }
    }

    public var isAbnormal: Bool {
        self == .high || self == .low || self == .positive
    }
}

/// One test row of a lab report.
public struct ParsedItem: Equatable, Codable, Sendable {
    /// The row number printed on the report, if any.
    public var sequence: Int?
    public var name: String
    /// Abbreviation printed in parentheses, e.g. "WBC".
    public var code: String
    /// The result exactly as printed ("5.30", "阴性").
    public var valueText: String
    public var value: Double?
    /// Qualitative words printed next to a numeric result, e.g. "无反应性".
    public var interpretation: String
    public var unit: String
    public var referenceText: String
    public var method: String
    /// The flag printed on the report (↑/↓), if any.
    public var reportedFlag: ResultFlag?
    public var confidence: Double

    public init(
        sequence: Int? = nil,
        name: String,
        code: String = "",
        valueText: String,
        value: Double? = nil,
        interpretation: String = "",
        unit: String = "",
        referenceText: String = "",
        method: String = "",
        reportedFlag: ResultFlag? = nil,
        confidence: Double = 1
    ) {
        self.sequence = sequence
        self.name = name
        self.code = code
        self.valueText = valueText
        self.value = value
        self.interpretation = interpretation
        self.unit = unit
        self.referenceText = referenceText
        self.method = method
        self.reportedFlag = reportedFlag
        self.confidence = confidence
    }

    public var referenceRange: ReferenceRange? { ReferenceRange.parse(referenceText) }

    /// The flag printed on the report, or one derived from the reference range.
    public var flag: ResultFlag {
        LabFlagging.flag(
            reported: reportedFlag,
            value: value,
            valueText: valueText,
            interpretation: interpretation,
            range: referenceRange
        )
    }
}

public struct ParsedReport: Equatable, Codable, Sendable {
    public var hospital: String = ""
    public var specimenNo: String = ""
    public var specimenType: String = ""
    public var department: String = ""
    public var diagnosis: String = ""
    public var instrument: String = ""
    public var collectedAt: Date?
    public var receivedAt: Date?
    public var reportedAt: Date?
    public var items: [ParsedItem] = []

    public init() {}

    /// A short title for the report, derived from the categories of its items ("血常规", "肝功能 · 肾功能").
    public var suggestedTitle: String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for item in items {
            let category = IndicatorCatalog.shared.category(name: item.name, code: item.code, specimen: specimenType)
            if counts[category] == nil { order.append(category) }
            counts[category, default: 0] += 1
        }
        let top = order
            .filter { $0 != IndicatorCatalog.otherCategory }
            .sorted { counts[$0, default: 0] > counts[$1, default: 0] }
            .prefix(2)
        return top.isEmpty ? "检验报告" : top.joined(separator: " · ")
    }
}
