import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            GameListView(mode: .uncracked)
                .tabItem { Label("Uncracked", systemImage: "lock.fill") }
            GameListView(mode: .cracked)
                .tabItem { Label("Cracked", systemImage: "lock.open.fill") }
            GameListView(mode: .watchlist)
                .tabItem { Label("Watchlist", systemImage: "star.fill") }
            SourcesView()
                .tabItem { Label("Sources", systemImage: "antenna.radiowaves.left.and.right") }
        }
    }
}

#Preview {
    ContentView().environmentObject(GameStore.shared)
}
