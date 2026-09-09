import AppKit
import SwiftUI

struct StickyCustomColorPicker: View {
    private let onChange: (Color) -> Void

    @State private var hue: CGFloat
    @State private var saturation: CGFloat
    @State private var brightness: CGFloat
    @State private var opacity: CGFloat
    @State private var hexText: String
    @State private var opacityText: String

    init(color: Color, onChange: @escaping (Color) -> Void) {
        self.onChange = onChange
        let components = Self.components(from: color)
        _hue = State(initialValue: components.hue)
        _saturation = State(initialValue: components.saturation)
        _brightness = State(initialValue: components.brightness)
        _opacity = State(initialValue: components.opacity)
        _hexText = State(initialValue: components.hex)
        _opacityText = State(initialValue: String(Int((components.opacity * 100).rounded())))
    }

    private var opaqueColor: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    private var selectedColor: Color {
        opaqueColor.opacity(opacity)
    }

    var body: some View {
        VStack(spacing: 12) {
            saturationBrightnessField
                .frame(width: 220, height: 148)

            HStack(spacing: 10) {
                eyedropperButton
                VStack(spacing: 10) {
                    hueSlider
                    opacitySlider
                }
            }

            HStack(spacing: 8) {
                Text("Hex")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("FFFFFF", text: $hexText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                    .onSubmit(applyHexText)

                TextField("100", text: $opacityText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 35)
                    .onSubmit(applyOpacityText)

                Text("%")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 220)
    }

    private var saturationBrightnessField: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.18), lineWidth: 1))

                selectionKnob
                    .position(
                        x: saturation * proxy.size.width,
                        y: (1 - brightness) * proxy.size.height
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        saturation = clamped(value.location.x / proxy.size.width)
                        brightness = clamped(1 - value.location.y / proxy.size.height)
                        emitChange()
                    }
            )
        }
        .accessibilityLabel("Saturation and brightness")
    }

    private var hueSlider: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .overlay(Capsule().stroke(.black.opacity(0.16), lineWidth: 1))

                sliderKnob
                    .position(x: hue * proxy.size.width, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        hue = clamped(value.location.x / proxy.size.width)
                        emitChange()
                    }
            )
        }
        .frame(height: 18)
        .accessibilityLabel("Hue")
    }

    private var opacitySlider: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Checkerboard()
                    .clipShape(Capsule())
                Capsule()
                    .fill(LinearGradient(colors: [opaqueColor.opacity(0), opaqueColor], startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().stroke(.black.opacity(0.16), lineWidth: 1))

                sliderKnob
                    .position(x: opacity * proxy.size.width, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        opacity = clamped(value.location.x / proxy.size.width)
                        emitChange()
                    }
            )
        }
        .frame(height: 18)
        .accessibilityLabel("Opacity")
    }

    private var eyedropperButton: some View {
        Button {
            NSColorSampler().show { sampledColor in
                guard let sampledColor else { return }
                apply(sampledColor)
            }
        } label: {
            Image(systemName: "eyedropper")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 26, height: 46)
        }
        .buttonStyle(.plain)
        .help("Pick a colour from the screen")
    }

    private var selectionKnob: some View {
        Circle()
            .fill(selectedColor)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private var sliderKnob: some View {
        Circle()
            .fill(.white)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(.black.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    private func emitChange() {
        hexText = Self.hex(red: selectedColor)
        opacityText = String(Int((opacity * 100).rounded()))
        onChange(selectedColor)
    }

    private func applyHexText() {
        let cleaned = hexText.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            hexText = Self.hex(red: selectedColor)
            return
        }
        let color = NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: opacity
        )
        apply(color)
    }

    private func applyOpacityText() {
        guard let percentage = Double(opacityText) else {
            opacityText = String(Int((opacity * 100).rounded()))
            return
        }
        opacity = clamped(CGFloat(percentage / 100))
        emitChange()
    }

    private func apply(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        var newHue: CGFloat = 0
        var newSaturation: CGFloat = 0
        var newBrightness: CGFloat = 0
        var newOpacity: CGFloat = 0
        rgb.getHue(&newHue, saturation: &newSaturation, brightness: &newBrightness, alpha: &newOpacity)
        hue = newHue
        saturation = newSaturation
        brightness = newBrightness
        opacity = newOpacity
        emitChange()
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private static func components(from color: Color) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, opacity: CGFloat, hex: String) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else {
            return (0, 0, 1, 1, "FFFFFF")
        }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var opacity: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &opacity)
        return (hue, saturation, brightness, opacity, hex(red: color))
    }

    private static func hex(red color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "FFFFFF" }
        return String(
            format: "%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 6
            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for column in 0..<columns {
                    let shade = (row + column).isMultiple(of: 2) ? Color.white : Color.black.opacity(0.13)
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                        with: .color(shade)
                    )
                }
            }
        }
        .background(Color.white)
    }
}
