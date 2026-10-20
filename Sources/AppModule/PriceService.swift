import Foundation

enum PriceServiceError: LocalizedError {
    case missingAPIKey
    case badURL
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "لا يوجد مفتاح API. افتح الإعدادات وأدخل مفتاح Twelve Data."
        case .badURL:
            return "رابط غير صالح"
        case .badResponse(let message):
            return message
        }
    }
}

/// خدمة جلب بيانات شموع الذهب XAU/USD من Twelve Data
struct PriceService {
    let apiKey: String

    func fetchCandles(timeFrame: TimeFrame, limit: Int = 400) async throws -> [Candle] {
        guard !apiKey.isEmpty else { throw PriceServiceError.missingAPIKey }

        var components = URLComponents(string: "https://api.twelvedata.com/time_series")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: "XAU/USD"),
            URLQueryItem(name: "interval", value: timeFrame.apiInterval),
            URLQueryItem(name: "outputsize", value: String(limit)),
            URLQueryItem(name: "order", value: "ASC"),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "format", value: "JSON"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]

        guard let url = components?.url else { throw PriceServiceError.badURL }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(TwelveDataResponse.self, from: data)

        if decoded.status == "error" {
            throw PriceServiceError.badResponse(decoded.message ?? "خطأ من الخادم")
        }

        guard let values = decoded.values, !values.isEmpty else {
            throw PriceServiceError.badResponse("لم يتم استلام أي بيانات من الخادم")
        }

        // تنسيقات محتملة للتاريخ: "2024-06-01 12:00:00" أو "2024-06-01"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd"
        fallback.timeZone = TimeZone(identifier: "UTC")
        fallback.locale = Locale(identifier: "en_US_POSIX")

        var candles: [Candle] = []
        candles.reserveCapacity(values.count)

        for value in values {
            let date = formatter.date(from: value.datetime)
                ?? fallback.date(from: value.datetime)
                ?? Date()

            guard
                let open = Double(value.open),
                let high = Double(value.high),
                let low = Double(value.low),
                let close = Double(value.close)
            else { continue }

            candles.append(Candle(time: date, open: open, high: high, low: low, close: close))
        }

        candles.sort { $0.time < $1.time }
        return candles
    }
}

private struct TwelveDataResponse: Decodable {
    struct Bar: Decodable {
        let datetime: String
        let open: String
        let high: String
        let low: String
        let close: String
    }

    let values: [Bar]?
    let status: String?
    let message: String?
}
