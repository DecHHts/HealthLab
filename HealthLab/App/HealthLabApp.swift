import SwiftUI
import SwiftData
import LabParser

@main
struct HealthLabApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [LabReport.self, LabResult.self, ReportImage.self])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("catalogVersion") private var catalogVersion = 0

    var body: some View {
        TabView {
            ReportListView()
                .tabItem { Label("报告", systemImage: "doc.text.magnifyingglass") }
            MatrixView()
                .tabItem { Label("表格", systemImage: "tablecells") }
            IndicatorListView()
                .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
        }
        .task { regroupIfCatalogChanged() }
    }

    /// Re-derives indicator keys and categories of saved results after the built-in catalog changed.
    private func regroupIfCatalogChanged() {
        guard catalogVersion != IndicatorCatalog.version else { return }
        let results = (try? context.fetch(FetchDescriptor<LabResult>())) ?? []
        for result in results { result.refreshDerivedFields() }
        try? context.save()
        catalogVersion = IndicatorCatalog.version
    }
}
