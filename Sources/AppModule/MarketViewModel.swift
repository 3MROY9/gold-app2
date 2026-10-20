import Foundation
import SwiftUI

@MainActor
final class MarketViewModel: ObservableObject {
    @Published var timeFrame: TimeFrame = .h1
    @Published var rawCandles: [Candle] = []
    @Published var haCandles: [Candle] = []
    @Published var zones: [Zone] = []
    @Published var lastPrice: Double = 0
    @Published var status: String = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var flashMessage: String?
    @Published var apiKey: String = ""

    var hasApiKey: Bool { !apiKey.isEmpty }

    private var lastClosedTime: Date?
    private var pollTask: Task<Void, Never>?

    private static let storageKey = "twelveDataApiKey"

    init() {
        apiKey = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
    }

    // MARK: - التحكم بالمفتاح والتحديث

    func saveApiKey(_ key: String) {
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(apiKey, forKey: Self.storageKey)
        reload()
    }

    /// إعادة تحميل كاملة (عند تغيير الفريم مثلاً)
    func reload() {
        zones = []
        rawCandles = []
        haCandles = []
        lastClosedTime = nil
        startPolling()
    }

    /// تحديث دوري كل 30 ثانية + إعادة حساب المناطق عند كل إغلاق شمعة
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func refresh() async {
        guard hasApiKey else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await PriceService(apiKey: apiKey).fetchCandles(timeFrame: timeFrame)

            errorMessage = nil
            rawCandles = data
            haCandles = HeikinAshi.candles(from: data)

            if let last = data.last {
                lastPrice = last.close
                status = "آخر تحديث: \(last.time.formatted(date: .omitted, time: .standard))"
            }

            // الشمعة الأخيرة من الخادم تكون قيد التكوين، نحسب المناطق من الشموع المغلقة فقط
            let closed = Array(data.dropLast())
            let closedLastTime = closed.last?.time

            let isNewCandleClose = closedLastTime != lastClosedTime
            lastClosedTime = closedLastTime

            if isNewCandleClose {
                let closedHA = HeikinAshi.candles(from: closed)
                zones = ZoneDetector.detect(raw: closed, ha: closedHA)
                flashMessage = "تم رسم مستطيلات الأوردر بوك عند إغلاق الشمعة ✓"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearSettings() {
        apiKey = ""
        UserDefaults.standard.set("", forKey: Self.storageKey)
        zones = []
        rawCandles = []
        haCandles = []
    }
}
