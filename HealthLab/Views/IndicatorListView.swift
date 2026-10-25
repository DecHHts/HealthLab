import SwiftUI
import SwiftData
import Charts
import LabParser

/// All indicators ever recorded, grouped by category, each with its latest value and a sparkline.
struct IndicatorListView: View {
    @Query(sort: \LabResult.collectedAt, order: .reverse) private var results: [LabResult]
    @State private var search = ""
    @State private var abnormalOnly = false

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    ContentUnavailableView("还没有数据", systemImage: "chart.xyaxis.line",
                                           description: Text("导入报告后，这里会按项目显示历次变化。"))
                } else {
                    List {
                        ForEach(sections, id: \.category) { section in
                            Section(section.category) {
                                ForEach(section.indicators) { indicator in
                                    NavigationLink(value: TrendRoute(key: indicator.key)) {
                                        IndicatorRow(indicator: indicator)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $search, prompt: "搜索项目名称或缩写")
                }
            }
            .navigationTitle("指标趋势")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $abnormalOnly) { Label("只看最近异常", systemImage: "exclamationmark.circle") }
                        .toggleStyle(.button)
                }
            }
            .navigationDestination(for: TrendRoute.self) { TrendView(indicatorKey: $0.key) }
            .navigationDestination(for: LabReport.self) { ReportDetailView(report: $0) }
        }
    }

    private var sections: [(category: String, indicators: [IndicatorSummary])] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = IndicatorSummary.build(from: results).filter { indicator in
            (!abnormalOnly || indicator.latest.flag.isAbnormal)
                && (query.isEmpty || indicator.name.lowercased().contains(query) || indicator.code.lowercased().contains(query))
        }
        var order: [String] = []
        var grouped: [String: [IndicatorSummary]] = [:]
        for indicator in filtered {
            if grouped[indicator.category] == nil { order.append(indicator.category) }
            grouped[indicator.category, default: []].append(indicator)
        }
        return order.map { ($0, grouped[$0]!) }
    }
}

struct IndicatorRow: View {
    let indicator: IndicatorSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(indicator.name).lineLimit(1)
                Text([indicator.code, "\(indicator.results.count) 次"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let points = indicator.points
            if points.count >= 2 {
                Chart(points) { point in
                    LineMark(x: .value("日期", point.collectedAt), y: .value("值", point.value!))
                        .foregroundStyle(Color.accentColor)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 60, height: 28)
            }
            VStack(alignment: .trailing, spacing: 2) {
                ValueText(text: indicator.latest.valueText, flag: indicator.latest.flag)
                Text(indicator.latest.unit).font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 64, alignment: .trailing)
        }
    }
}
