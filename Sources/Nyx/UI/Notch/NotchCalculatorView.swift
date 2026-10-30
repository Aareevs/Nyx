import AppKit
import SwiftUI

/// What a key does when pressed.
private enum CalculatorKeyAction {
    case insert(String)
    case clear, backspace, equals
    case fraction, derivative, integral, definite
}

private struct CalculatorKey: Identifiable {
    enum Kind { case digit, op, function, equals, utility }
    let id = UUID()
    let label: String
    let action: CalculatorKeyAction
    var kind: Kind = .function

    static func insert(_ label: String, _ text: String? = nil, kind: Kind = .function) -> CalculatorKey {
        CalculatorKey(label: label, action: .insert(text ?? label), kind: kind)
    }
}

/// The calculator page: three keypads over one display.
struct NotchCalculatorView: View {
    let size: CGSize
    @ObservedObject private var model = NotchCalculatorModel.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchCalculatorStrings { FeatureStrings.notchCalculator(l10n.language) }

    private let rows = 5
    private let spacing: CGFloat = 6
    private var compact: Bool { size.height < 300 }
    private var displayHeight: CGFloat { compact ? 46 : 84 }

    var body: some View {
        VStack(spacing: 8) {
            // A short island has no room for a row of modes: they become a menu beside the camera.
            if !compact { modePicker }
            display
            if model.mode == .calculus, model.definite { limits }
            keypad
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .notchBand(leading: { if compact { modeMenu } }, trailing: {
            Button { model.angle = model.angle == .degrees ? .radians : .degrees } label: {
                Text(model.angle == .degrees ? text.degrees : text.radians)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(model.mode == .calculus ? .white.opacity(0.3) : .white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.mode == .calculus)
            .help(model.mode == .calculus ? text.calculusAnglesNote
                  : (model.angle == .degrees ? text.degreesHelp : text.radiansHelp))
            NotchIconButton(symbol: "doc.on.doc", title: text.copy) { model.copyResult() }
        })
    }

    // MARK: Mode

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(CalculatorMode.allCases, id: \.self) { mode in
                Button { model.mode = mode } label: {
                    Text(title(of: mode))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(model.mode == mode ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(.white.opacity(model.mode == mode ? 0.14 : 0),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var modeMenu: some View {
        Menu {
            ForEach(CalculatorMode.allCases, id: \.self) { mode in
                Button { model.mode = mode } label: {
                    if model.mode == mode { Label(title(of: mode), systemImage: "checkmark") } else { Text(title(of: mode)) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title(of: model.mode)).font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(.white.opacity(0.1), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func title(of mode: CalculatorMode) -> String {
        switch mode {
        case .basic: return text.basic
        case .trigonometry: return text.trigonometry
        case .calculus: return text.calculus
        }
    }

    // MARK: Display

    private var display: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if !compact {
                Text(model.previous.isEmpty ? " " : model.previous)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            TextField(model.mode == .calculus ? text.calculusHint : text.placeholder, text: $model.expression)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .onSubmit { model.equals() }
            if let error = model.error {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(1)
            } else {
                Button { model.useResult() } label: {
                    Text(model.hasResult ? model.resultText : " ")
                        .font(.system(size: compact ? 18 : 26, weight: .light, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .help(text.useResult)
            }
            if !compact {
                Text(model.secondary.isEmpty ? " " : model.secondary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: displayHeight)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var limits: some View {
        HStack(spacing: 8) {
            Text(text.from).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            limitField($model.lower)
            Text(text.to).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            limitField($model.upper)
        }
        .frame(maxWidth: .infinity)
    }

    private func limitField(_ binding: Binding<String>) -> some View {
        TextField("", text: binding)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .multilineTextAlignment(.center)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: Keypad

    private var keyHeight: CGFloat {
        let limitsShown = model.mode == .calculus && model.definite
        let items = (compact ? 0 : 1) + 1 + (limitsShown ? 1 : 0) + 1
        let used = (compact ? 0 : 30) + displayHeight + (limitsShown ? 24 : 0) + 8 * CGFloat(items - 1)
        return max(18, (size.height - used - spacing * CGFloat(rows - 1)) / CGFloat(rows))
    }

    private var keypad: some View {
        HStack(alignment: .top, spacing: 10) {
            grid(panel, columns: 4)
                .frame(maxWidth: .infinity)
            grid(pad, columns: 4)
                .frame(maxWidth: .infinity)
        }
    }

    private func grid(_ keys: [CalculatorKey?], columns: Int) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < keys.count, let key = keys[index] {
                            keyButton(key)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(height: keyHeight)
            }
        }
    }

    private func keyButton(_ key: CalculatorKey) -> some View {
        let selected: Bool = {
            if case .definite = key.action { return model.definite }
            if case .fraction = key.action { return model.showsFraction }
            return false
        }()
        return Button { press(key.action) } label: {
            Text(key.label)
                .font(.system(size: key.kind == .digit ? 15 : 12, weight: key.kind == .digit ? .medium : .regular,
                              design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(CalculatorKeyStyle(kind: key.kind, selected: selected, reduceMotion: reduceMotion))
        .accessibilityLabel(key.label)
    }

    private func press(_ action: CalculatorKeyAction) {
        switch action {
        case .insert(let value): model.insert(value)
        case .clear: model.clear()
        case .backspace: model.backspace()
        case .equals: model.equals()
        case .fraction: model.showsFraction.toggle()
        case .derivative: model.differentiate()
        case .integral: model.integrate()
        case .definite: model.definite.toggle()
        }
    }

    /// The numbers and the four operations, the same in every mode.
    private var pad: [CalculatorKey?] {
        [
            CalculatorKey(label: "AC", action: .clear, kind: .utility),
            CalculatorKey(label: "⌫", action: .backspace, kind: .utility),
            .insert("(", kind: .utility), .insert(")", kind: .utility),
            .insert("7", kind: .digit), .insert("8", kind: .digit), .insert("9", kind: .digit), .insert("÷", kind: .op),
            .insert("4", kind: .digit), .insert("5", kind: .digit), .insert("6", kind: .digit), .insert("×", kind: .op),
            .insert("1", kind: .digit), .insert("2", kind: .digit), .insert("3", kind: .digit), .insert("−", kind: .op),
            .insert("0", kind: .digit), .insert(".", kind: .digit), .insert("+", kind: .op),
            CalculatorKey(label: "=", action: .equals, kind: .equals),
        ]
    }

    /// The keys that change with the mode, four to a row.
    private var panel: [CalculatorKey?] {
        switch model.mode {
        case .basic:
            return [
                .insert("x²", "²"), .insert("√", "√("), .insert("xʸ", "^"), .insert("1/x", "⁻¹"),
                CalculatorKey(label: "a⁄b", action: .fraction), .insert("ans"), .insert("π"), .insert("e"),
                .insert("n!", "!"), .insert("|x|", "abs("), .insert("ln", "ln("), .insert("log", "log("),
            ]
        case .trigonometry:
            return [
                .insert("sin", "sin("), .insert("cos", "cos("), .insert("tan", "tan("), .insert("π"),
                .insert("csc", "csc("), .insert("sec", "sec("), .insert("cot", "cot("), .insert("°"),
                .insert("sin⁻¹", "asin("), .insert("cos⁻¹", "acos("), .insert("tan⁻¹", "atan("),
                CalculatorKey(label: "a⁄b", action: .fraction),
                .insert("csc⁻¹", "acsc("), .insert("sec⁻¹", "asec("), .insert("cot⁻¹", "acot("), .insert("ans"),
            ]
        case .calculus:
            return [
                .insert("x"), .insert("i"), .insert("xʸ", "^"), .insert("n!", "!"),
                CalculatorKey(label: "d/dx", action: .derivative, kind: .op),
                CalculatorKey(label: "∫dx", action: .integral, kind: .op),
                CalculatorKey(label: "∫ₐᵇ", action: .definite, kind: .op),
                .insert("√", "√("),
                .insert("conj", "conj("), .insert("abs", "abs("), .insert("arg", "arg("), .insert("π"),
                .insert("re", "re("), .insert("im", "im("), .insert("ln", "ln("), .insert("exp", "exp("),
                .insert("e"), .insert("sin", "sin("), .insert("cos", "cos("), .insert("tan", "tan("),
            ]
        }
    }
}

private struct CalculatorKeyStyle: ButtonStyle {
    let kind: CalculatorKey.Kind
    let selected: Bool
    let reduceMotion: Bool

    private var fill: Color {
        switch kind {
        case .digit: return .white.opacity(0.12)
        case .op: return .orange.opacity(selected ? 1 : 0.78)
        case .equals: return .orange
        case .function: return .white.opacity(selected ? 0.26 : 0.07)
        case .utility: return .white.opacity(0.18)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(kind == .equals ? .black : .white)
            .background(fill.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
