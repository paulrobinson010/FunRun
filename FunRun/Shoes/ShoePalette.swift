import SwiftUI

/// The dropdown choices when registering trainers — the brands and
/// colourways that cover almost every pair, with "Custom…" as the escape
/// hatch for the rest.
enum ShoePalette {
    static let brands = [
        "Adidas", "Altra", "Asics", "Brooks", "Hoka", "Inov-8", "Mizuno",
        "New Balance", "Nike", "On", "Puma", "Reebok", "Salomon",
        "Saucony", "Under Armour",
    ]

    static let colours = [
        "Black", "White", "Grey", "Red", "Orange", "Yellow", "Green",
        "Blue", "Purple", "Pink", "Multicolour",
    ]

    /// A fill for the little colour dot; nil for names it doesn't know.
    static func swatch(for name: String?) -> AnyShapeStyle? {
        switch name?.lowercased() {
        case "black": AnyShapeStyle(Color.black)
        case "white": AnyShapeStyle(Color.white)
        case "grey", "gray": AnyShapeStyle(Color.gray)
        case "red": AnyShapeStyle(Color.red)
        case "orange": AnyShapeStyle(Color.orange)
        case "yellow": AnyShapeStyle(Color.yellow)
        case "green": AnyShapeStyle(Color.green)
        case "blue": AnyShapeStyle(Color.blue)
        case "purple": AnyShapeStyle(Color.purple)
        case "pink": AnyShapeStyle(Color.pink)
        case "multicolour", "multicolor": AnyShapeStyle(AngularGradient(
            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
            center: .center
        ))
        default: nil
        }
    }
}

/// The colour dot shown next to a pair in lists.
struct ShoeColorDot: View {
    let colorName: String?

    var body: some View {
        if let fill = ShoePalette.swatch(for: colorName) {
            Circle()
                .fill(fill)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
                .frame(width: 10, height: 10)
        }
    }
}

/// A picker over common options with a "Custom…" choice that reveals a
/// text field — used for brand and colour.
struct ChoiceOrCustomField: View {
    let title: String
    let options: [String]
    @Binding var value: String

    private static let custom = "Custom…"

    @State private var selection: String
    @State private var customText: String

    init(title: String, options: [String], value: Binding<String>) {
        self.title = title
        self.options = options
        _value = value
        let current = value.wrappedValue
        if current.isEmpty {
            _selection = State(initialValue: options.first ?? Self.custom)
            _customText = State(initialValue: "")
        } else if options.contains(current) {
            _selection = State(initialValue: current)
            _customText = State(initialValue: "")
        } else {
            _selection = State(initialValue: Self.custom)
            _customText = State(initialValue: current)
        }
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
            Text(Self.custom).tag(Self.custom)
        }
        .onChange(of: selection) { sync() }
        .onAppear { sync() }

        if selection == Self.custom {
            TextField("\(title) name", text: $customText)
                .onChange(of: customText) { sync() }
        }
    }

    private func sync() {
        value = selection == Self.custom
            ? customText.trimmingCharacters(in: .whitespaces)
            : selection
    }
}
