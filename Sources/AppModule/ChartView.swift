import SwiftUI

/// شارت الشموع: يرسم شموع Heikin Ashi + مستطيلات مناطق الأوردر بوك
struct ChartView: View {
    let candles: [Candle]
    let zones: [Zone]

    private let barsToShow = 130

    var body: some View {
        Canvas { context, size in
            draw(&context, size: size)
        }
    }

    private func zoneColor(_ zone: Zone) -> Color {
        switch zone.kind {
        case .orderBlock: return zone.bull ? Color(hex: 0x22C55E) : Color(hex: 0xF43F5E)
        case .demand:     return Color(hex: 0x22C55E)
        case .supply:     return Color(hex: 0xF43F5E)
        case .gap:        return Color(hex: 0x8B5CF6)
        case .touch:      return Color(hex: 0x3B82F6)
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let bars = Array(candles.suffix(barsToShow))
        guard !bars.isEmpty else { return }
        let offset = candles.count - bars.count

        // نطاق السعر: من الشموع + المناطق النشطة القريبة
        var minPrice = bars.map(\.low).min() ?? 0
        var maxPrice = bars.map(\.high).max() ?? 1

        for zone in zones where zone.state == .active && zone.startBar >= offset - 5 {
            if zone.top > maxPrice && zone.top < maxPrice * 1.03 { maxPrice = zone.top }
            if zone.bottom < minPrice && zone.bottom > minPrice * 0.97 { minPrice = zone.bottom }
        }

        let span = max(maxPrice - minPrice, 0.5)
        minPrice -= span * 0.06
        maxPrice += span * 0.06
        let range = maxPrice - minPrice

        func y(_ price: Double) -> CGFloat {
            CGFloat((maxPrice - price) / range) * size.height
        }

        let slot = size.width / CGFloat(max(bars.count, 10))
        let candleWidth = max(1.5, slot * 0.62)

        // ===== شبكة السعر =====
        for step in 0...4 {
            let price = minPrice + range * Double(step) / 5
            let lineY = y(price)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: lineY))
            line.addLine(to: CGPoint(x: size.width, y: lineY))
            context.stroke(line, with: .color(.gray.opacity(0.18)), lineWidth: 0.5)
            context.draw(
                Text(String(format: "%.1f", price))
                    .font(.system(size: 9))
                    .foregroundColor(.gray.opacity(0.8)),
                at: CGPoint(x: size.width - 28, y: lineY - 8)
            )
        }

        // ===== مستطيلات المناطق =====
        // تُرسم من الشمعة التي أُنشئت عندها المستطيل (عند إغلاقها) حتى طرف الشارت
        for zone in zones.reversed() {
            let startIndex = max(0, zone.startBar - offset)
            if startIndex >= bars.count { continue }

            let x0 = CGFloat(startIndex) * slot
            let yTop = y(zone.top)
            let yBottom = y(zone.bottom)
            let height = max(1.5, yBottom - yTop)
            let rect = CGRect(x: x0, y: yTop, width: size.width - x0, height: height)
            let color = zoneColor(zone)

            context.fill(Path(rect), with: .color(color.opacity(zone.state == .broken ? 0.10 : 0.22)))
            context.stroke(Path(rect), with: .color(color.opacity(zone.state == .broken ? 0.35 : 0.9)), lineWidth: 0.8)

            if height > 13 && height < 70 {
                context.draw(
                    Text("\(zone.kind.rawValue) ×\(zone.touches)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(color),
                    at: CGPoint(x: rect.minX + 52, y: rect.midY)
                )
            } else if height <= 13 {
                // مستطيل رفيع: نكتب بجانبه
                context.draw(
                    Text("\(zone.kind.rawValue) ×\(zone.touches)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(color.opacity(0.9)),
                    at: CGPoint(x: rect.minX + 52, y: rect.maxY + 7)
                )
            }
        }

        // ===== شموع هيكن آشي =====
        for (i, candle) in bars.enumerated() {
            let xc = slot * (CGFloat(i) + 0.5)
            let color: Color = candle.isBullish ? Color(hex: 0x26A69A) : Color(hex: 0xEF5350)

            // الذيل
            var wick = Path()
            wick.move(to: CGPoint(x: xc, y: y(candle.high)))
            wick.addLine(to: CGPoint(x: xc, y: y(candle.low)))
            context.stroke(wick, with: .color(color), lineWidth: 1)

            // الجسم
            let bodyTop = y(candle.bodyTop)
            let bodyBottom = y(candle.bodyBottom)
            let bodyRect = CGRect(
                x: xc - candleWidth / 2,
                y: bodyTop,
                width: candleWidth,
                height: max(1, bodyBottom - bodyTop)
            )
            context.fill(Path(bodyRect), with: .color(color))
        }

        // ===== خط السعر الحالي =====
        if let last = bars.last {
            let yc = y(last.close)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: yc))
            line.addLine(to: CGPoint(x: size.width, y: yc))
            context.stroke(
                line,
                with: .color(.white.opacity(0.5)),
                style: StrokeStyle(lineWidth: 0.8, dash: [4, 3])
            )

            // شعار السعر على يمين الشارت
            let label = String(format: "%.2f", last.close)
            let badgeRect = CGRect(x: size.width - 58, y: yc - 10, width: 56, height: 20)
            context.fill(Path(badgeRect), with: .color(Color(hex: 0x26A69A).opacity(0.9)))
            context.draw(
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white),
                at: CGPoint(x: badgeRect.midX, y: badgeRect.midY)
            )
        }
    }
}

// MARK: - مساعد الألوان (HEX)

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
