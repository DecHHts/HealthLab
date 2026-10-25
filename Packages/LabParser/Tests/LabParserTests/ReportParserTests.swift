import XCTest
@testable import LabParser

/// Builds OCR blocks the way Vision returns them for the sample screenshots (921×2000 points),
/// one block per visually separate run of text.
private struct Page {
    var blocks: [TextBlock] = []

    mutating func row(_ y: Double, _ cells: [(Double, String)]) {
        for (x, text) in cells {
            let width = Double(text.count) * 11
            blocks.append(TextBlock(
                text: text,
                box: Box(x: x / 921, y: (y - 7) / 2000, width: width / 921, height: 14 / 2000),
                confidence: 0.9
            ))
        }
    }

    /// Patient and staff names are made up; the layout follows the sample screenshots.
    mutating func header(collected: String, specimenNo: String, type: String, diagnosis: String = "健康体检") {
        row(165, [(395, "文件预览")])
        row(405, [(60, "广东省医学科学院"), (390, "广东省人民医院"), (680, "检验科报告单")])
        row(467, [(20, "姓"), (78, "名:张三"), (310, "病历号:1000001"), (622, "标本编号:\(specimenNo)")])
        row(492, [(20, "性"), (78, "别:男"), (310, "病"), (395, "区:东川内科门诊"), (622, "标本类型:\(type)")])
        row(517, [(20, "年"), (78, "龄:22岁"), (310, "病床号:"), (622, "样本状态:合格")])
        row(542, [(20, "申请医生:李四"), (310, "主要诊断:\(diagnosis)"), (622, "采集时间:\(collected)")])
        row(574, [(20, "序号"), (145, "项目名称"), (335, "结果"), (515, "单位"), (617, "参考值"), (771, "检验方法")])
    }

    mutating func footer(instrument: String) {
        row(1210, [(18, "☆:粤HR(广东省检验结果互认项目) *:粤琼YQHR(粤琼跨省检验结果互认项目)")])
        row(1512, [(320, "此报告仅对本次收到的样本负责")])
        row(1541, [(22, "接收时间:2026-03-16 11:42"), (595, "报告时间:2026-03-16 12:04")])
        row(1564, [(22, "录入者:王五"), (315, "检验者:"), (595, "审核者:")])
        row(1594, [(20, "检验仪器:\(instrument)"), (490, "第"), (540, "1页/共"), (632, "1"), (652, "页")])
    }
}

final class ReportParserTests: XCTestCase {
    func testBloodRoutine() throws {
        var page = Page()
        page.header(collected: "2026-03-16 11:09", specimenNo: "2000000050", type: "全血")
        page.row(599, [(38, "1"), (70, "☆*白细胞计数"), (228, "( WBC"), (318, ") 10.20"), (515, "10^9/L"), (615, "3.50-9.50")])
        page.row(621, [(38, "2"), (70, "☆*红细胞计数"), (228, "( RBC"), (318, ") 4.86"), (464, "↑"), (515, "10^12/L"), (615, "4.30-5.80")])
        page.row(643, [(38, "3"), (70, "☆*血红蛋白量"), (228, "( HGB"), (318, ") 125"), (515, "g/L"), (615, "130-175")])
        page.row(664, [(38, "4"), (70, "☆*红细胞比积"), (228, "( HCT"), (318, ") 0.441"), (615, "0.400-0.500")])
        page.row(686, [(38, "5"), (70, "☆*平均红细胞体积"), (228, "( MCV"), (318, ") 91.3"), (464, "↓"), (515, "fL"), (615, "82.0-100.0")])
        page.row(708, [(38, "6"), (70, "☆*平均红细胞血红蛋"), (228, "( MCH"), (318, ") 30.2"), (464, "↓"), (515, "pg"), (615, "27.0-34.0")])
        page.row(724, [(70, "白量")])
        page.row(1023, [(38, "19"), (70, "红细胞分布宽度CV"), (228, "( RDW-CV"), (318, ") 0.13"), (464, "↑"), (615, "0.11-0.16")])
        page.row(1133, [(38, "24"), (70, "血小板压积"), (228, "( PCT"), (318, ") 2.15"), (515, "‰"), (615, "1.08-2.72")])
        page.footer(instrument: "计算结果,XN9000_1")

        let report = ReportParser.parse(page.blocks)

        XCTAssertEqual(report.hospital, "广东省人民医院")
        XCTAssertEqual(report.specimenNo, "2000000050")
        XCTAssertEqual(report.specimenType, "全血")
        XCTAssertEqual(report.diagnosis, "健康体检")
        XCTAssertEqual(report.department, "东川内科门诊")
        XCTAssertEqual(report.instrument, "计算结果,XN9000_1")
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: try XCTUnwrap(report.collectedAt))
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 3, 16, 11, 9])

        XCTAssertEqual(report.items.count, 8)
        let wbc = report.items[0]
        XCTAssertEqual(wbc.sequence, 1)
        XCTAssertEqual(wbc.name, "白细胞计数")
        XCTAssertEqual(wbc.code, "WBC")
        XCTAssertEqual(wbc.value, 10.20)
        XCTAssertEqual(wbc.unit, "10^9/L")
        XCTAssertEqual(wbc.referenceText, "3.50-9.50")
        XCTAssertEqual(wbc.flag, .high)

        XCTAssertEqual(report.items[1].flag, .high)
        XCTAssertEqual(report.items[1].unit, "10^12/L")
        XCTAssertEqual(report.items[3].unit, "")
        XCTAssertEqual(report.items[4].flag, .low)

        let mch = report.items[5]
        XCTAssertEqual(mch.name, "平均红细胞血红蛋白量")
        XCTAssertEqual(mch.code, "MCH")
        XCTAssertEqual(mch.reportedFlag, .low)

        XCTAssertEqual(report.items[6].code, "RDW-CV")
        XCTAssertEqual(report.items[6].flag, .high)
        XCTAssertEqual(report.items[7].unit, "‰")
        XCTAssertEqual(report.suggestedTitle, "血常规")
    }

    func testBiochemistryWithWrappedReference() throws {
        var page = Page()
        page.header(collected: "2026-03-16 11:09", specimenNo: "2000000052", type: "血清")
        page.row(599, [(38, "1"), (70, "☆*葡萄糖"), (228, "( GLU"), (318, ") 5.62"), (515, "mmol/L"), (615, "3.90-6.10"), (771, "酶法")])
        page.row(643, [(38, "3"), (70, "碳酸氢盐"), (228, "( HCO3"), (318, ") 24.3"), (515, "mmol/L"), (615, "21.0-31.0"), (771, "酶法")])
        page.row(686, [(38, "5"), (70, "☆*尿酸"), (228, "( UA"), (318, ") 352.6"), (464, "↑"), (515, "μ mol/L"), (615, "208.0-428.0"), (771, "酶法")])
        page.row(708, [(38, "12"), (70, "☆胱抑素C"), (228, "( Cys-C"), (318, ") 0.91"), (515, "mg/L"), (615, "0.59-1.03"), (771, "免疫比浊法")])
        page.row(752, [(38, "7"), (70, "☆*天门冬氨酸氨基转"), (228, "( AST"), (318, ") 26"), (515, "U/L"), (615, "15-40"), (771, "速率法")])
        page.row(768, [(70, "移酶")])
        page.row(870, [(38, "8"), (70, "天门冬氨酸氨基转移"), (228, "( AST/ALT"), (318, ") 1.2")])
        page.row(886, [(70, "酶/丙氨酸氨基转移酶")])
        page.row(907, [(38, "13"), (70, "肾小球滤过率"), (228, "( eGFR"), (318, ") 103.62"), (615, "CKD-EPI2021联合公式"), (771, "计算法")])
        page.row(923, [(615, "估算的肾小球滤过率")])
        page.row(939, [(615, "eGFR单位:mL/")])
        page.row(969, [(615, "CKD1期:正常≥90")])
        page.row(985, [(615, "CKD2期:轻度下降60-")])
        page.row(1001, [(615, "89")])
        page.footer(instrument: "Remiso_1,AU5800-3")

        let report = ReportParser.parse(page.blocks)

        XCTAssertEqual(report.items.count, 7)
        XCTAssertEqual(report.items[0].method, "酶法")
        XCTAssertEqual(report.items[1].code, "HCO3")
        let ua = report.items[2]
        XCTAssertEqual(ua.unit, "μmol/L")
        XCTAssertEqual(ua.flag, .high)
        XCTAssertEqual(IndicatorCatalog.shared.indicatorKey(name: ua.name, code: ua.code), "UA")
        XCTAssertEqual(report.items[3].sequence, 12)
        XCTAssertEqual(report.items[4].name, "天门冬氨酸氨基转移酶")
        XCTAssertEqual(report.items[5].name, "天门冬氨酸氨基转移酶/丙氨酸氨基转移酶")
        XCTAssertEqual(report.items[5].flag, .unknown)

        let egfr = report.items[6]
        XCTAssertEqual(egfr.value, 103.62)
        XCTAssertEqual(egfr.method, "计算法")
        XCTAssertEqual(egfr.referenceText, "CKD-EPI2021联合公式估算的肾小球滤过率\neGFR单位:mL/\nCKD1期:正常≥90\nCKD2期:轻度下降60-89")
        XCTAssertNil(egfr.referenceRange)
        XCTAssertEqual(egfr.flag, .unknown)
        XCTAssertEqual(report.suggestedTitle, "肾功能 · 肝功能")
    }

    func testInfectiousScreeningWithQualitativeUnits() throws {
        var page = Page()
        page.header(collected: "2026-03-16 11:09", specimenNo: "2000000051", type: "血清")
        page.row(599, [(38, "1"), (70, "☆*乙型肝炎表面抗原"), (228, "( HBsAg"), (318, ") 0.402"), (460, "无反应"), (525, "COI"), (615, "<0.900:无反应性"), (771, "电化学发光法")])
        page.row(615, [(460, "性"), (615, "≥0.900至<1.000:不")])
        page.row(630, [(615, "确定")])
        page.row(645, [(615, "≥1.00:有反应性")])
        page.row(667, [(38, "2"), (70, "人类免疫缺陷病毒抗"), (228, "( HIV Duo"), (318, ") 0.251"), (460, "无反应"), (525, "COI"), (615, "<1.000:无反应性"), (771, "电化学发光法")])
        page.row(683, [(70, "原/抗体联合检测"), (460, "性"), (615, "≥1.00:待确证")])
        page.row(846, [(38, "6"), (70, "☆*梅毒螺旋体特异抗"), (228, "( TP-Ab"), (318, ") 0.11"), (460, "无反应"), (525, "COI"), (615, "<1.00:无反应性"), (771, "电化学发光法")])
        page.row(862, [(70, "体"), (460, "性"), (615, "≥1.00:有反应性")])
        page.footer(instrument: "IT3000_1,IT3000_1,Cobas-1")

        let report = ReportParser.parse(page.blocks)

        XCTAssertEqual(report.items.count, 3)
        let hbsag = report.items[0]
        XCTAssertEqual(hbsag.name, "乙型肝炎表面抗原")
        XCTAssertEqual(hbsag.code, "HBsAg")
        XCTAssertEqual(hbsag.value, 0.402)
        XCTAssertEqual(hbsag.unit, "COI")
        XCTAssertEqual(hbsag.interpretation, "无反应性")
        XCTAssertEqual(hbsag.referenceText, "<0.900:无反应性\n≥0.900至<1.000:不确定\n≥1.00:有反应性")
        XCTAssertEqual(hbsag.referenceRange, ReferenceRange(low: nil, high: 0.9, highExclusive: true))
        XCTAssertEqual(hbsag.flag, .normal)

        let hiv = report.items[1]
        XCTAssertEqual(hiv.name, "人类免疫缺陷病毒抗原/抗体联合检测")
        XCTAssertEqual(hiv.code, "HIV Duo")
        XCTAssertEqual(IndicatorCatalog.shared.indicatorKey(name: hiv.name, code: hiv.code), "HIV DUO")

        XCTAssertEqual(report.items[2].name, "梅毒螺旋体特异抗体")
        XCTAssertEqual(report.suggestedTitle, "传染病")
    }

    func testMergedBlocksAreSplitIntoColumns() {
        var page = Page()
        page.header(collected: "2026/03/16 11:09", specimenNo: "1", type: "血清")
        page.row(599, [(38, "1 ☆*丙氨酸氨基转移酶 (ALT) 22 U/L 9-50")])
        page.row(621, [(38, "2 ☆*尿酸（UA）352.6↑ umol/L"), (615, "208.0-428.0")])

        let items = ReportParser.parse(page.blocks).items

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].code, "ALT")
        XCTAssertEqual(items[0].value, 22)
        XCTAssertEqual(items[0].unit, "U/L")
        XCTAssertEqual(items[0].referenceText, "9-50")
        XCTAssertEqual(items[1].code, "UA")
        XCTAssertEqual(items[1].reportedFlag, .high)
        XCTAssertEqual(items[1].unit, "μmol/L")
    }

    func testQualitativeResultsWithParentheses() {
        var page = Page()
        page.header(collected: "2026-03-16 11:09", specimenNo: "1", type: "血清")
        page.row(599, [(38, "1"), (70, "乙肝表面抗原"), (228, "( HBsAg"), (318, ") 阴性(-)"), (615, "阴性")])
        page.row(621, [(38, "2"), (70, "梅毒螺旋体抗体"), (228, "( TP"), (318, ") (+)"), (615, "阴性")])
        page.row(643, [(38, "3"), (70, "总蛋白"), (228, "( TP"), (318, ") 72.1"), (515, "g/L"), (615, "65.0-85.0")])

        let items = ReportParser.parse(page.blocks).items

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].code, "HBsAg")
        XCTAssertEqual(items[0].valueText, "阴性(-)")
        XCTAssertEqual(items[0].flag, .normal)
        XCTAssertEqual(items[1].valueText, "(+)")
        XCTAssertEqual(items[1].flag, .positive)
        let catalog = IndicatorCatalog.shared
        XCTAssertEqual(catalog.indicatorKey(name: items[1].name, code: items[1].code), "TP-AB")
        XCTAssertEqual(catalog.indicatorKey(name: items[2].name, code: items[2].code), "TP")
    }

    func testEmptyHeaderFieldDoesNotTakeTheNextBlock() {
        var page = Page()
        page.header(collected: "2026-03-16 11:09", specimenNo: "1", type: "血清", diagnosis: "")
        page.row(599, [(38, "1"), (70, "葡萄糖"), (228, "( GLU"), (318, ") 5.62"), (515, "mmol/L"), (615, "3.90-6.10")])

        let report = ReportParser.parse(page.blocks)

        XCTAssertEqual(report.diagnosis, "")
        XCTAssertNotNil(report.collectedAt)
    }

    func testHeaderValuesInTheirOwnBlocks() throws {
        var page = Page()
        page.row(467, [(20, "姓名:张三"), (622, "标本编号:"), (730, "2000000050")])
        page.row(492, [(310, "主要诊断:"), (622, "标本类型:"), (730, "血清")])
        page.row(542, [(622, "采集时间:"), (730, "2026-03-16 11:09")])
        page.row(574, [(20, "序号"), (145, "项目名称"), (335, "结果"), (515, "单位"), (617, "参考值"), (771, "检验方法")])
        page.row(599, [(38, "1"), (70, "葡萄糖"), (228, "( GLU"), (318, ") 5.62"), (515, "mmol/L"), (615, "3.90-6.10")])

        let report = ReportParser.parse(page.blocks)

        XCTAssertEqual(report.specimenNo, "2000000050")
        XCTAssertEqual(report.specimenType, "血清")
        XCTAssertEqual(report.diagnosis, "")
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: try XCTUnwrap(report.collectedAt))
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 3, 16, 11, 9])
    }

    func testRepeatedHeaderAndFlagInParentheses() {
        var page = Page()
        page.header(collected: "2026-03-16 11:09", specimenNo: "1", type: "全血")
        page.row(599, [(38, "1"), (70, "白细胞计数 (WBC) 10.30 (H)"), (515, "10^9/L"), (615, "3.50-9.50")])
        page.row(621, [(20, "序号"), (145, "项目名称"), (335, "结果"), (515, "单位"), (617, "参考值")])
        page.row(643, [(38, "2"), (70, "红细胞计数"), (228, "( RBC"), (318, ") 4.80"), (515, "10^12/L"), (615, "4.30-5.80")])

        let items = ReportParser.parse(page.blocks).items

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].code, "WBC")
        XCTAssertEqual(items[0].reportedFlag, .high)
        XCTAssertEqual(items[0].unit, "10^9/L")
        XCTAssertEqual(items[0].name, "白细胞计数")
        XCTAssertEqual(items[1].code, "RBC")
    }

    func testValueInNameColumnWithoutAbbreviation() {
        var page = Page()
        page.header(collected: "2026-03-16 11:09", specimenNo: "1", type: "血清")
        page.row(599, [(38, "1"), (70, "25-羟基维生素D 30.5"), (515, "ng/mL"), (615, "30.0-100.0")])
        page.row(621, [(38, "2"), (70, "同型半胱氨酸 18.2↑"), (515, "μmol/L"), (615, "0-15")])

        let items = ReportParser.parse(page.blocks).items

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "25-羟基维生素D")
        XCTAssertEqual(items[0].value, 30.5)
        XCTAssertEqual(items[0].unit, "ng/mL")
        XCTAssertEqual(items[1].name, "同型半胱氨酸")
        XCTAssertEqual(items[1].reportedFlag, .high)
    }

    func testWithoutHeaderRowFallsBackToLinePattern() {
        var page = Page()
        page.row(100, [(20, "白细胞计数 (WBC) 6.12 10^9/L 3.50-9.50")])
        page.row(130, [(20, "温馨提示：请空腹")])

        let items = ReportParser.parse(page.blocks).items

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].code, "WBC")
        XCTAssertEqual(items[0].flag, .normal)
    }
}

final class ReferenceRangeTests: XCTestCase {
    func testParsesCommonForms() {
        XCTAssertEqual(ReferenceRange.parse("3.50-9.50"), ReferenceRange(low: 3.5, high: 9.5))
        XCTAssertEqual(ReferenceRange.parse("5000-12000"), ReferenceRange(low: 5000, high: 12000))
        XCTAssertEqual(ReferenceRange.parse("男：130～175"), ReferenceRange(low: 130, high: 175))
        XCTAssertEqual(ReferenceRange.parse("<0.900:无反应性\n≥1.00:有反应性"), ReferenceRange(low: nil, high: 0.9, highExclusive: true))
        XCTAssertEqual(ReferenceRange.parse("≥90"), ReferenceRange(low: 90, high: nil))
        XCTAssertNil(ReferenceRange.parse("CKD-EPI2021联合公式"))
        XCTAssertNil(ReferenceRange.parse(""))
    }

    func testClassify() {
        let range = ReferenceRange(low: 208, high: 428)
        XCTAssertEqual(range.classify(452.6), .high)
        XCTAssertEqual(range.classify(100), .low)
        XCTAssertEqual(range.classify(428), .normal)
        XCTAssertEqual(ReferenceRange(low: nil, high: 1, highExclusive: true).classify(1), .high)
    }

    func testQualitativeFlags() {
        XCTAssertEqual(ParsedItem(name: "x", valueText: "阴性").flag, .normal)
        XCTAssertEqual(ParsedItem(name: "x", valueText: "阳性").flag, .positive)
        XCTAssertEqual(ParsedItem(name: "x", valueText: "未检出").flag, .normal)
        XCTAssertEqual(ParsedItem(name: "x", valueText: "2+").flag, .positive)
        XCTAssertEqual(ParsedItem(name: "x", valueText: "(-)").flag, .normal)
        XCTAssertEqual(ParsedItem(name: "x", valueText: "-").flag, .normal)
    }
}

final class IndicatorCatalogTests: XCTestCase {
    func testMatchesByCodeAcrossHospitalNames() {
        let catalog = IndicatorCatalog.shared
        XCTAssertEqual(catalog.indicatorKey(name: "谷丙转氨酶", code: ""), "ALT")
        XCTAssertEqual(catalog.indicatorKey(name: "丙氨酸转氨酶", code: "GPT"), "ALT")
        XCTAssertEqual(catalog.indicatorKey(name: "肌酐", code: "CREA"), "CR")
        XCTAssertEqual(catalog.indicatorKey(name: "中性粒细胞比值", code: "NEUT%"), "NEUT%")
        XCTAssertEqual(catalog.indicatorKey(name: "某新项目", code: "xyz 1"), "XYZ1")
        XCTAssertEqual(catalog.indicatorKey(name: "某新项目", code: ""), "名称:某新项目")
        XCTAssertEqual(catalog.category(name: "胱抑素C", code: "Cys-C"), "肾功能")
        XCTAssertEqual(catalog.indicatorKey(name: "梅毒螺旋体特异性抗体", code: "TP"), "TP-AB")
        XCTAssertEqual(catalog.indicatorKey(name: "某抗体", code: "TP"), "名称:某抗体")
    }

    func testUrineResultsStayApartFromBlood() {
        let catalog = IndicatorCatalog.shared
        XCTAssertEqual(catalog.indicatorKey(name: "白细胞", code: "WBC", specimen: "尿液"), "尿:WBC")
        XCTAssertEqual(catalog.category(name: "葡萄糖", code: "GLU", specimen: "尿液"), "尿常规")
        XCTAssertEqual(catalog.indicatorKey(name: "白细胞", code: "WBC", specimen: "全血"), "WBC")
    }
}

final class CatalogCorrectionTests: XCTestCase {
    private func corrected(_ name: String, _ code: String) -> ParsedItem {
        IndicatorCatalog.shared.corrected(ParsedItem(name: name, code: code, valueText: "1"))
    }

    func testRepairsOCRSlips() {
        let mch = corrected("含平均細胞血紅蛋", "NCH")
        XCTAssertEqual(mch.name, "平均红细胞血红蛋白量")
        XCTAssertEqual(mch.code, "MCH")
    }

    func testLeavesSimilarButDifferentTestsAlone() {
        for (name, code) in [("尿微量白蛋白", "mALB"), ("反三碘甲状腺原氨酸", "rT3"), ("微量白蛋白", "mALB"),
                             ("小而密低密度脂蛋白胆固醇", "sdLDL-C"), ("某某特殊白蛋白测定", "XALB")] {
            let item = corrected(name, code)
            XCTAssertEqual(item.name, name)
            XCTAssertEqual(item.code, code)
        }
    }

    func testReferenceCommas() {
        XCTAssertEqual(Normalizer.reference("<1,000:无反应性"), "<1.000:无反应性")
        XCTAssertEqual(Normalizer.reference("≥0.900至<1,000:不确定"), "≥0.900至<1.000:不确定")
        XCTAssertEqual(Normalizer.reference("4,000-10,000"), "4,000-10,000")
    }
}
