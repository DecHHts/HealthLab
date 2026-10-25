import SwiftUI
import SwiftData
import LabParser

/// Recognizes the selected images, then lets the user check and correct every report before saving.
struct ImportReviewView: View {
    let images: [UIImage]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [ReportDraft] = []
    @State private var selection: UUID?
    @State private var processed = 0
    @State private var failures = 0
    @State private var finished = false

    var body: some View {
        NavigationStack {
            Group {
                if !finished {
                    ProgressView("正在识别 \(processed + 1)/\(images.count)…")
                } else if drafts.isEmpty {
                    ContentUnavailableView("没有识别到内容", systemImage: "exclamationmark.triangle",
                                           description: Text("请换一张更清晰、完整的报告截图再试。"))
                } else {
                    VStack(spacing: 0) {
                        if failures > 0 {
                            Label("\(failures) 张图片识别失败，已跳过", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .padding(.bottom, 8)
                        }
                        if drafts.count > 1 {
                            Picker("报告", selection: $selection) {
                                ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                                    Text("\(index + 1). \(draft.title)").tag(Optional(draft.id))
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding([.horizontal, .bottom])
                        }
                        if let current {
                            DraftEditor(draft: current, otherDrafts: drafts.filter { $0.id != current.id })
                                .id(current.id)
                        }
                    }
                }
            }
            .navigationTitle("核对识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(drafts.count > 1 ? "全部保存" : "保存") { saveAll() }
                        .disabled(!finished || drafts.isEmpty)
                }
                if drafts.count > 1, let current, let index = drafts.firstIndex(where: { $0.id == current.id }) {
                    ToolbarItem(placement: .bottomBar) {
                        Menu("这份报告") {
                            if index > 0 {
                                Button("并入上一份（同一报告的多页截图）") { mergeIntoPrevious(index) }
                            }
                            Button("不保存这份", role: .destructive) { remove(index) }
                        }
                    }
                }
            }
        }
        .task { await recognizeAll() }
    }

    private var current: ReportDraft? {
        drafts.first { $0.id == selection } ?? drafts.first
    }

    private func recognizeAll() async {
        guard !finished else { return }
        for image in images {
            do {
                let draft = try await ReportDraft.recognize(image)
                drafts.append(draft)
            } catch {
                failures += 1
            }
            processed = min(processed + 1, images.count - 1)
        }
        selection = drafts.first?.id
        finished = true
    }

    private func mergeIntoPrevious(_ index: Int) {
        drafts[index - 1].merge(drafts[index])
        selection = drafts[index - 1].id
        drafts.remove(at: index)
    }

    private func remove(_ index: Int) {
        drafts.remove(at: index)
        selection = drafts.first?.id
    }

    private func saveAll() {
        for draft in drafts { draft.save(in: context) }
        dismiss()
    }
}

struct DraftEditor: View {
    @Bindable var draft: ReportDraft
    var otherDrafts: [ReportDraft] = []
    @Environment(\.modelContext) private var context
    @State private var viewingImage: IdentifiedImage?

    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(draft.images.enumerated()), id: \.offset) { _, image in
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
            } footer: {
                Text("点击原图放大，和下面的识别结果对照检查。")
            }

            Section("报告信息") {
                TextField("标题", text: $draft.title)
                DatePicker("采集时间", selection: $draft.collectedAt)
                if !draft.dateRecognized {
                    Label("没有识别到采集时间，请手动选择", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                LabeledTextField("医院", text: $draft.hospital)
                LabeledTextField("标本编号", text: $draft.specimenNo)
                LabeledTextField("标本类型", text: $draft.specimenType)
                if let existing = draft.duplicate(in: context) {
                    Label("已存在相同标本编号的报告（\(existing.collectedAt.dayString) \(existing.title)），保存会产生重复记录",
                          systemImage: "doc.on.doc")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if !draft.specimenNo.isEmpty, otherDrafts.contains(where: { $0.specimenNo == draft.specimenNo }) {
                    Label("这次导入里有另一张图片的标本编号相同，可能是同一份报告，可用下方菜单合并", systemImage: "doc.on.doc")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach($draft.items) { $item in
                    NavigationLink {
                        ItemEditor(item: $item.parsed)
                    } label: {
                        DraftItemRow(item: item.parsed)
                    }
                }
                .onDelete { draft.items.remove(atOffsets: $0) }
                Button {
                    draft.items.append(.init(parsed: ParsedItem(name: "", valueText: "")))
                } label: {
                    Label("添加项目", systemImage: "plus")
                }
            } header: {
                Text("检测项目（\(draft.items.count)）")
            } footer: {
                Text("黄色标记的行可能识别不完整，请点开核对。左滑可删除误识别的行。")
            }
        }
        .fullScreenCover(item: $viewingImage) { item in
            ImageViewer(image: item.image)
        }
    }
}

struct DraftItemRow: View {
    let item: ParsedItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? "（未识别名称）" : item.name)
                Text([item.code, item.referenceText.split(separator: "\n").first.map(String.init) ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                ValueText(text: item.valueText.isEmpty ? "—" : item.valueText, flag: item.flag)
                Text(item.unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .listRowBackground(ReportDraft.needsAttention(item) ? Color.yellow.opacity(0.2) : nil)
    }
}

/// Edits one recognized row before saving.
struct ItemEditor: View {
    @Binding var item: ParsedItem

    var body: some View {
        Form {
            Section("项目") {
                LabeledTextField("名称", text: $item.name)
                LabeledTextField("缩写", text: $item.code)
            }
            Section("结果") {
                LabeledTextField("结果", text: $item.valueText)
                    .onChange(of: item.valueText) { _, text in item.value = LabText.number(text) }
                LabeledTextField("定性结果", text: $item.interpretation)
                LabeledTextField("单位", text: $item.unit)
                FlagPicker(flag: $item.reportedFlag, derived: item.flag)
            }
            Section("参考范围") {
                TextField("如 3.50-9.50", text: $item.referenceText, axis: .vertical)
            }
            Section("检验方法") {
                TextField("可选", text: $item.method)
            }
        }
        .navigationTitle(item.name.isEmpty ? "编辑项目" : item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "自动" follows the reference range; the other options override it.
struct FlagPicker: View {
    @Binding var flag: ResultFlag?
    let derived: ResultFlag

    var body: some View {
        Picker("标记", selection: $flag) {
            Text(flag == nil && !derived.label.isEmpty ? "自动（\(derived.label)）" : "自动").tag(ResultFlag?.none)
            ForEach([ResultFlag.normal, .high, .low, .positive], id: \.self) { option in
                Text(option.label).tag(Optional(option))
            }
        }
    }
}

struct LabeledTextField: View {
    let label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        _text = text
    }

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: $text)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct IdentifiedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Full-screen original with pinch to zoom.
struct ImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: UIScreen.main.bounds.width * scale * pinch)
            }
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = min(max(scale * value.magnification, 1), 5) }
            )
            .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5 } }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
