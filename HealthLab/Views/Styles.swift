import SwiftUI
import LabParser

extension ResultFlag {
    var label: String {
        switch self {
        case .normal: return "正常"
        case .high: return "偏高"
        case .low: return "偏低"
        case .positive: return "阳性"
        case .unknown: return ""
        }
    }

    var color: Color {
        switch self {
        case .high, .positive: return .red
        case .low: return .blue
        case .normal, .unknown: return .primary
        }
    }
}

/// "352.6 ↑" in the flag's color.
struct ValueText: View {
    let text: String
    let flag: ResultFlag

    var body: some View {
        HStack(spacing: 2) {
            Text(text).monospacedDigit()
            if !flag.symbol.isEmpty {
                Text(flag.symbol).fontWeight(.bold)
            }
        }
        .foregroundStyle(flag.color)
    }
}

extension Date {
    var dayString: String { formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) }
    var shortDayString: String { formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits)) }
}

extension Double {
    /// Up to 3 decimals, without trailing zeros.
    var compact: String { formatted(.number.grouping(.never).precision(.fractionLength(0...3))) }
}
