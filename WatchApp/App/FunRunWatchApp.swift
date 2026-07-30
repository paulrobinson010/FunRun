import SwiftUI

@main
struct FunRunWatchApp: App {
    @State private var workout = WorkoutManager()
    @State private var sync = WatchSync()

    var body: some Scene {
        WindowGroup {
            if DemoMode.isActive {
                DemoRootView(workout: workout, sync: sync)
            } else {
                RootView(workout: workout, sync: sync)
                    .onAppear {
                        workout.onFinished = { sync.send($0) }
                        sync.attach(routeStore: workout.routeStore)
                    }
            }
        }
    }
}

struct RootView: View {
    let workout: WorkoutManager
    let sync: WatchSync

    var body: some View {
        switch workout.phase {
        case .idle, .starting, .failed:
            StartView(workout: workout, sync: sync)
        case .active, .paused, .ending:
            SessionView(workout: workout)
        case .ended:
            SummaryView(workout: workout)
        }
    }
}
