import SwiftUI

@main
struct FunRunApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}

struct ContentView: View {
    let model: AppModel

    var body: some View {
        TabView {
            ShoeListView(model: model)
                .tabItem {
                    Label("Shoes", systemImage: "shoe.2")
                }
            NetworkView(model: model)
                .tabItem {
                    Label("Network", systemImage: "map")
                }
            RoutePlannerView(model: model)
                .tabItem {
                    Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
            HistoryView(model: model)
                .tabItem {
                    Label("History", systemImage: "list.bullet.rectangle")
                }
        }
    }
}
