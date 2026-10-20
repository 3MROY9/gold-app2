import Foundation

/// منطقة سيولة تُرسم كمستطيل على الشارت (عند إغلاق الشمعة)
struct Zone: Identifiable, Equatable {
    enum Kind: String {
        case orderBlock = "Order Block"
        case supply = "عرض Supply"
        case demand = "طلب Demand"
        case touch  = "لمس متكرر"
        case gap    = "فجوة/تسرب Imbalance"
    }

    enum State: String {
        case active = "نشطة"
        case broken = "مخترقة"
    }

    let id: String
    let kind: Kind
    /// true = منطقة طلب/دعم (اخضر) / false = منطقة عرض/مقاومة (أحمر)
    let bull: Bool
    let top: Double
    let bottom: Double
    /// رقم الشمعة في المصفوفة التي أُنشئ عندها المستطيل (عند إغلاقها)
    let startBar: Int
    let startBarTime: Date
    let touches: Int
    var state: State = .active
}

/// كاشف مناطق دفتر الأوامر:
///  1) Order Blocks — الشمعة المعاكسة الأخيرة قبل الحركة القوية، المستطيل يظهر عند إغلاق شمعة الدفعة
///  2) Supply/Demand — من القمم والقيعان غير المكسورة
///  3) فجوات السيولة — المسافات بين الشموع غير الملموسة
///  4) مستويات اللمس المتكرر — قمم/قيعان متقاربة تتكرر 3 مرات أو أكثر
enum ZoneDetector {
    struct Config {
        /// عدد الشموع على جانبي القمة/القاع لتأكيد السوينغ
        var swingLookback = 3
        /// حجم جسم شمعة الدفعة كنسبة من متوسط الأجسام ليُعتبر "دفعة"
        var impulseBodyFactor = 1.6
        /// نسبة تجميع المستويات المتقاربة (0.08% من السعر)
        var clusterPct = 0.0008
        /// الحد الأدنى لعدد اللمسات لاعتبار المستوى "لمس متكرر"
        var minTouches = 3
        var thinZoneHeightPct = 0.0006
        var minZoneHeightPct = 0.0003
        /// أقصى عدد مناطق نشطة تُعرض
        var maxActiveZones = 14
        /// آخر عدد شموع نبحث فيها عن مناطق
        var searchBars = 240
    }

    static func detect(raw: [Candle], ha: [Candle], config: Config = Config()) -> [Zone] {
        guard ha.count >= 15, raw.count == ha.count else { return [] }

        var zones: [Zone] = []
        let basePrice = ha[ha.count - 2].close
        let minZone = basePrice * config.minZoneHeightPct
        let eps = basePrice * 0.00003
        let searchStart = max(3, ha.count - config.searchBars)

        /// عدد الشموع التي ارتدت على المنطقة
        func touchCount(top: Double, bottom: Double, after: Int) -> Int {
            guard after < ha.count - 1 else { return 0 }
            var n = 0
            for k in after..<(ha.count - 1)
            where ha[k].low <= top && ha[k].high >= bottom { n += 1 }
            return n
        }

        func averageBody(until index: Int, window: Int = 15) -> Double {
            guard index < ha.count else { return 1 }
            let lower = max(0, index - window)
            let slice = ha[lower...index]
            guard !slice.isEmpty else { return 1 }
            let sum = slice.reduce(0.0) { $0 + $1.bodySize }
            return max(sum / Double(slice.count), 0.00001)
        }

        // ================= 1) Order Blocks =================
        // شمعة الدفعة القوية j → آخر شمعه معاكسة قبلها هي الاوردر بوك
        for j in (searchStart + 1)..<(ha.count - 1) {
            let impulse = ha[j]
            guard impulse.bodySize > averageBody(until: j) * config.impulseBodyFactor else { continue }

            var obIndex = j - 1
            while obIndex > 0 && ha[obIndex].isBullish == impulse.isBullish { obIndex -= 1 }
            guard ha[obIndex].isBullish != impulse.isBullish else { continue }

            let ob = ha[obIndex]
            var top = ob.bodyTop
            var bottom = ob.bodyBottom
            if top - bottom < minZone {
                top = ob.high
                bottom = ob.low
            }
            guard top - bottom >= minZone else { continue }

            var state: Zone.State = .active
            for k in (j + 1)..<(ha.count - 1) {
                let broken = impulse.isBullish ? ha[k].close < bottom : ha[k].close > top
                if broken { state = .broken; break }
            }

            zones.append(Zone(
                id: "OB-\(obIndex)-\(j)",
                kind: .orderBlock,
                bull: impulse.isBullish,
                top: top,
                bottom: bottom,
                startBar: j, // يظهر المستطيل عند إغلاق شمعة الدفعة
                startBarTime: ha[j].time,
                touches: touchCount(top: top, bottom: bottom, after: j),
                state: state
            ))
        }

        // ================= 2) Supply / Demand من السوينفس =================
        // القمم والقيعان غير المكسورة → منطقة عرض/طلب قرب ترف الويك
        var extremes: [(price: Double, index: Int, isHigh: Bool)] = []

        for i in (searchStart + config.swingLookback)..<(ha.count - 1 - config.swingLookback) {
            let c = ha[i]
            var swingHigh = true
            var swingLow = true
            for k in 1...config.swingLookback {
                if ha[i - k].high > c.high || ha[i + k].high > c.high { swingHigh = false }
                if ha[i - k].low < c.low || ha[i + k].low < c.low { swingLow = false }
            }

            if swingHigh {
                extremes.append((c.high, i, true))
                let top = c.high
                let bottomRaw = max(c.bodyTop, top - basePrice * config.thinZoneHeightPct * 3)
                let bottom = min(bottomRaw, top - minZone)
                var state: Zone.State = .active
                for k in (i + 1)..<(ha.count - 1) where ha[k].close > top + eps * 6 {
                    state = .broken; break
                }
                zones.append(Zone(
                    id: "SUP-\(i)",
                    kind: .supply,
                    bull: false,
                    top: top,
                    bottom: bottom,
                    startBar: i, // المستطيل يبدأ عند إغلاق شمعة القمة
                    startBarTime: c.time,
                    touches: touchCount(top: top, bottom: bottom, after: i),
                    state: state
                ))
            }

            if swingLow {
                extremes.append((c.low, i, false))
                let bottom = c.low
                let topRaw = min(c.bodyBottom, bottom + basePrice * config.thinZoneHeightPct * 3)
                let top = max(topRaw, bottom + minZone)
                var state: Zone.State = .active
                for k in (i + 1)..<(ha.count - 1) where ha[k].close < bottom - eps * 6 {
                    state = .broken; break
                }
                zones.append(Zone(
                    id: "DEM-\(i)",
                    kind: .demand,
                    bull: true,
                    top: top,
                    bottom: bottom,
                    startBar: i, // المستطيل يبدأ عند إغلاق شمعة القاع
                    startBarTime: c.time,
                    touches: touchCount(top: top, bottom: bottom, after: i),
                    state: state
                ))
            }
        }

        // ================= 3) فجوات السيولة =================
        // تُقاس من الشموع الخام (الهيكن آشي يلس الفجوات)
        for i in searchStart..<(raw.count - 2) {
            let c = raw[i]
            let n = raw[i + 1]

            // فجوة صاعدة: افتتاح الشمعة التالية فوق قمة السابقة
            if n.low > c.high {
                let top = n.low
                let bottom = c.high
                if top - bottom >= minZone {
                    var state: Zone.State = .active
                    for k in (i + 2)..<(raw.count - 1) where raw[k].low <= bottom + eps {
                        state = .broken; break
                    }
                    zones.append(Zone(
                        id: "GAPU-\(i)",
                        kind: .gap,
                        bull: true,
                        top: top,
                        bottom: bottom,
                        startBar: i + 1,
                        startBarTime: n.time,
                        touches: touchCount(top: top, bottom: bottom, after: i + 1),
                        state: state
                    ))
                }
            }

            // فجوة هابطة: افتتاح الشمعة التالية تحت قاع السابقة
            if n.high < c.low {
                let top = c.low
                let bottom = n.high
                if top - bottom >= minZone {
                    var state: Zone.State = .active
                    for k in (i + 2)..<(raw.count - 1) where raw[k].high >= top - eps {
                        state = .broken; break
                    }
                    zones.append(Zone(
                        id: "GAPD-\(i)",
                        kind: .gap,
                        bull: false,
                        top: top,
                        bottom: bottom,
                        startBar: i + 1,
                        startBarTime: n.time,
                        touches: touchCount(top: top, bottom: bottom, after: i + 1),
                        state: state
                    ))
                }
            }
        }

        // ================= 4) مستويات اللمس المتكرر =================
        func buildClusters(swingPoints: [(price: Double, index: Int, isHigh: Bool)], isHighSide: Bool) -> [[(price: Double, index: Int, isHigh: Bool)]] {
            let sorted = swingPoints.sorted { $0.price < $1.price }
            var groups: [[(price: Double, index: Int, isHigh: Bool)]] = []
            var idx = 0
            while idx < sorted.count {
                let reference = sorted[idx].price
                let tolerance = max(reference * config.clusterPct, 0.05)
                var j = idx + 1
                while j < sorted.count && sorted[j].price - reference <= tolerance { j += 1 }
                groups.append(Array(sorted[idx..<j]))
                idx = j
            }
            return groups
        }

        for isHighSide in [true, false] {
            let points = extremes.filter { $0.isHigh == isHighSide }
            for group in buildClusters(swingPoints: points, isHighSide: isHighSide) {
                let touchedBars = Set(group.map(\.index))
                guard touchedBars.count >= config.minTouches else { continue }

                let level = group.map(\.price).reduce(0, +) / Double(group.count)
                let half = max(level * config.thinZoneHeightPct, 0.05)
                let firstIndex = touchedBars.min() ?? 0

                var state: Zone.State = .active
                for k in (firstIndex + 1)..<(ha.count - 1) {
                    let pierced = isHighSide
                        ? ha[k].close > level + half * 3
                        : ha[k].close < level - half * 3
                    if pierced { state = .broken; break }
                }

                zones.append(Zone(
                    id: "TOUCH-\(isHighSide ? "H" : "L")-\(firstIndex)",
                    kind: .touch,
                    bull: !isHighSide, // مستوى دعم تحت السعر = أخضر، فوقه = أحمر
                    top: isHighSide ? level + half : level - half,
                    bottom: isHighSide ? level - half : level + half,
                    startBar: firstIndex,
                    startBarTime: ha[firstIndex].time,
                    touches: touchedBars.count,
                    state: state
                ))
            }
        }

        // ================= تنقية: إزالة التداخل + الحد الأقصى =================
        func overlapRatio(_ a: Zone, _ b: Zone) -> Double {
            let top = min(a.top, b.top)
            let bottom = max(a.bottom, b.bottom)
            guard top > bottom else { return 0 }
            let smaller = min(a.top - a.bottom, b.top - b.bottom)
            return smaller > 0 ? (top - bottom) / smaller : 0
        }

        var result: [Zone] = []
        for zone in zones {
            // هل تتداخل مع مناطق موجودة مسبقاً؟
            var overlappingExisting: Zone? = nil
            for existing in result {
                if existing.bull == zone.bull && overlapRatio(existing, zone) > 0.7 {
                    overlappingExisting = existing
                    break
                }
            }

            if let existing = overlappingExisting {
                // نُفضّل عادة الاوردر بوك (أقوى منطقة)
                if zone.kind == .orderBlock && existing.kind != .orderBlock {
                    result.removeAll { $0.id == existing.id }
                    result.append(zone)
                }
                // وإلا نتجاهل المنطقة الجديدة المتداخلة
            } else {
                result.append(zone)
            }
        }

        // نسارياً الترتيب الأخضر ثم الأحمر ثم فجوة ثم لمس
        func priority(_ kind: Zone.Kind) -> Int {
            switch kind {
            case .orderBlock: return 0
            case .demand, .supply: return 1
            case .gap: return 2
            case .touch: return 3
            }
        }

        let active = result.filter { $0.state == .active }
            .sorted { a, b in
                let pa = priority(a.kind), pb = priority(b.kind)
                if pa != pb { return pa < pb }
                return a.startBarTime > b.startBarTime
            }
            .prefix(config.maxActiveZones)

        let broken = result.filter { $0.state == .broken }.suffix(10)

        return Array(active).sorted { $0.startBarTime < $1.startBarTime }
            + Array(broken).sorted { $0.startBarTime < $1.startBarTime }
    }
}
