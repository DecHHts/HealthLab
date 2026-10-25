import SwiftUI
import SwiftData
import LabParser

struct ReportDetailView: View {
    @Bindable var report: LabReport
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editingResult: LabResult?
    @State private var editingInfo = false
    @State private var confirmDelete = false
    @State private var viewingImage: IdentifiedImage?
    @State private var abnormalOnly = false

    var body: some View {
        List {
            Section {
                LabeledContent("采集时间", value: report.collectedAt.formatted(date: .numeric, time: .shortened))
                if !report.hospital.isEmpty { LabeledContent("医院", value: report.hospital) }
                if !report.specimenType.isEmpty { LabeledContent("标本类型", value: report.specimenType) }
                if !report.specimenNo.isEmpty { LabeledContent("标本编号", value: report.specimenNo) }
                if !report.diagnosis.isEmpty { LabeledContent("诊断", value: report.diagnosis) }
                if !report.note.isEmpty { LabeledContent("备注", value: report.note) }
            }

            if !report.sortedImages.isEmpty {
                Section("原图") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(report.sortedImages) { stored in
                                if let image = UIImage(data: stored.data) {
                                    Button { viewingImage = IdentifiedImage(image: image) } label: {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 96)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Toggle("只看异常（\(report.abnormalCount)）", isOn: $abnormalOnly)
                ForEach(visibleResults) { result in
                    NavigationLink(value: TrendRoute(key: result.indicatorKey)) {
                        ResultRow(result: result)
                    }
                    .contextMenu {
                        Button { editingResult = result } label: { Label("编辑", systemImage: "pencil") }
                        Button(role: .destructive) { context.delete(result) } label: { Label("删除", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { editingResult = result } label: { Label("编辑", systemImage: "pencil") }
                            .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    let results = visibleResults
                    for index in offsets { context.delete(results[index]) }
                }
            } header: {
                Text("检测项目（\(report.results?.count ?? 0)）")
            } footer: {
                Text("点击项目查看历次趋势；右滑编辑，左滑删除。")
            }
        }
        .navigationTitle(report.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { editingInfo = true } label: { Label("编辑报告信息", systemImage: "pencil") }
                Button(role: .destructive) { confirmDelete = true } label: { Label("删除报告", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(item: $editingResult) { result in
            NavigationStack { ResultEditor(result: result) }
        }
        .sheet(isPresented: $editingInfo) {
            NavigationStack { ReportInfoEditor(report: report) }
        }
        .fullScreenCover(item: $viewingImage) { ImageViewer(image: $0.image) }
        .confirmationDialog("删除这份报告和其中的全部检测结果？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                // Leave the screen first: deleting while this view still renders the report can crash.
                let report = report
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    context.delete(report)
                }
            }
        }
    }

    private var visibleResults: [LabResult] {
        abnormalOnly ? report.sortedResults.filter { $0.flag.isAbnormal } : report.sortedResults
    }
}

struct ResultRow: View {
    let result: LabResult

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                Text([result.code, result.referenceText.split(separator: "\n").first.map(String.init) ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                ValueText(text: result.valueText, flag: result.flag)
                Text([result.unit, result.interpretation].filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Edits a saved result in place.
struct ResultEditor: View {
    @Bindable var result: LabResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("项目") {
                LabeledTextField("名称", text: $result.name)
                LabeledTextField("缩写", text: $result.code)
            }
            Section("结果") {
                LabeledTextField("结果", text: $result.valueText)
                LabeledTextField("定性结果", text: $result.interpretation)
                LabeledTextField("单位", text: $result.unit)
                FlagPicker(flag: $result.reportedFlag, derived: result.flag)
            }
            Section("参考范围") {
                TextField("如 3.50-9.50", text: $result.referenceText, axis: .vertical)
            }
            Section("检验方法") {
                TextField("可选", text: $result.method)
            }
        }
        .navigationTitle("编辑项目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        // Also runs when the sheet is swiped away.
        .onDisappear {
            result.value = LabText.number(result.valueText)
            result.unit = LabText.unit(result.unit)
            result.refreshDerivedFields()
        }
    }
}

struct ReportInfoEditor: View {
    @Bindable var report: LabReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("标题", text: $report.title)
            DatePicker("采集时间", selection: $report.collectedAt)
            LabeledTextField("医院", text: $report.hospital)
            LabeledTextField("标本编号", text: $report.specimenNo)
            LabeledTextField("标本类型", text: $report.specimenType)
            LabeledTextField("诊断", text: $report.diagnosis)
            Section("备注") {
                TextField("如：空腹、服药情况", text: $report.note, axis: .vertical)
            }
        }
        .navigationTitle("报告信息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onDisappear {
            for result in report.results ?? [] {
                result.collectedAt = report.collectedAt
                result.refreshDerivedFields()
            }
        }
    }
}
