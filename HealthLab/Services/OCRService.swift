import UIKit
import Vision
import LabParser

enum OCRError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "无法读取这张图片"
        }
    }
}

/// On-device text recognition with Apple Vision. Nothing leaves the phone.
enum OCRService {
    static func recognize(_ image: UIImage) async throws -> [TextBlock] {
        guard let cgImage = image.cgImage else { throw OCRError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            // Language correction "fixes" abbreviations such as HBsAg and RDW-CV into words.
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])

            return (request.results ?? []).compactMap { observation -> TextBlock? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let b = observation.boundingBox
                // Vision's origin is bottom-left; the parser expects top-left.
                return TextBlock(
                    text: candidate.string,
                    box: Box(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height),
                    confidence: Double(candidate.confidence)
                )
            }
        }.value
    }
}

#if DEBUG
extension OCRService {
    /// Keeps the raw OCR blocks in Documents/ocr-debug, so parser problems can be reproduced as test fixtures.
    /// The text includes the patient's name and record number, so it is off unless the app is launched with
    /// `-saveOCRForDebugging YES` (Xcode: Product › Scheme › Edit Scheme › Arguments), and only the latest
    /// few dumps are kept.
    static func saveForDebugging(_ blocks: [TextBlock], keep: Int = 6) {
        guard UserDefaults.standard.bool(forKey: "saveOCRForDebugging"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("ocr-debug", isDirectory: true)
        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(blocks).write(to: folder.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(4)).json"))

        // Names start with the timestamp, so sorting by name sorts by age.
        let saved = ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        for old in saved.dropLast(keep) {
            try? files.removeItem(at: folder.appendingPathComponent(old))
        }
    }
}
#endif

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
