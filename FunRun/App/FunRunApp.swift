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

    init(model: AppModel) {
        self.model = model
        // The tab bar and nav bars are UIKit underneath; brand them
        // once here so every screen sits on the same near-black.
        let background = UIColor(Gaitway.background)
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = background
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = background
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }

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
        .tint(Gaitway.cyan)
        // The logo is a dark-world mark; the app lives in that world.
        .preferredColorScheme(.dark)
    }
}
