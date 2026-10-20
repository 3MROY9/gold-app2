import Foundation

/// شمعة سعرية واحدة (بيانات خام أو شمعة هيكن آشي بعد الحساب)
struct Candle: Identifiable, Equatable {
    let time: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double

    var id: Date { time }

    var isBullish: Bool { close >= open }
    var bodyTop: Double { max(open, close) }
    var bodyBottom: Double { min(open, close) }
    var bodySize: Double { abs(close - open) }
    var range: Double { high - low }
}

/// الفريمات الزمنية المدعومة: الساعة، 30 دقيقة، 15 دقيقة
enum TimeFrame: String, CaseIterable, Identifiable {
    case h1, m30, m15

    var id: String { rawValue }

    var title: String {
        switch self {
        case .h1:  return "ساعة H1"
        case .m30: return "30 دقيقة"
        case .m15: return "15 دقيقة"
        }
    }

    var apiInterval: String {
        switch self {
        case .h1:  return "1h"
        case .m30: return "30min"
        case .m15: return "15min"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .h1:  return 3600
        case .m30: return 1800
        case .m15: return 900
        }
    }
}
