import Foundation

struct NotchCalculatorStrings {
    let title: String
    let description: String
    let basic: String
    let trigonometry: String
    let calculus: String
    let degrees: String
    let radians: String
    let degreesHelp: String
    let radiansHelp: String
    let copy: String
    let placeholder: String
    let useResult: String
    let derivativeOf: String
    let integralOf: String
    let definiteIntegral: String
    let from: String
    let to: String
    let calculusAnglesNote: String
    let fraction: String
    let calculusHint: String
}

extension FeatureStrings {
    static func notchCalculator(_ language: AppLanguage) -> NotchCalculatorStrings {
        switch language {
        case .enUS: return NotchCalculatorStrings(
            title: "Calculator",
            description: "A calculator in the Dynamic Island: everyday arithmetic, trigonometry, and calculus with derivatives, integrals, complex numbers and factorials.",
            basic: "Basic",
            trigonometry: "Trigonometry",
            calculus: "Calculus",
            degrees: "DEG",
            radians: "RAD",
            degreesHelp: "Angles are in degrees. Click for radians.",
            radiansHelp: "Angles are in radians. Click for degrees.",
            copy: "Copy result",
            placeholder: "Type or tap an expression",
            useResult: "Use this result",
            derivativeOf: "d/dx of %@",
            integralOf: "∫ %@ dx",
            definiteIntegral: "Definite integral",
            from: "from",
            to: "to",
            calculusAnglesNote: "Calculus uses radians.",
            fraction: "Show as a fraction",
            calculusHint: "Write in x, like x³ + sin(x)")
        }
    }
}
