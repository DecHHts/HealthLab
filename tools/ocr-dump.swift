// Runs the same Vision OCR as the app and prints the text blocks as JSON (top-left origin, normalized).
// Usage: swift ocr-dump.swift image.jpeg > image.json
import Foundation
import Vision
import AppKit

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot load \(path)")
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: cg).perform([request])

var out: [[String: Any]] = []
for obs in request.results ?? [] {
    guard let top = obs.topCandidates(1).first else { continue }
    let b = obs.boundingBox
    out.append([
        "text": top.string,
        "confidence": Double(top.confidence),
        "x": Double(b.minX), "y": Double(1 - b.maxY),
        "w": Double(b.width), "h": Double(b.height),
    ])
}
let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
