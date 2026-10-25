import SwiftUI
import SwiftData
import LabParser

/// One recognized report, edited on the review screen before it is saved.
@Observable
final class ReportDraft: Identifiable {
    struct Item: Identifiable {
        let id = UUID()
        var parsed: ParsedItem
    }

    let id = UUID()
    var title: String
    var hospital: String
    var specimenNo: String
    var specimenType: String
    var department: String
    var diagnosis: String
    var instrument: String
    var collectedAt: Date
    /// false when no collection date was found and today's date is only a placeholder.
    var dateRecognized: Bool
    var reportedAt: Date?
    var items: [Item]
    var images: [UIImage]

    init(parsed: ParsedReport, images: [UIImage]) {
        title = parsed.suggestedTitle
        hospital = parsed.hospital
        specimenNo = parsed.specimenNo
        specimenType = parsed.specimenType
        department = parsed.department
        diagnosis = parsed.diagnosis
        instrument = parsed.instrument
        collectedAt = parsed.collectedAt ?? Date()
        dateRecognized = parsed.collectedAt != nil
        reportedAt = parsed.reportedAt
        items = parsed.items.map { Item(parsed: $0) }
        self.images = images
    }

    static func recognize(_ image: UIImage) async throws -> ReportDraft {
        let blocks = try await OCRService.recognize(image)
        #if DEBUG
        OCRService.saveForDebugging(blocks)
        #endif
        return ReportDraft(parsed: ReportParser.parse(blocks), images: [image])
    }

    /// Appends the rows of another page of the same report (for reports longer than one screenshot).
    func merge(_ other: ReportDraft) {
        items += other.items
        images += other.images
        if !dateRecognized, other.dateRecognized {
            collectedAt = other.collectedAt
            dateRecognized = true
        }
        if specimenNo.isEmpty { specimenNo = other.specimenNo }
        if hospital.isEmpty { hospital = other.hospital }
    }

    /// Rows that probably need a look: low OCR confidence, or a missing name or result.
    static func needsAttention(_ item: ParsedItem) -> Bool {
        item.confidence < 0.5 || item.name.isEmpty || item.valueText.isEmpty
    }

    func duplicate(in context: ModelContext) -> LabReport? {
        guard !specimenNo.isEmpty else { return nil }
        let number = specimenNo
        let descriptor = FetchDescriptor<LabReport>(predicate: #Predicate { $0.specimenNo == number })
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func save(in context: ModelContext) -> LabReport {
        let report = LabReport(title: title.isEmpty ? "检验报告" : title, collectedAt: collectedAt)
        report.hospital = hospital
        report.specimenNo = specimenNo
        report.specimenType = specimenType
        report.department = department
        report.diagnosis = diagnosis
        report.instrument = instrument
        report.reportedAt = reportedAt
        context.insert(report)

        let filled = items.filter { !$0.parsed.name.isEmpty || !$0.parsed.valueText.isEmpty }
        for (index, item) in filled.enumerated() {
            let p = item.parsed
            let result = LabResult()
            result.name = p.name
            result.code = p.code
            result.valueText = p.valueText
            result.value = LabText.number(p.valueText)
            result.interpretation = p.interpretation
            result.unit = LabText.unit(p.unit)
            result.referenceText = p.referenceText
            result.method = p.method
            result.reportedFlag = p.reportedFlag
            result.sortIndex = index
            result.collectedAt = collectedAt
            context.insert(result)
            result.report = report
            result.refreshDerivedFields()
        }

        for (index, image) in images.enumerated() {
            guard let data = ImageStore.compressedJPEG(image) else { continue }
            let stored = ReportImage(data: data, pageIndex: index)
            context.insert(stored)
            stored.report = report
        }
        return report
    }
}

enum ImageStore {
    /// Keeps originals readable for checking values while staying around a few hundred KB.
    static func compressedJPEG(_ image: UIImage, maxDimension: CGFloat = 2400) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image.jpegData(compressionQuality: 0.75) }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
