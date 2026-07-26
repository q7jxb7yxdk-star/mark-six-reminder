import SwiftUI

/// The root container for Jackpot Alert's feature areas.
struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("首頁", systemImage: "house")
                }

            RandomNumbersView()
                .tabItem {
                    Label("運財號碼", systemImage: "dice.fill")
                }

            CustomNumbersView()
                .tabItem {
                    Label("自選號碼", systemImage: "circle.grid.3x3.fill")
                }

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
        .tint(.red)
    }
}
