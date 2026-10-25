import Foundation

/// Turns OCR text blocks of a Chinese hospital lab report into a structured report.
///
/// The parser expects the common layout "序号 | 项目名称 (缩写) | 结果 ↑↓ | 单位 | 参考值 | 检验方法".
/// It finds the table's header row, uses the header words' x positions as column boundaries, and treats
/// a row without a result as the continuation of the row above (names and reference texts that wrap).
public enum ReportParser {
    public static func parse(_ blocks: [TextBlock]) -> ParsedReport {
        let lines = groupLines(blocks)
        var report = parseHeader(lines)
        if let table = locateTable(lines) {
            report.items = parseTable(lines: table.rows, columns: table.columns)
        } else {
            report.items = parseWithoutColumns(lines)
        }
        return report
    }

    // MARK: - Lines

    struct Line {
        var blocks: [TextBlock]
        var midY: Double
        var height: Double

        var text: String { blocks.map(\.text).joined(separator: " ") }
        var compact: String { Normalizer.basic(text).replacingOccurrences(of: " ", with: "") }
        var confidence: Double { blocks.map(\.confidence).min() ?? 1 }
    }

    /// Groups blocks whose vertical centers are close into lines, each sorted left to right.
    static func groupLines(_ blocks: [TextBlock]) -> [Line] {
        var lines: [Line] = []
        for block in blocks.sorted(by: { $0.box.midY < $1.box.midY }) {
            if var last = lines.last,
               abs(block.box.midY - last.midY) < 0.5 * max(block.box.height, last.height) {
                last.blocks.append(block)
                let n = Double(last.blocks.count)
                last.midY = last.midY * (n - 1) / n + block.box.midY / n
                last.height = max(last.height, block.box.height)
                lines[lines.count - 1] = last
            } else {
                lines.append(Line(blocks: [block], midY: block.box.midY, height: block.box.height))
            }
        }
        return lines.map { line in
            var line = line
            line.blocks.sort { $0.box.minX < $1.box.minX }
            return line
        }
    }

    // MARK: - Header fields

    /// Separates OCR blocks of one line in the header text, so a field's value never runs into the next block
    /// ("主要诊断:" with nothing after it must not swallow "采集时间:…").
    static let blockSeparator = "¦"

    static func parseHeader(_ lines: [Line]) -> ParsedReport {
        let text = lines
            .map { line in line.blocks.map { Normalizer.basic($0.text) }.joined(separator: " \(blockSeparator) ") }
            .joined(separator: "\n")
        var report = ParsedReport()
        report.hospital = hospital(in: text)
        report.specimenNo = field(["标本编号", "条码号", "样本号", "标本号"], value: #"([A-Za-z0-9\-]+)"#, in: text)
        report.specimenType = field(["标本类型", "样本类型", "标本种类"], value: #"(\p{Han}+)"#, in: text)
        report.department = field(["病区", "科室", "科别"], value: #"([^\s¦:：][^\s¦]*)"#, in: text)
        report.diagnosis = field(["主要诊断", "临床诊断", "诊断"], value: #"([^\s¦:：][^\s¦]*)"#, in: text)
        report.instrument = field(["检验仪器", "仪器"], value: #"([^\s¦:：][^\n¦]*?)[ \t]*(?:¦|第\s*\d|$)"#, in: text)
        report.collectedAt = date(after: ["采集时间", "采样时间", "采集日期", "采样日期", "检查日期"], in: text)
        report.receivedAt = date(after: ["接收时间", "签收时间"], in: text)
        report.reportedAt = date(after: ["报告时间", "报告日期", "审核时间"], in: text)
        if report.collectedAt == nil {
            report.collectedAt = report.receivedAt ?? report.reportedAt
        }
        return report
    }

    /// A label whose characters may be split into blocks or spaced out ("病  区"), then an optional colon.
    /// The value may be the next OCR block ("采集时间:" | "2026-03-16"), unless that block is itself a
    /// "label:" — so an empty field never takes the following one.
    private static func labelPattern(_ labels: [String], strictValue: Bool = false) -> String {
        let alternatives = labels.map { label in
            label.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"[\s¦]*"#)
        }
        // A strictly formatted value (a date) can never be mistaken for a label, so any gap is fine.
        let gap = strictValue ? #"[\s¦]*"# : #"[ \t]*(?:¦[ \t]*(?![^¦\n]*[:：]))?"#
        return "(?:" + alternatives.joined(separator: "|") + #")[ \t]*[:：]?"# + gap
    }

    private static func field(_ labels: [String], value: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: labelPattern(labels) + value, options: [.anchorsMatchLines]),
              let m = regex.firstMatch(in: text) else { return "" }
        return text.group(m, 1).trimmingCharacters(in: .whitespaces)
    }

    private static let datePattern = #"(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?(?:[\s¦]*(\d{1,2})\s*[:：]\s*(\d{2}))?"#

    static func date(after labels: [String], in text: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: labelPattern(labels, strictValue: true) + datePattern),
              let m = regex.firstMatch(in: text) else { return nil }
        var c = DateComponents()
        c.year = Int(text.group(m, 1))
        c.month = Int(text.group(m, 2))
        c.day = Int(text.group(m, 3))
        c.hour = Int(text.group(m, 4)) ?? 0
        c.minute = Int(text.group(m, 5)) ?? 0
        return Calendar(identifier: .gregorian).date(from: c)
    }

    private static let traditional: [Character: Character] = [
        "廣": "广", "東": "东", "醫": "医", "衛": "卫", "門": "门", "華": "华", "國": "国", "學": "学", "區": "区", "縣": "县",
    ]
    private static let hospitalPattern = try! NSRegularExpression(
        pattern: #"(\p{Han}{2,20}?(?:医院|醫院|卫生院|衛生院|体检中心|健康管理中心|妇幼保健院))"#
    )

    static func hospital(in text: String) -> String {
        guard let m = hospitalPattern.firstMatch(in: text) else { return "" }
        return String(text.group(m, 1).map { traditional[$0] ?? $0 })
    }

    // MARK: - Table

    struct Columns {
        /// Blocks starting left of this are in the name column.
        var resultStart: Double
        var referenceStart: Double
        var methodStart: Double
    }

    private static let footerMarkers = [
        "此报告仅对", "接收时间", "检验者", "审核者", "报告时间", "粤HR", "互认项目", "检验仪器", "备注:", "温馨提示",
    ]
    /// Results are printed a little left of their header word, right after the abbreviation's ")".
    private static let margin = 0.025

    static func locateTable(_ lines: [Line]) -> (rows: [Line], columns: Columns)? {
        guard let headerIndex = lines.firstIndex(where: isHeader) else { return nil }
        let header = lines[headerIndex]
        guard let result = x(of: "结果", in: header),
              let reference = x(of: "参考", in: header) ?? x(of: "范围", in: header) else { return nil }
        // OCR often reads "方法" as "万法".
        let method = x(of: "方法", in: header) ?? x(of: "万法", in: header) ?? .infinity
        let columns = Columns(
            resultStart: result - margin,
            referenceStart: reference - margin,
            methodStart: method - margin
        )

        var rows: [Line] = []
        for line in lines[(headerIndex + 1)...] {
            let compact = line.compact
            if footerMarkers.contains(where: { compact.contains($0) }) { break }
            // A repeated header (a second page in one long screenshot) is not data.
            if isHeader(line) { continue }
            rows.append(line)
        }
        return (rows, columns)
    }

    static func isHeader(_ line: Line) -> Bool {
        let compact = line.compact
        return compact.contains("结果") && (compact.contains("参考") || compact.contains("单位"))
    }

    /// The x position where the header word containing `word` starts ("方法" → the start of "检验方法"),
    /// estimated within its block when OCR merged several header words.
    static func x(of word: String, in line: Line) -> Double? {
        for block in line.blocks {
            let text = Normalizer.basic(block.text)
            guard let range = text.range(of: word) else { continue }
            let wordStart = text[..<range.lowerBound].lastIndex(of: " ").map { text.index(after: $0) } ?? text.startIndex
            let offset = Double(text.distance(from: text.startIndex, to: wordStart))
            let count = Double(max(text.count, 1))
            return block.box.minX + block.box.width * offset / count
        }
        return nil
    }

    struct Zones {
        var name = ""
        var result = ""
        var reference = ""
        var method = ""
        var confidence = 1.0
    }

    static func zones(of line: Line, columns: Columns) -> Zones {
        var z = Zones(confidence: line.confidence)
        func add(_ s: inout String, _ text: String) { s += s.isEmpty ? text : " " + text }
        for block in line.blocks {
            let x = textStart(of: block)
            if x < columns.resultStart { add(&z.name, block.text) }
            else if x < columns.referenceStart { add(&z.result, block.text) }
            else if x < columns.methodStart { z.reference = ParsedItem.joinReference(z.reference, Normalizer.reference(block.text)) }
            else { add(&z.method, block.text) }
        }
        return z
    }

    /// Where a block's own text starts: the closing parenthesis of the abbreviation column often lands in the
    /// same block as the result ("） 5.30"), which would put the result left of the result column.
    static func textStart(of block: TextBlock) -> Double {
        let text = block.text
        let skipped = text.prefix { ")）] ".contains($0) }.count
        guard skipped > 0, skipped < text.count else { return block.box.minX }
        return block.box.minX + block.box.width * Double(skipped) / Double(text.count)
    }

    static func parseTable(lines: [Line], columns: Columns) -> [ParsedItem] {
        var items: [ParsedItem] = []
        for line in lines {
            switch parseRow(zones(of: line, columns: columns)) {
            case .item(let item)?:
                items.append(item)
            case .continuation(let c)?:
                guard !items.isEmpty else { continue }
                items[items.count - 1].absorb(c)
            case nil:
                continue
            }
        }
        return items.map(IndicatorCatalog.shared.corrected)
    }

    /// Without a recognizable header, accept only lines that look like "名称 (缩写) 结果 …" on their own.
    static func parseWithoutColumns(_ lines: [Line]) -> [ParsedItem] {
        lines.compactMap { line in
            guard case .item(let item)? = parseRow(Zones(name: line.text, confidence: line.confidence)),
                  !item.name.isEmpty, !item.code.isEmpty else { return nil }
            return IndicatorCatalog.shared.corrected(item)
        }
    }

    // MARK: - Rows

    struct Continuation {
        var name = ""
        var interpretation = ""
        var unit = ""
        var reference = ""
        var method = ""
    }

    enum Row {
        case item(ParsedItem)
        case continuation(Continuation)
    }

    private static let sequencePattern = try! NSRegularExpression(pattern: #"^(\d{1,3})(?=\s|[^\d.\-])\s*"#)
    private static let numericValue = try! NSRegularExpression(pattern: #"^[<>≤≥]?\d+(?:\.\d+)?$"#)
    private static let qualitativeValues: Set<String> = [
        "阴性", "阳性", "弱阳性", "无反应性", "有反应性", "未检出", "检出", "正常", "异常",
        "+", "-", "±", "+-", "1+", "2+", "3+", "4+", "(+)", "(-)", "(±)",
        "阴性(-)", "阳性(+)", "弱阳性(±)", "阴性(−)",
    ]
    private static let abbreviationPattern = try! NSRegularExpression(pattern: #"^[A-Za-zα-ωΑ-Ω][A-Za-z0-9α-ωΑ-Ω#%\-/.:\s]*$"#)
    private static let arrows: [Character: ResultFlag] = ["↑": .high, "▲": .high, "↓": .low, "▼": .low]
    private static let misreadArrow = try! NSRegularExpression(pattern: #"^[1Il|tTJ!→]{1,3}$"#)

    static func parseRow(_ z: Zones) -> Row? {
        var nameText = Normalizer.basic(z.name).trimmingCharacters(in: .whitespaces)

        var sequence: Int?
        if let m = sequencePattern.firstMatch(in: nameText) {
            sequence = Int(nameText.group(m, 1))
            nameText = String(nameText[Range(m.range, in: nameText)!.upperBound...])
        }

        var (namePart, code, trailing) = splitName(nameText)
        // A wrapped name line that OCR merged into the same block row ends up after the result in the name
        // column ("人类免疫缺陷病毒抗 (HIV Duo) 0.209 原/抗体联合检测"); it belongs to the name.
        let trailingTokens = trailing.split(separator: " ").map(String.init)
        let wrappedName = trailingTokens.filter { Normalizer.containsHan($0) && !isQualitative($0) }
        if !wrappedName.isEmpty {
            namePart += wrappedName.joined()
            trailing = trailingTokens.filter { !wrappedName.contains($0) }.joined(separator: " ")
        }

        var resultText = trailing + " " + Normalizer.basic(z.result)
        resultText = resultText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"^[)\s]+"#, with: "", options: .regularExpression)
            // A unit split by OCR ("10 9/L") must not read as the result 10.
            .replacingOccurrences(of: #"(?<![\d.])10[\s^ˆ'’*`]+(9|12)/L"#, with: "10^$1/L", options: .regularExpression)
            // "无反应COI" in one block: the word and the unit.
            .replacingOccurrences(of: #"(\p{Han})(?=[A-Za-z]{2})"#, with: "$1 ", options: .regularExpression)
        for arrow in arrows.keys {
            resultText = resultText.replacingOccurrences(of: String(arrow), with: " \(arrow) ")
        }

        var valueText: String?
        var flag: ResultFlag?
        var unitParts: [String] = []
        var hanParts: [String] = []
        var referenceParts: [String] = []
        for token in resultText.split(separator: " ").map(String.init) {
            if token.count == 1, let arrowFlag = arrows[token.first!] {
                flag = arrowFlag
            } else if valueText == nil, isValue(token) {
                valueText = token
            } else if valueText != nil, flag == nil, ["H", "L", "(H)", "(L)"].contains(token) {
                flag = token.contains("H") ? .high : .low
            } else if misreadArrow.firstMatch(in: token) != nil {
                // An ↑ or ↓ that OCR read as a letter or digit; the flag is derived from the reference instead.
                continue
            } else if Normalizer.containsHan(token) {
                hanParts.append(Normalizer.interpretation(token))
            } else if ReferenceRange.parse(token) != nil, token.contains(where: { "-~<>≤≥".contains($0) }) {
                referenceParts.append(token)
            } else {
                unitParts.append(token)
            }
        }

        // A row whose result OCR missed still starts a new test when it has its own abbreviation or the ☆/*
        // marker; merging it into the row above would corrupt that row. The empty result is left for the user.
        let startsNewRow = Normalizer.cleanCode(code).count >= 2
            || nameText.first.map { "☆★✩*＊".contains($0) } == true
        guard let valueText = valueText ?? (startsNewRow ? "" : nil) else {
            return .continuation(Continuation(
                name: Normalizer.cleanName(z.name),
                interpretation: hanParts.joined(),
                unit: unitParts.joined(),
                reference: Normalizer.reference(z.reference),
                method: Normalizer.basic(z.method).replacingOccurrences(of: " ", with: "")
            ))
        }

        let name = Normalizer.cleanName(namePart)
        var reference = Normalizer.reference(z.reference)
        if reference.isEmpty { reference = referenceParts.joined(separator: " ") }
        // A row whose name OCR missed is kept when it still looks like a result row, so the user can fill it in.
        guard !name.isEmpty || !code.isEmpty || !reference.isEmpty || !unitParts.isEmpty else { return nil }

        return .item(ParsedItem(
            sequence: sequence,
            name: name,
            code: Normalizer.cleanCode(code),
            valueText: valueText,
            value: Normalizer.number(valueText),
            interpretation: hanParts.joined(),
            unit: Normalizer.unit(unitParts.joined()),
            referenceText: reference,
            method: Normalizer.basic(z.method).replacingOccurrences(of: " ", with: ""),
            reportedFlag: flag,
            confidence: z.confidence
        ))
    }

    /// Splits "名称 (CODE) 尾部" into its parts; the tail belongs to the result columns.
    ///
    /// The abbreviation is the last parenthesized group that looks like one, so "阴性(-)" in the tail and
    /// "抗原(E)" in the name are not mistaken for it. Without an abbreviation, a result printed in the name
    /// column is split off at the first token that reads as a value ("25-羟基维生素D 30.5").
    static func splitName(_ text: String) -> (name: String, code: String, trailing: String) {
        var text = text
        for arrow in arrows.keys {
            text = text.replacingOccurrences(of: String(arrow), with: " \(arrow) ")
        }

        var best: (open: String.Index, code: String, trailing: String)?
        var searchStart = text.startIndex
        while let open = text[searchStart...].firstIndex(of: "(") {
            let afterOpen = text[text.index(after: open)...]
            let close = afterOpen.firstIndex(of: ")")
            let inner = String(close.map { afterOpen[..<$0] } ?? afterOpen).trimmingCharacters(in: .whitespaces)
            // "(H)" / "(L)" after a result are flags, not abbreviations.
            if abbreviationPattern.firstMatch(in: inner) != nil, inner != "H", inner != "L" {
                let trailing = close.map { String(afterOpen[afterOpen.index(after: $0)...]) } ?? ""
                best = (open, inner, trailing)
            }
            searchStart = text.index(after: open)
        }
        if let best {
            return (String(text[..<best.open]), best.code, best.trailing)
        }

        let tokens = text.split(separator: " ").map(String.init)
        if let i = tokens.indices.dropFirst().first(where: { isValue(tokens[$0]) }) {
            return (tokens[..<i].joined(separator: " "), "", tokens[i...].joined(separator: " "))
        }
        return (text, "", "")
    }

    /// Words that describe a result rather than name a test ("阴性", "无反应性", OCR-garbled "森反应").
    static func isQualitative(_ token: String) -> Bool {
        let word = Normalizer.interpretation(token)
        // "性" is the wrapped tail of "无反应性".
        return word == "性" || qualitativeValues.contains(word)
            || (LabFlagging.positiveWords + LabFlagging.negativeWords).contains(where: word.contains)
    }

    static func isValue(_ token: String) -> Bool {
        numericValue.firstMatch(in: token) != nil || qualitativeValues.contains(token)
    }
}

extension ParsedItem {
    mutating func absorb(_ c: ReportParser.Continuation) {
        name += c.name
        // The wrapped tail of "无反应" + "性" is already part of the corrected word.
        if !(interpretation.hasSuffix("性") && c.interpretation == "性") { interpretation += c.interpretation }
        if unit.isEmpty, !c.unit.isEmpty { unit = Normalizer.unit(c.unit) }
        if !c.reference.isEmpty { referenceText = Self.joinReference(referenceText, c.reference) }
        method += c.method
    }

    /// Joins a wrapped reference line: a new line starts at a bound or a "label:" entry; other pieces
    /// continue the previous line ("≥0.900至<1.000:不" + "确定").
    static func joinReference(_ existing: String, _ piece: String) -> String {
        guard !existing.isEmpty else { return piece }
        let continuesPrevious = existing.hasSuffix("-") || existing.hasSuffix("至")
        let startsEntry = piece.first.map { "<>≤≥0123456789".contains($0) } == true
            || piece.contains(":") || piece.contains("：")
        return continuesPrevious || !startsEntry ? existing + piece : existing + "\n" + piece
    }
}
