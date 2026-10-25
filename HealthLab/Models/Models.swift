import Foundation
import SwiftData
import LabParser

// Every stored property has a default and relationships are optional, so the schema can move to
// CloudKit sync later without a migration.

@Model
final class LabReport {
    var id: UUID = UUID()
    var title: String = ""
    var hospital: String = ""
    var specimenNo: String = ""
    var specimenType: String = ""
    var department: String = ""
    var diagnosis: String = ""
    var instrument: String = ""
    var note: String = ""
    var collectedAt: Date = Date()
    var reportedAt: Date?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \LabResult.report)
    var results: [LabResult]? = []

    @Relationship(deleteRule: .cascade, inverse: \ReportImage.report)
    var images: [ReportImage]? = []

    init(title: String, collectedAt: Date) {
        self.title = title
        self.collectedAt = collectedAt
    }

    var sortedResults: [LabResult] {
        (results ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var sortedImages: [ReportImage] {
        (images ?? []).sorted { $0.pageIndex < $1.pageIndex }
    }

    var abnormalCount: Int {
        (results ?? []).filter { $0.flag.isAbnormal }.count
    }
}

@Model
final class LabResult {
    var id: UUID = UUID()
    /// Groups the same test across reports (see `IndicatorCatalog.indicatorKey`).
    var indicatorKey: String = ""
    var name: String = ""
    var code: String = ""
    var category: String = ""
    var valueText: String = ""
    var value: Double?
    var interpretation: String = ""
    var unit: String = ""
    var referenceText: String = ""
    var refLow: Double?
    var refHigh: Double?
    var flagRaw: String = ResultFlag.unknown.rawValue
    /// The flag printed on the report or chosen by the user; nil means derive it from the reference range.
    var reportedFlagRaw: String?
    var method: String = ""
    var sortIndex: Int = 0
    /// Copied from the report so trend queries need no join.
    var collectedAt: Date = Date()
    var report: LabReport?

    init() {}

    var flag: ResultFlag {
        ResultFlag(rawValue: flagRaw) ?? .unknown
    }

    var reportedFlag: ResultFlag? {
        get { reportedFlagRaw.flatMap(ResultFlag.init(rawValue:)) }
        set { reportedFlagRaw = newValue?.rawValue }
    }

    /// Re-derives the catalog fields and the flag after the name, code, value or reference was edited.
    func refreshDerivedFields() {
        let catalog = IndicatorCatalog.shared
        let specimen = report?.specimenType ?? ""
        indicatorKey = catalog.indicatorKey(name: name, code: code, specimen: specimen)
        category = catalog.category(name: name, code: code, specimen: specimen)
        let range = ReferenceRange.parse(referenceText)
        refLow = range?.low
        refHigh = range?.high
        flagRaw = LabFlagging.flag(
            reported: reportedFlag,
            value: value,
            valueText: valueText,
            interpretation: interpretation,
            range: range
        ).rawValue
    }
}

@Model
final class ReportImage {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var data: Data = Data()
    var pageIndex: Int = 0
    var report: LabReport?

    init(data: Data, pageIndex: Int) {
        self.data = data
        self.pageIndex = pageIndex
    }
}
