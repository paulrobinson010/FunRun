import SwiftUI

struct ShoeDetailView: View {
    let model: AppModel
    @State var shoe: Shoe

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section("Trainers") {
                TextField("Model", text: $shoe.name)
                ChoiceOrCustomField(title: "Brand", options: ShoePalette.brands, value: $shoe.brand)
                ChoiceOrCustomField(title: "Colour", options: ShoePalette.colours, value: Binding(
                    get: { shoe.color ?? "" },
                    set: { shoe.color = $0.isEmpty ? nil : $0 }
                ))
            }
            Section("Wear") {
                LabeledContent("Distance so far", value: Format.distance(shoe.distanceMeters))
                Stepper(value: $shoe.replaceAfterKm, in: 100...1500, step: 50) {
                    LabeledContent("Replace after", value: "\(Int(shoe.replaceAfterKm)) km")
                }
                ProgressView(value: min(shoe.wearFraction, 1)) {
                    Text("\(Int((shoe.wearFraction * 100).rounded()))% worn")
                        .font(.caption)
                }
            }
            Section {
                Toggle("Retired", isOn: $shoe.retired)
                Button("Delete shoes", role: .destructive) {
                    confirmingDelete = true
                }
            } footer: {
                Text("Retired shoes stay in your history but no longer appear on the watch.")
            }
        }
        .navigationTitle(shoe.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: shoe) {
            model.shoeStore.update(shoe)
            model.pushShoes()
        }
        .confirmationDialog("Delete these trainers?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                model.shoeStore.remove(shoe)
                model.pushShoes()
                dismiss()
            }
        } message: {
            Text("Past runs keep their record, but wear tracking for this pair is gone.")
        }
    }
}
