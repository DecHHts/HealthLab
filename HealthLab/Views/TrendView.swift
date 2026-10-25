import SwiftUI
import SwiftData
import Charts
import LabParser

/// Every result of one indicator over time: chart with the reference range, statistics, and records.
struct TrendView: View {
    let indicatorKey: String
    @Query private var results: [LabResult]

    init(indicatorKey: String) {
        self.indicatorKey = indicatorKey
        _results = Query(
            filter: #Predicate<LabResult> { $0.indicatorKey == indicatorKey },
            sort: \LabResult.collectedAt,
            order: .reverse
        )
    }

    var body: some View {
        List {
            if let latest = results.first {
                Section {
                    header(latest)
                    if points.count >= 1 {
                        TrendChart(points: points, unit: latest.unit, range: (latest.refLow, latest.refHigh))
                            .frame(height: 220)
                            .padding(.vertical, 8)
                    }
                    if otherUnitCount > 0 {
                        Text("另有 \(otherUnitCount) 次结果单位不是 \(latest.unit)，未画入图表")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if points.count >= 2 {
                    Section("统计") { stats }
                }
                Section("历次结果（\(results.count)）") {
                    ForEach(results) { result in
                        if let report = result.report {
                            NavigationLink(value: report) { HistoryRow(result: result) }
                        } else {
                            HistoryRow(result: result)
                        }
                    }
                }
            } else {
                ContentUnavailableView("没有记录", systemImage: "chart.xyaxis.line")
            }
        }
        .navigationTitle(results.first?.name ?? "趋势")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Numeric results in the latest result's unit, oldest first. Values in other units (another hospital
    /// reporting μmol/L vs mg/dL) are left out of the chart and statistics rather than drawn on one axis.
    private var points: [LabResult] {
        let unit = results.first?.unit ?? ""
        return results.filter { $0.value != nil && $0.unit == unit }.reversed()
    }

    private var otherUnitCount: Int {
        results.filter { $0.value != nil }.count - points.count
    }

    private func header(_ latest: LabResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(latest.code.isEmpty ? latest.category : "\(latest.code) · \(latest.category)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("最近 \(latest.collectedAt.dayString)").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ValueText(text: latest.valueText, flag: latest.flag).font(.largeTitle.weight(.semibold))
                Text(latest.unit).foregroundStyle(.secondary)
                if !latest.interpretation.isEmpty { Text(latest.interpretation).foregroundStyle(.secondary) }
            }
            if !latest.referenceText.isEmpty {
                Text("参考范围 \(latest.referenceText.replacingOccurrences(of: "\n", with: " "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
        let values = points.compactMap(\.value)
        let latest = values[values.count - 1]
        let previous = values[values.count - 2]
        let change = latest - previous
        LabeledContent("较上次") {
            let percent = previous == 0 ? "" : String(format: "（%+.1f%%）", change / previous * 100)
            Text("\(change >= 0 ? "+" : "")\(change.compact)\(percent)")
                .monospacedDigit()
        }
        LabeledContent("最高", value: values.max()!.compact)
        LabeledContent("最低", value: values.min()!.compact)
        LabeledContent("平均", value: (values.reduce(0, +) / Double(values.count)).compact)
        LabeledContent("异常次数", value: "\(results.filter { $0.flag.isAbnormal }.count) / \(results.count)")
    }
}

struct TrendChart: View {
    let points: [LabResult]
    let unit: String
    let range: (low: Double?, high: Double?)

    var body: some View {
        Chart {
            if let high = range.high {
                RuleMark(y: .value("上限", high))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.green.opacity(0.7))
                    .annotation(position: .top, alignment: .leading) {
                        Text("上限 \(high.compact)").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let low = range.low {
                RuleMark(y: .value("下限", low))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.green.opacity(0.7))
                    .annotation(position: .bottom, alignment: .leading) {
                        Text("下限 \(low.compact)").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            ForEach(points) { point in
                LineMark(x: .value("日期", point.collectedAt, unit: .day), y: .value(unit, point.value!))
                    .foregroundStyle(Color.accentColor)
                PointMark(x: .value("日期", point.collectedAt, unit: .day), y: .value(unit, point.value!))
                    .foregroundStyle(point.flag.isAbnormal ? point.flag.color : Color.accentColor)
                    .symbolSize(60)
                    .annotation(position: .top) {
                        Text(point.value!.compact).font(.caption2).foregroundStyle(point.flag.isAbnormal ? point.flag.color : .secondary)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.year(.twoDigits).month(.twoDigits))
            }
        }
    }

    /// Fits the values and the reference bounds, with some headroom for the labels.
    private var yDomain: ClosedRange<Double> {
        let values = points.compactMap(\.value) + [range.low, range.high].compactMap { $0 }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.2, abs(hi) * 0.05, 0.01)
        return (lo - pad)...(hi + pad)
    }
}

struct HistoryRow: View {
    let result: LabResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.collectedAt.dayString)
                Text(result.report?.hospital ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ValueText(text: result.valueText, flag: result.flag)
            Text(result.unit).font(.caption).foregroundStyle(.secondary)
        }
    }
}
