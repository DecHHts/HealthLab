import XCTest
@testable import LabParser

/// Real Vision output for the sample screenshots, dumped with ocr-dump.swift (names and numbers replaced).
/// It has the noise synthetic pages lack: traditional characters, "（WBC" / "） 5.30" blocks, ↑ read as "1",
/// ☆ read as Han characters, O read as 0, and rows whose name OCR missed.
final class RealOCRTests: XCTestCase {
    private struct RawBlock: Decodable {
        var text: String
        var confidence: Double
        var x, y, w, h: Double
    }

    private func parse(_ name: String) throws -> ParsedReport {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        let raw = try JSONDecoder().decode([RawBlock].self, from: Data(contentsOf: url))
        return ReportParser.parse(raw.map {
            TextBlock(text: $0.text, box: Box(x: $0.x, y: $0.y, width: $0.w, height: $0.h), confidence: $0.confidence)
        })
    }

    private func row(_ items: [ParsedItem], _ code: String) throws -> ParsedItem {
        try XCTUnwrap(items.first { $0.code == code }, "no row \(code)")
    }

    func testBloodRoutine() throws {
        let r = try parse("blood-routine")
        XCTAssertEqual(r.hospital, "广东省人民医院")
        XCTAssertEqual(r.specimenNo, "2000000050")
        XCTAssertEqual(r.specimenType, "全血")
        XCTAssertEqual(r.items.count, 24)
        XCTAssertEqual(r.items.map(\.code), [
            "WBC", "RBC", "HGB", "HCT", "MCV", "MCH", "MCHC", "PLT", "NEUT%", "LYMPH%", "MONO%", "EO%", "BASO%",
            "NEUT#", "LYMPH#", "MONO#", "EO#", "BASO#", "RDW-CV", "RDW-SD", "PDW", "MPV", "P-LCR", "PCT",
        ])
        XCTAssertFalse(r.items.contains { $0.name.isEmpty || $0.valueText.isEmpty })

        let mch = try row(r.items, "MCH")
        XCTAssertEqual(mch.name, "平均红细胞血红蛋白量")
        XCTAssertEqual(mch.valueText, "30.2")
        XCTAssertEqual(mch.flag, .normal)
        XCTAssertEqual(try row(r.items, "MCHC").name, "平均红细胞血红蛋白浓度")
        XCTAssertEqual(try row(r.items, "BASO#").name, "嗜碱性粒细胞计数")
        XCTAssertEqual(try row(r.items, "WBC").flag, .high)
        XCTAssertEqual(try row(r.items, "HGB").flag, .low)
        XCTAssertEqual(try row(r.items, "RBC").unit, "10^12/L")
        XCTAssertEqual(try row(r.items, "LYMPH#").unit, "10^9/L")
        XCTAssertEqual(try row(r.items, "RDW-CV").unit, "")
        XCTAssertEqual(try row(r.items, "RDW-CV").flag, .normal)
        XCTAssertEqual(try row(r.items, "PCT").unit, "‰")
    }

    func testBiochemistry() throws {
        let r = try parse("biochemistry")
        XCTAssertEqual(r.specimenType, "血清")
        XCTAssertEqual(r.items.count, 13)
        XCTAssertEqual(r.items.map(\.code), [
            "GLU", "Urea", "HCO3", "Cr", "UA", "Cys-C", "ALT", "AST", "GGT", "ALP", "CHE", "AST/ALT", "eGFR",
        ])
        let ua = try row(r.items, "UA")
        XCTAssertEqual(ua.unit, "μmol/L")
        XCTAssertEqual(ua.referenceText, "208.0-428.0")
        XCTAssertEqual(ua.flag, .normal)
        XCTAssertEqual(ua.interpretation, "")
        XCTAssertEqual(ua.method, "酶法")
        XCTAssertEqual(try row(r.items, "AST").name, "天门冬氨酸氨基转移酶")
        XCTAssertEqual(try row(r.items, "GGT").name, "γ-谷氨酰基转移酶")
        XCTAssertEqual(try row(r.items, "AST/ALT").name, "天门冬氨酸氨基转移酶/丙氨酸氨基转移酶")
        XCTAssertEqual(try row(r.items, "Cr").unit, "μmol/L")
    }

    func testInfectiousScreening() throws {
        let r = try parse("infectious")
        XCTAssertEqual(r.items.count, 6)
        XCTAssertEqual(r.items.map(\.code), ["HBSAg", "HIV DUO", "", "", "Anti-HCV", "TP-AB"])
        XCTAssertEqual(r.items[1].name, "人类免疫缺陷病毒抗原/抗体联合检测")
        // Rows whose name OCR missed are kept for the user to fill in.
        XCTAssertEqual(r.items[2].valueText, "0.173")
        XCTAssertEqual(r.items[2].name, "")
        XCTAssertEqual(r.items[5].name, "梅毒螺旋体特异抗体")
        for item in r.items {
            XCTAssertEqual(item.interpretation, "无反应性", item.code)
            XCTAssertEqual(item.unit, "COI", item.code)
            XCTAssertEqual(item.method, "电化学发光法", item.code)
            XCTAssertEqual(item.flag, .normal, item.code)
        }
        XCTAssertEqual(r.items[0].referenceText, "<0.900:无反应性\n≥0.900至<1.000:不确定\n≥1.00:有反应性")
    }
}

/// The iOS Simulator's Vision is much noisier than a device's: whole values and codes go missing.
extension RealOCRTests {
    func testSimulatorBloodRoutineKeepsRowsWithMissingValues() throws {
        let r = try parse("blood-routine-sim")
        XCTAssertEqual(r.items.count, 24)
        XCTAssertEqual(r.items.map(\.name).prefix(6), ["白细胞计数", "红细胞计数", "血红蛋白量", "红细胞比积", "平均红细胞体积", "平均红细胞血红蛋白量"])
        // MCV's result was not recognized: the row stays separate, empty, instead of merging into HCT.
        let mcv = try row(r.items, "MCV")
        XCTAssertEqual(mcv.valueText, "")
        XCTAssertEqual(mcv.unit, "fL")
        XCTAssertEqual(try row(r.items, "HCT").name, "红细胞比积")
        XCTAssertEqual(try row(r.items, "NEUT%").referenceText, "0.400-0.750")
        // "10 9/L" split by OCR is a unit, not the result 10.
        let baso = try row(r.items, "BASO#")
        XCTAssertEqual(baso.valueText, "")
        XCTAssertEqual(baso.unit, "10^9/L")
    }

    func testSimulatorBiochemistry() throws {
        let r = try parse("biochemistry-sim")
        XCTAssertEqual(r.items.first?.name, "葡萄糖")
        XCTAssertEqual(r.items.first?.valueText, "")
        XCTAssertEqual(try row(r.items, "UA").name, "尿酸")
        XCTAssertEqual(try row(r.items, "Cr").value, 72.3)
    }

    func testSimulatorInfectiousScreening() throws {
        let r = try parse("infectious-sim")
        XCTAssertEqual(r.items.count, 6)
        for item in r.items {
            XCTAssertEqual(item.unit, "COI", item.code)
            XCTAssertEqual(item.flag, .normal, item.code)
        }
    }
}
