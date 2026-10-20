import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: MarketViewModel
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color(hex: 0x0B0F19).ignoresSafeArea()

            if vm.hasApiKey {
                mainView
            } else {
                WelcomeView()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            if vm.hasApiKey { vm.startPolling() }
        }
    }

    // MARK: - الشاشة الرئيسية

    private var mainView: some View {
        VStack(spacing: 10) {
            header

            // اختيار الفريم الزمني
            Picker("الفريم", selection: $vm.timeFrame) {
                ForEach(TimeFrame.allCases) { tf in
                    Text(tf.title).tag(tf)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: vm.timeFrame) { _ in vm.reload() }
            .colorScheme(.dark)

            if let error = vm.errorMessage {
                Text("⚠️ \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            CandleCountdownView(timeFrame: vm.timeFrame)
                .font(.caption2)
                .foregroundColor(.yellow)

            // الشارت
            ZStack {
                Color(hex: 0x111827)
                if vm.haCandles.isEmpty {
                    if vm.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("لا توجد بيانات بعد…")
                            .foregroundColor(.gray)
                    }
                } else {
                    ChartView(candles: vm.haCandles, zones: vm.zones)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .frame(maxHeight: 340)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            legend

            zonesList
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .refreshable { await vm.refresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("XAU/USD الذهب")
                    .font(.headline)
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Text(String(format: "%.2f", vm.lastPrice))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: 0xFFD54F))
                    if vm.isLoading {
                        ProgressView().scaleEffect(0.6).tint(.gray)
                    }
                }
                Text(vm.status)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                LegendDot(color: Color(hex: 0x22C55E), label: "Order Block صاعد / Demand")
                LegendDot(color: Color(hex: 0xF43F5E), label: "Order Block هابط / Supply")
                LegendDot(color: Color(hex: 0x8B5CF6), label: "فجوة سيولة")
                LegendDot(color: Color(hex: 0x3B82F6), label: "لمس متكرر")
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var zonesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("مناطق الأوردر بوك النشطة")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(vm.zones.filter { $0.state == .active }.count) منطقة")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            if vm.zones.filter({ $0.state == .active }).isEmpty && !vm.haCandles.isEmpty {
                Text("لم يتم العثور على مناطق نشطة على هذا الفريم.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(vm.zones) { zone in
                        ZoneRow(zone: zone)
                    }
                }
            }
            .frame(maxHeight: 170)
        }
    }
}

// MARK: - صف المنطقة في القائمة

struct ZoneRow: View {
    let zone: Zone

    private var color: Color {
        switch zone.kind {
        case .orderBlock: return zone.bull ? Color(hex: 0x22C55E) : Color(hex: 0xF43F5E)
        case .demand:     return Color(hex: 0x22C55E)
        case .supply:     return Color(hex: 0xF43F5E)
        case .gap:        return Color(hex: 0x8B5CF6)
        case .touch:      return Color(hex: 0x3B82F6)
        }
    }

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(zone.kind.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
            Text(zone.state == .broken ? "(مخترقة)" : "")
                .font(.caption2)
                .foregroundColor(.gray)
            Spacer()
            Text(String(format: "%.2f – %.2f", zone.bottom, zone.top))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            Text("×\(zone.touches)")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: 0x1A2238).opacity(zone.state == .broken ? 0.35 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(zone.state == .broken ? 0.55 : 1)
    }
}

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: 0x1A2238))
        .clipShape(Capsule())
    }
}

// MARK: - عدّاد إغلاق الشمعة القادمة

struct CandleCountdownView: View {
    let timeFrame: TimeFrame

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timeFrame.seconds
                - context.date.timeIntervalSince1970
                    .truncatingRemainder(dividingBy: timeFrame.seconds)
            let mm = Int(remaining) / 60
            let ss = Int(remaining) % 60
            Text("⏳ إغلاق الشمعة القادمة بعد \(mm):\(String(format: "%02d", ss))")
        }
    }
}

// MARK: - شاشة الترحيب (إدخال مفتاح API)

struct WelcomeView: View {
    @EnvironmentObject var vm: MarketViewModel
    @State private var keyInput = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("🥇")
                .font(.system(size: 64))

            Text("محلل الذهب — XAU/USD")
                .font(.title.weight(.bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(icon: "clock", text: "فريمات الساعة و 30 و 15 دقيقة")
                FeatureRow(icon: "chart.bar.fill", text: "شموع Heikin Ashi")
                FeatureRow(icon: "rectangle.fill.on.rectangle.fill", text: "مستطيلات الأوردر بوك عند إغلاق الشمعة")
            }

            VStack(alignment: .leading, spacing: 6) {
                SecureField("مفتاح API من Twelve Data", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Text("مفتاح مجاني من twelvedata.com — سجّل مجاناً وانسخ مفتاح API والصقه هنا.")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Button {
                vm.saveApiKey(keyInput)
                vm.startPolling()
            } label: {
                Text("ابدأ التحليل")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer()
        }
        .padding(24)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(Color(hex: 0xFFD54F))
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

// MARK: - الإعدادات

struct SettingsView: View {
    @EnvironmentObject var vm: MarketViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("مفتاح API (Twelve Data)") {
                    SecureField("المفتاح الحالي مخفي", text: $keyInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("حفظ وتحديث") {
                        if !keyInput.trimmingCharacters(in: .whitespaces).isEmpty {
                            vm.saveApiKey(keyInput)
                        }
                        dismiss()
                    }
                }
                Section("بيانات") {
                    Button("تحديث الآن", role: .none) {
                        Task { await vm.refresh() }
                        dismiss()
                    }
                    Button("حذف المفتاح", role: .destructive) {
                        vm.clearSettings()
                        dismiss()
                    }
                }
                Section("عن") {
                    Text("يحدد البرنامج مناطق دفتر الأوامر (Order Blocks / Supply / Demand) على شموع Heikin Ashi، ويرسمها كمستطيلات عند إغلاق كل شمعة. لا تمثل هذه المناطق دفتر أوامر حقيقي من الوسيط، وإنما تقدير ذكي من حركة السعر.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("الإعدادات")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
        }
    }
}
