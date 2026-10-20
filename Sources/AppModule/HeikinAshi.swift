import Foundation

/// حاسبة شموع Heikin Ashi من الشموع الخام
enum HeikinAshi {
    static func candles(from raw: [Candle]) -> [Candle] {
        guard !raw.isEmpty else { return [] }

        var result: [Candle] = []
        result.reserveCapacity(raw.count)

        // الشمعة الأولى: البداية
        let first = raw[0]
        var prevHAOpen = (first.open + first.close) / 2
        var prevHAClose = (first.open + first.high + first.low + first.close) / 4

        result.append(Candle(
            time: first.time,
            open: prevHAOpen,
            high: max(first.high, prevHAOpen, prevHAClose),
            low: min(first.low, prevHAOpen, prevHAClose),
            close: prevHAClose
        ))

        for i in 1..<raw.count {
            let c = raw[i]
            let haClose = (c.open + c.high + c.low + c.close) / 4
            let haOpen = (prevHAOpen + prevHAClose) / 2
            let haHigh = max(c.high, haOpen, haClose)
            let haLow = min(c.low, haOpen, haClose)

            result.append(Candle(time: c.time, open: haOpen, high: haHigh, low: haLow, close: haClose))

            prevHAOpen = haOpen
            prevHAClose = haClose
        }

        return result
    }
}
