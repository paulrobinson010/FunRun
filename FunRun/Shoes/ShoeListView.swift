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
                        }
                    }
                }
                if !model.shoeStore.retired.isEmpty {
                    Section("Retired") {
                        ForEach(model.shoeStore.retired) { shoe in
                            NavigationLink(value: shoe.id) {
                                ShoeRow(shoe: shoe)
                            }
                        }
                    }
                }
            }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(shoe.displayName)
                    .font(.headline)
                Spacer()
                Text("\(Int(shoe.distanceKm.rounded())) / \(Int(shoe.replaceAfterKm)) km")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(shoe.wearFraction, 1))
                .tint(wearColor)
            if shoe.wearFraction >= 1 {
                Text("Past its replacement distance")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private var wearColor: Color {
        switch shoe.wearFraction {
        case ..<0.7: .green
        case ..<0.9: .yellow
        default: .red
        }
    }
}
