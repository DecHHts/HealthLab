import Foundation
import CoreTransferable
import UniformTypeIdentifiers

enum CSVExporter {
    static let header = ["采集日期", "报告", "医院", "分类", "项目", "缩写", "结果", "单位", "参考范围", "标记", "检验方法"]

    /// One row per result, newest report first. Starts with a UTF-8 BOM so Excel shows Chinese correctly.
    static func csv(for reports: [LabReport]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = [header.map(escape).joined(separator: ",")]
        for report in reports.sorted(by: { $0.collectedAt > $1.collectedAt }) {
            for r in report.sortedResults {
                let fields = [
                    dateFormatter.string(from: report.collectedAt),
                    report.title,
                    report.hospital,
                    r.category,
                    r.name,
                    r.code,
                    r.interpretation.isEmpty ? r.valueText : "\(r.valueText) \(r.interpretation)",
                    r.unit,
                    r.referenceText.replacingOccurrences(of: "\n", with: " "),
                    r.flag.label,
                    r.method,
                ]
                lines.append(fields.map(escape).joined(separator: ","))
            }
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// The CSV export as a shareable file named like "体检记录-20261025.csv".
struct CSVFile: Transferable {
    /// Built up front: SwiftData models must not be read from the export's background thread.
    let text: String

    init(reports: [LabReport]) {
        text = CSVExporter.csv(for: reports)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("体检记录-\(formatter.string(from: Date())).csv")
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
