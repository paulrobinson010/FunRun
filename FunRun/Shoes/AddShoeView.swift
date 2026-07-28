import SwiftUI

struct AddShoeView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var colour = ""
    @State private var replaceAfterKm = 650.0
    @State private var alreadyRunKm = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Trainers") {
                    TextField("Model (e.g. Pegasus 41)", text: $name)
                    ChoiceOrCustomField(title: "Brand", options: ShoePalette.brands, value: $brand)
                    ChoiceOrCustomField(title: "Colour", options: ShoePalette.colours, value: $colour)
                }
                Section("Wear") {
                    Stepper(value: $replaceAfterKm, in: 100...1500, step: 50) {
                        LabeledContent("Replace after", value: "\(Int(replaceAfterKm)) km")
                    }
                    Stepper(value: $alreadyRunKm, in: 0...1500, step: 10) {
                        LabeledContent("Already run", value: "\(Int(alreadyRunKm)) km")
                    }
                }
            }
            .navigationTitle("Add shoes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        model.shoeStore.add(Shoe(
                            name: name.trimmingCharacters(in: .whitespaces),
                            brand: brand.trimmingCharacters(in: .whitespaces),
                            replaceAfterKm: replaceAfterKm,
                            distanceMeters: alreadyRunKm * 1000,
                            color: colour.isEmpty ? nil : colour
                        ))
                        model.pushShoes()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
