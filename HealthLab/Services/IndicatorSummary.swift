import Foundation
import LabParser

/// All results of one indicator, newest first.
struct IndicatorSummary: Identifiable {
    let key: String
    let results: [LabResult]

    var id: String { key }
    var latest: LabResult { results[0] }
    var name: String { latest.name }
    var code: String { latest.code }
    var category: String { latest.category }
    var hasAbnormal: Bool { results.contains { $0.flag.isAbnormal } }

    /// Numeric points in the latest unit, in time order, for charts.
    var points: [LabResult] { results.filter { $0.value != nil && $0.unit == latest.unit }.reversed() }

    /// Groups results by indicator, ordered by category and then by the row order of the latest report.
    static func build(from results: [LabResult]) -> [IndicatorSummary] {
        let grouped = Dictionary(grouping: results, by: \.indicatorKey)
        let order = IndicatorCatalog.categoryOrder
        return grouped
            .map { key, values in
                IndicatorSummary(key: key, results: values.sorted { $0.collectedAt > $1.collectedAt })
            }
            .sorted { a, b in
                let ca = order.firstIndex(of: a.category) ?? order.count
                let cb = order.firstIndex(of: b.category) ?? order.count
                if ca != cb { return ca < cb }
                if a.latest.sortIndex != b.latest.sortIndex { return a.latest.sortIndex < b.latest.sortIndex }
                return a.name < b.name
            }
    }
}
