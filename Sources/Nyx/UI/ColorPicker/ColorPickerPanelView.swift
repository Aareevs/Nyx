import AppKit
import SwiftUI

/// The picker panel: gradient square and hue slider on the left; the color,
/// its contrast, its HEX / RGB / HSL values and the recent colors beside and
/// below them.
struct ColorPickerPanelView: View {
    @ObservedObject private var service = ColorPickerPanelService.shared
    @AppStorage(DefaultsKey.colorPickerBareHex) private var bareHex = false
    @State private var editingHex = false
    @State private var hexDraft = ""
    @State private var copiedRow: String?
    @FocusState private var hexFocused: Bool

    private let squareSize = CGSize(width: 250, height: 150)

    private var swiftUIColor: Color {
        let c = service.rgb
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 12) {
                    saturationSquare
                    hueSlider
                }
                .frame(width: squareSize.width)
                VStack(alignment: .leading, spacing: 10) {
                    colorHeader
                    contrastChips
                    valueRow("HEX", service.hex(bare: bareHex))
                    valueRow("RGB", ColorPickerMath.rgbString(red: service.rgb.red, green: service.rgb.green, blue: service.rgb.blue))
                    valueRow("HSL", ColorPickerMath.hslString(red: service.rgb.red, green: service.rgb.green, blue: service.rgb.blue))
                }
                .frame(maxWidth: .infinity)
            }
            recentRow
        }
        .padding(18)
        .frame(width: 560)
        .background(Color(white: 0.085), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Colour picker").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button { service.pickFromScreen() } label: {
                Label("Pick from screen", systemImage: "eyedropper")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(Color.white, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Button { service.hide() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    // MARK: Square and hue

    private var saturationSquare: some View {
        let hue = service.color.hue
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(hue: hue, saturation: 1, brightness: 1))
            LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .background(Circle().fill(swiftUIColor))
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .offset(x: service.color.saturation * squareSize.width - 8,
                        y: (1 - service.color.brightness) * squareSize.height - 8)
        }
        .frame(width: squareSize.width, height: squareSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            service.color.saturation = min(max(drag.location.x / squareSize.width, 0), 1)
            service.color.brightness = 1 - min(max(drag.location.y / squareSize.height, 0), 1)
        })
        .accessibilityLabel("Saturation and brightness")
    }

    private var hueSlider: some View {
        let stops = (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }
        return ZStack(alignment: .leading) {
            Capsule().fill(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
                .frame(height: 12)
            Circle()
                .fill(Color(hue: service.color.hue, saturation: 1, brightness: 1))
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .offset(x: service.color.hue * (squareSize.width - 16))
        }
        .frame(width: squareSize.width, height: 18)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            service.color.hue = min(max((drag.location.x - 8) / (squareSize.width - 16), 0), 1)
        })
        .accessibilityLabel("Hue")
    }

    // MARK: Color and values

    private var colorHeader: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(swiftUIColor)
                .frame(width: 58, height: 58)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
            if editingHex {
                TextField("#RRGGBB", text: $hexDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .focused($hexFocused)
                    .onSubmit { commitHex() }
                    .onExitCommand { editingHex = false }
            } else {
                Text(service.hex(bare: false))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
            }
            Button {
                if editingHex { commitHex() } else {
                    hexDraft = service.hex(bare: false)
                    editingHex = true
                    hexFocused = true
                }
            } label: {
                Image(systemName: editingHex ? "checkmark" : "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help(editingHex ? "Apply" : "Type a hex value")
            Spacer(minLength: 0)
        }
    }

    private func commitHex() {
        service.select(hex: hexDraft)
        editingHex = false
    }

    private var contrastChips: some View {
        let c = service.rgb
        let contrast = ColorPickerMath.contrast(red: c.red, green: c.green, blue: c.blue)
        return HStack(spacing: 8) {
            chip(ratio: contrast.onWhite, background: .white)
            chip(ratio: contrast.onBlack, background: Color(white: 0.04))
        }
    }

    /// One decimal, in the reader's own number style.
    private func ratioText(_ ratio: Double) -> String {
        ratio.formatted(.number.precision(.fractionLength(1)))
    }

    private func chip(ratio: Double, background: Color) -> some View {
        let grade = ColorContrastGrade(ratio: ratio)
        return HStack(spacing: 5) {
            Text("Aa").font(.system(size: 12, weight: .bold)).foregroundStyle(swiftUIColor)
            Text(ratioText(ratio)).font(.system(size: 11, weight: .semibold)).foregroundStyle(swiftUIColor)
            Text(grade.label).font(.system(size: 8, weight: .bold)).foregroundStyle(swiftUIColor.opacity(0.8))
        }
        .padding(.horizontal, 9).frame(height: 24)
        .background(background, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .accessibilityLabel("Contrast \(ratioText(ratio)) to 1, \(grade.label)")
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 30, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Button { copy(label, value) } label: {
                Image(systemName: copiedRow == label ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(copiedRow == label ? Color.green : .white.opacity(0.55))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Copy \(label)")
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func copy(_ label: String, _ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareNyxSource()
        pasteboard.setString(value, forType: .string)
        service.addCurrentToRecents()
        copiedRow = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedRow == label { copiedRow = nil }
        }
    }

    // MARK: Recent

    private var recentRow: some View {
        HStack(spacing: 8) {
            Text("Recent").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            ForEach(service.recents, id: \.self) { hex in
                if let rgb = ColorPickerMath.rgb(fromHex: hex) {
                    Button { service.select(hex: hex) } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue))
                            .frame(width: 22, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(hex)
                }
            }
            Spacer(minLength: 0)
            Button("Clear") { service.clearRecents() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).frame(height: 24)
                .background(.white.opacity(0.08), in: Capsule())
                .disabled(service.recents.isEmpty)
        }
        .frame(height: 26)
    }
}
