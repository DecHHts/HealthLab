import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

struct ReportListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LabReport.collectedAt, order: .reverse) private var reports: [LabReport]

    @State private var showPhotoPicker = false
    @State private var showScanner = false
    @State private var showFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importBatch: ImportBatch?
    @State private var scannedImages: [UIImage] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if reports.isEmpty {
                    ContentUnavailableView {
                        Label("还没有报告", systemImage: "doc.text.viewfinder")
                    } description: {
                        Text("从相册选择体检报告截图，或扫描纸质报告，自动识别所有检测项目。")
                    } actions: {
                        Button("从相册导入") { showPhotoPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("体检报告")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { importMenu }
            }
            .navigationDestination(for: LabReport.self) { ReportDetailView(report: $0) }
            .navigationDestination(for: TrendRoute.self) { TrendView(indicatorKey: $0.key) }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            loadFiles(result)
        }
        // The review sheet opens only after the scanner is fully dismissed; presenting both at once drops the sheet.
        .fullScreenCover(isPresented: $showScanner, onDismiss: {
            if !scannedImages.isEmpty { importBatch = ImportBatch(images: scannedImages) }
            scannedImages = []
        }) {
            DocumentScanner { images in
                scannedImages = images
                showScanner = false
            }
            .ignoresSafeArea()
        }
        .sheet(item: $importBatch) { batch in
            ImportReviewView(images: batch.images)
                .interactiveDismissDisabled()
        }
        .alert("导入失败", isPresented: .constant(loadError != nil), presenting: loadError) { _ in
            Button("好") { loadError = nil }
        } message: { Text($0) }
    }

    private var list: some View {
        List {
            ForEach(reportsByYear, id: \.year) { group in
                Section(String(group.year)) {
                    ForEach(group.reports) { report in
                        NavigationLink(value: report) { ReportRow(report: report) }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(group.reports[index]) }
                    }
                }
            }
        }
    }

    private var importMenu: some View {
        Menu {
            Button { showPhotoPicker = true } label: { Label("从相册选择", systemImage: "photo.on.rectangle") }
            if VNDocumentCameraViewController.isSupported {
                Button { showScanner = true } label: { Label("扫描纸质报告", systemImage: "doc.viewfinder") }
            }
            Button { showFileImporter = true } label: { Label("从文件选择", systemImage: "folder") }
        } label: {
            Image(systemName: "plus")
        }
    }

    private var reportsByYear: [(year: Int, reports: [LabReport])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: reports) { calendar.component(.year, from: $0.collectedAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        if images.isEmpty {
            loadError = "没有读取到图片"
        } else {
            importBatch = ImportBatch(images: images)
        }
    }

    private func loadFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            loadError = error.localizedDescription
        case .success(let urls):
            let images = urls.compactMap { url -> UIImage? in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
            }
            if images.isEmpty {
                loadError = "没有读取到图片"
            } else {
                importBatch = ImportBatch(images: images)
            }
        }
    }
}

struct ImportBatch: Identifiable {
    let id = UUID()
    let images: [UIImage]
}

struct TrendRoute: Hashable {
    let key: String
}

struct ReportRow: View {
    let report: LabReport

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(report.title).font(.headline)
                Text([report.collectedAt.dayString, report.hospital].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let abnormal = report.abnormalCount
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(report.results?.count ?? 0) 项").font(.subheadline).foregroundStyle(.secondary)
                if abnormal > 0 {
                    Text("\(abnormal) 项异常")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.12), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// VisionKit's document camera, which finds the page edges and corrects perspective.
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map(scan.imageOfPage(at:)))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}
