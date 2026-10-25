import SwiftUI
import SwiftData
import LabParser

/// A spreadsheet of indicator × checkup date, like a multi-dimensional table: filter by category,
/// show only abnormal indicators, search, and export everything as CSV.
struct MatrixView: View {
    @Query(sort: \LabResult.collectedAt, order: .reverse) private var results: [LabResult]
    @Query(sort: \LabReport.collectedAt, order: .reverse) private var reports: [LabReport]
    @State private var category = MatrixView.allCategories
    @State private var abnormalOnly = false
    @State private var search = ""

    static let allCategories = "全部"
    private let nameWidth: CGFloat = 128
    private let cellWidth: CGFloat = 88
    private let rowHeight: CGFloat = 48

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    ContentUnavailableView("还没有数据", systemImage: "tablecells",
                                           description: Text("导入报告后，这里会按「项目 × 日期」排成表格。"))
                } else {
                    VStack(spacing: 0) {
                        filterBar
                        Divider()
                        grid
                    }
                }
            }
            .navigationTitle("数据表格")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索项目")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: CSVFile(reports: reports), preview: SharePreview("体检记录.csv")) {
                        Label("导出 CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(reports.isEmpty)
                }
            }
            .navigationDestination(for: TrendRoute.self) { TrendView(indicatorKey: $0.key) }
            .navigationDestination(for: LabReport.self) { ReportDetailView(report: $0) }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Menu {
                    Picker("分类", selection: $category) {
                        ForEach([Self.allCategories] + categories, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    Label(category, systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
                Toggle("只看有异常的项目", isOn: $abnormalOnly)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                Text("\(rows.count) 项 × \(days.count) 次")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var grid: some View {
        let days = days
        let rows = rows
        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                // Frozen first column.
                VStack(spacing: 0) {
                    headerCell("项目", width: nameWidth, alignment: .leading)
                    ForEach(rows) { row in
                        NavigationLink(value: TrendRoute(key: row.key)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).font(.subheadline).lineLimit(1)
                                Text(row.code).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: nameWidth - 12, height: rowHeight, alignment: .leading)
                            .padding(.leading, 12)
                        }
                        .buttonStyle(.plain)
                        .background(Color(.secondarySystemBackground))
                        .overlay(alignment: .bottom) { Divider() }
                    }
                }
                Divider()
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(days, id: \.self) { day in headerCell(day.shortDayString, width: cellWidth) }
                        }
                        ForEach(rows) { row in
                            let byDay = Dictionary(row.results.map { (Calendar.current.startOfDay(for: $0.collectedAt), $0) },
                                                   uniquingKeysWith: { first, _ in first })
                            HStack(spacing: 0) {
                                ForEach(days, id: \.self) { day in
                                    cell(byDay[day])
                                }
                            }
                            .overlay(alignment: .bottom) { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment = .center) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: alignment == .leading ? width - 12 : width, height: 32, alignment: alignment)
            .padding(.leading, alignment == .leading ? 12 : 0)
            .background(Color(.tertiarySystemBackground))
            .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func cell(_ result: LabResult?) -> some View {
        if let result {
            NavigationLink(value: TrendRoute(key: result.indicatorKey)) {
                VStack(spacing: 1) {
                    ValueText(text: result.valueText, flag: result.flag).font(.subheadline)
                    Text(result.unit).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: cellWidth, height: rowHeight)
                .background(result.flag.isAbnormal ? result.flag.color.opacity(0.08) : .clear)
            }
            .buttonStyle(.plain)
        } else {
            Text("—")
                .foregroundStyle(.quaternary)
                .frame(width: cellWidth, height: rowHeight)
        }
    }

    /// Checkup days, newest first. Reports collected on the same day share a column.
    private var days: [Date] {
        let calendar = Calendar.current
        return Array(Set(filteredResults.map { calendar.startOfDay(for: $0.collectedAt) })).sorted(by: >)
    }

    private var categories: [String] {
        let present = Set(results.map(\.category))
        return IndicatorCatalog.categoryOrder.filter { present.contains($0) }
    }

    private var filteredResults: [LabResult] {
        rows.flatMap(\.results)
    }

    private var rows: [IndicatorSummary] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return IndicatorSummary.build(from: results).filter { row in
            (category == Self.allCategories || row.category == category)
                && (!abnormalOnly || row.hasAbnormal)
                && (query.isEmpty || row.name.lowercased().contains(query) || row.code.lowercased().contains(query))
        }
    }
}
