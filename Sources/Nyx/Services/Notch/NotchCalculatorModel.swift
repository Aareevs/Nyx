import AppKit
import Foundation

enum CalculatorMode: String, CaseIterable {
    case basic, trigonometry, calculus
}

/// What the calculator page shows. It lives apart from the page so an
/// expression survives the island closing and opening again.
@MainActor
final class NotchCalculatorModel: ObservableObject {
    static let shared = NotchCalculatorModel()

    @Published var expression = "" {
        didSet {
            // Powers show raised: 4^8 becomes 4⁸ as it is typed.
            let tidy = CalculatorEngine.tidy(expression)
            if tidy != expression { expression = tidy }
            if expression != oldValue { refresh() }
        }
    }
    @Published var mode: CalculatorMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.notchCalculatorMode)
            definite = definite && mode == .calculus
            refresh()
        }
    }
    @Published var angle: CalculatorAngle {
        didSet {
            UserDefaults.standard.set(angle.rawValue, forKey: DefaultsKey.notchCalculatorAngle)
            refresh()
        }
    }
    /// The line under the expression: its value, or a derivative or integral.
    @Published private(set) var result = ""
    /// A smaller line: the fraction, the polar form, or what was asked.
    @Published private(set) var secondary = ""
    @Published private(set) var error: String?
    /// The sum an answer came from, shown small above the expression.
    @Published private(set) var previous = ""
    @Published var showsFraction = false { didSet { refresh() } }
    @Published var definite = false
    @Published var lower = "0"
    @Published var upper = "1"

    private var answer = Complex(0)
    /// True when `result` is a value that can go back into the expression.
    private var resultIsExpression = false

    private init() {
        let defaults = UserDefaults.standard
        mode = CalculatorMode(rawValue: defaults.string(forKey: DefaultsKey.notchCalculatorMode) ?? "") ?? .basic
        angle = CalculatorAngle(rawValue: defaults.string(forKey: DefaultsKey.notchCalculatorAngle) ?? "") ?? .degrees
    }

    /// Calculus works in radians whatever the angle switch says.
    var effectiveAngle: CalculatorAngle { mode == .calculus ? .radians : angle }
    var hasResult: Bool { !result.isEmpty }

    // MARK: Keys

    func insert(_ text: String) {
        // A number typed right after an answer starts a new sum; an operator carries on from it.
        expression += text
    }

    func clear() {
        previous = ""
        expression = ""
        result = ""
        secondary = ""
        error = nil
    }

    func backspace() {
        guard !expression.isEmpty else { return }
        expression.removeLast()
        error = nil
    }

    func useResult() {
        guard hasResult, resultIsExpression else { return }
        expression = result
    }

    var resultText: String { result }

    func copyResult() {
        guard hasResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    // MARK: Working it out

    /// The expression with any bracket left open closed, so sin(30 reads as sin(30).
    private func closed(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let open = trimmed.filter { $0 == "(" }.count - trimmed.filter { $0 == ")" }.count
        return open > 0 ? trimmed + String(repeating: ")", count: open) : trimmed
    }

    private var variables: [String: Complex] { ["ans": answer] }

    /// A live answer while typing; an unfinished expression just shows none.
    private func refresh() {
        error = nil
        let trimmed = closed(expression)
        guard !trimmed.isEmpty else { result = ""; secondary = ""; return }
        guard let value = try? CalculatorEngine.evaluate(trimmed, angle: effectiveAngle, variables: variables) else {
            result = ""
            secondary = ""
            return
        }
        show(value)
    }

    private func show(_ value: Complex) {
        result = CalculatorEngine.format(value)
        resultIsExpression = true
        if !value.isReal {
            secondary = CalculatorEngine.polar(value, angle: effectiveAngle)
        } else if showsFraction, let fraction = CalculatorEngine.fraction(value.re) {
            secondary = "= " + fraction
        } else {
            secondary = ""
        }
    }

    func equals() {
        let trimmed = closed(expression)
        guard !trimmed.isEmpty else { return }
        error = nil
        if mode == .calculus, definite {
            integrateDefinite(trimmed)
            return
        }
        do {
            let value = try CalculatorEngine.evaluate(trimmed, angle: effectiveAngle, variables: variables)
            guard value.re.isFinite, value.im.isFinite else { throw CalculatorError("Result is too large") }
            answer = value
            show(value)
            // The answer becomes the expression, ready to carry on from.
            let text = result
            previous = trimmed + " ="
            expression = text
            result = text
        } catch let failure as CalculatorError {
            error = failure.message
        } catch {
            self.error = "Cannot work that out"
        }
    }

    func differentiate() {
        let trimmed = closed(expression)
        guard !trimmed.isEmpty else { return }
        error = nil
        do {
            result = CalculatorEngine.tidy(try CalculatorCalculus.derivative(of: trimmed))
            resultIsExpression = true
            secondary = String(format: FeatureStrings.notchCalculator(L10n.shared.language).derivativeOf, trimmed)
        } catch let failure as CalculatorError {
            error = failure.message
        } catch {
            self.error = "Cannot differentiate that"
        }
    }

    func integrate() {
        let trimmed = closed(expression)
        guard !trimmed.isEmpty else { return }
        error = nil
        do {
            result = CalculatorEngine.tidy(try CalculatorCalculus.antiderivative(of: trimmed))
            // "+ C" is not part of an expression that can be fed back.
            resultIsExpression = false
            secondary = String(format: FeatureStrings.notchCalculator(L10n.shared.language).integralOf, trimmed)
        } catch let failure as CalculatorError {
            error = failure.message
        } catch {
            self.error = "Cannot integrate that"
        }
    }

    private func integrateDefinite(_ text: String) {
        do {
            let value = try CalculatorCalculus.definiteIntegral(of: text, from: lower, to: upper)
            result = CalculatorEngine.formatNumber(value)
            resultIsExpression = true
            secondary = "∫ from \(lower) to \(upper)"
            if showsFraction, let fraction = CalculatorEngine.fraction(value) { secondary += "  = " + fraction }
        } catch let failure as CalculatorError {
            error = failure.message
        } catch {
            self.error = "Cannot integrate that"
        }
    }
}
