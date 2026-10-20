import SwiftUI

@main
struct GoldOrderBookApp: App {
    @StateObject private var viewModel = MarketViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
