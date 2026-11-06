import SwiftUI

@main
struct CrackTrackerApp: App {
    @StateObject private var store = GameStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    if store.isStale { await store.refresh() }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await GameStore.shared.refresh()
            BackgroundRefresh.schedule()
        }
    }
}
