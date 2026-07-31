import SwiftUI

/// Register trainers and watch their wear build up. Runs done on the watch
/// carry the chosen shoe's ID back here, where the distance accumulates.
struct ShoeListView: View {
    let model: AppModel

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if model.shoeStore.shoes.isEmpty {
                    ContentUnavailableView(
                        "No trainers yet",
                        systemImage: "shoe.2",
                        description: Text("Add the shoes you run in. You'll pick a pair on your watch when starting a workout, and wear is tracked here.")
                    )
                }
                if !model.shoeStore.active.isEmpty {
                    Section("In rotation") {
                        ForEach(model.shoeStore.active) { shoe in
                            NavigationLink(value: shoe.id) {
                                ShoeRow(shoe: shoe)
                            }
                            .listRowBackground(Gaitway.panel)
                        }
                    }
                }
                if !model.shoeStore.retired.isEmpty {
                    Section("Retired") {
                        ForEach(model.shoeStore.retired) { shoe in
                            NavigationLink(value: shoe.id) {
                                ShoeRow(shoe: shoe)
                            }
                            .listRowBackground(Gaitway.panel)
                        }
                    }
                }
            }
            .gaitwayList()
            .navigationTitle("Shoes")
            .navigationDestination(for: UUID.self) { shoeID in
                if let shoe = model.shoeStore.shoes.first(where: { $0.id == shoeID }) {
                    ShoeDetailView(model: model, shoe: shoe)
                }
            }
            .toolbar {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddShoeView(model: model)
            }
        }
    }
}

struct ShoeRow: View {
    let shoe: Shoe

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                ShoeColorDot(colorName: shoe.color)
                Text(shoe.displayName)
                    .font(.headline)
                Spacer()
                Text("\(Int(shoe.distanceKm.rounded())) / \(Int(shoe.replaceAfterKm)) km")
                    .font(.subheadline)
                    .foregroundStyle(Gaitway.muted)
            }
            WearBar(fraction: shoe.wearFraction)
            if shoe.wearFraction >= 1 {
                Text("Past its replacement distance")
                    .font(.caption)
                    .foregroundStyle(Gaitway.magenta)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Wear as a neon bar: cyan while there's life left, sweeping to
/// magenta as the pair runs out — the brand's own two colours doing
/// the work a traffic light used to.
struct WearBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            let filled = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: filled < 0.7 ? [Gaitway.cyan, Gaitway.cyan] : [Gaitway.cyan, Gaitway.magenta],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(3, geometry.size.width * filled))
                    .gaitwayGlow(filled < 0.7 ? Gaitway.cyan : Gaitway.magenta, radius: 6)
            }
        }
        .frame(height: 6)
    }
}
