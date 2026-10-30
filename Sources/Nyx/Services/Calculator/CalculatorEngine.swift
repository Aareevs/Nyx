import Foundation

/// What went wrong with an expression, in words the calculator can show.
struct CalculatorError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

enum CalculatorAngle: String { case degrees, radians }

// MARK: - Complex numbers

struct Complex: Equatable {
    var re: Double
    var im: Double

    init(_ re: Double, _ im: Double = 0) {
        self.re = re
        self.im = im
    }

    static let i = Complex(0, 1)

    var isReal: Bool { abs(im) <= 1e-12 * max(1, abs(re)) }
    var magnitude: Double { hypot(re, im) }
    var argument: Double { atan2(im, re) }

    static func + (a: Complex, b: Complex) -> Complex { Complex(a.re + b.re, a.im + b.im) }
    static func - (a: Complex, b: Complex) -> Complex { Complex(a.re - b.re, a.im - b.im) }
    static prefix func - (a: Complex) -> Complex { Complex(-a.re, a.im == 0 ? 0 : -a.im) }
    static func * (a: Complex, b: Complex) -> Complex {
        Complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re)
    }
    static func / (a: Complex, b: Complex) throws -> Complex {
        let d = b.re * b.re + b.im * b.im
        guard d != 0 else { throw CalculatorError("Cannot divide by zero") }
        return Complex((a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d)
    }

    var conjugate: Complex { Complex(re, -im) }

    func exp() -> Complex {
        let scale = Foundation.exp(re)
        return Complex(scale * cos(im), scale * sin(im))
    }

    func ln() throws -> Complex {
        guard magnitude > 0 else { throw CalculatorError("ln of zero is undefined") }
        return Complex(Foundation.log(magnitude), argument)
    }

    func sqrt() -> Complex {
        if isReal && re >= 0 { return Complex(Foundation.sqrt(re)) }
        let root = Foundation.sqrt(magnitude)
        let half = argument / 2
        return Complex(root * cos(half), root * sin(half))
    }

    func power(_ exponent: Complex) throws -> Complex {
        if isReal, exponent.isReal {
            if re == 0 && exponent.re <= 0 { throw CalculatorError(exponent.re == 0 ? "0^0 is undefined" : "Cannot divide by zero") }
            if re >= 0 || exponent.re == exponent.re.rounded() { return Complex(Foundation.pow(re, exponent.re)) }
        }
        if magnitude == 0 { return Complex(0) }
        let logarithm = try ln()
        return (exponent * logarithm).exp()
    }

    func sine() -> Complex { Complex(sin(re) * cosh(im), cos(re) * sinh(im)) }
    func cosine() -> Complex { Complex(cos(re) * cosh(im), -sin(re) * sinh(im)) }
}

// MARK: - Syntax tree

indirect enum CalcNode: Equatable {
    case number(Double)
    case imaginary
    case variable(String)
    case negate(CalcNode)
    case binary(Character, CalcNode, CalcNode)
    case call(String, [CalcNode])
    case factorial(CalcNode)

    func contains(_ name: String) -> Bool {
        switch self {
        case .number, .imaginary: return false
        case .variable(let n): return n == name
        case .negate(let a), .factorial(let a): return a.contains(name)
        case .binary(_, let a, let b): return a.contains(name) || b.contains(name)
        case .call(_, let args): return args.contains { $0.contains(name) }
        }
    }
}

// MARK: - Parser

struct CalculatorParser {
    private enum Token: Equatable {
        case number(Double)
        case name(String)
        case symbol(Character)
    }

    private var tokens: [Token] = []
    private var position = 0

    static let functions: Set<String> = [
        "sin", "cos", "tan", "csc", "sec", "cot", "asin", "acos", "atan", "acsc", "asec", "acot",
        "sinh", "cosh", "tanh", "ln", "log", "exp", "sqrt", "cbrt", "abs", "conj", "re", "im", "arg", "fact",
    ]

    static func parse(_ text: String) throws -> CalcNode {
        var parser = CalculatorParser()
        try parser.tokenize(text)
        guard !parser.tokens.isEmpty else { throw CalculatorError("Type an expression") }
        let node = try parser.expression()
        guard parser.position == parser.tokens.count else { throw CalculatorError("Unexpected input") }
        return node
    }

    private mutating func tokenize(_ raw: String) throws {
        let text = raw
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "·", with: "*")
            .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "π", with: "pi")
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let c = chars[index]
            if c == " " { index += 1; continue }
            if CalculatorEngine.superscriptValues[c] != nil {
                // x² reads as x^2, and 2⁻¹ as 2^-1.
                var end = index
                var written = ""
                while end < chars.count, let plain = CalculatorEngine.superscriptValues[chars[end]] {
                    written.append(plain)
                    end += 1
                }
                tokens.append(.symbol("^"))
                if written.hasPrefix("-") {
                    tokens.append(.symbol("-"))
                    written.removeFirst()
                }
                guard let value = Double(written) else { throw CalculatorError("Bad exponent") }
                tokens.append(.number(value))
                index = end
            } else if c.isNumber || c == "." {
                var end = index
                var dots = 0
                while end < chars.count, (chars[end].isNumber && CalculatorEngine.superscriptValues[chars[end]] == nil) || chars[end] == "." {
                    if chars[end] == "." { dots += 1 }
                    end += 1
                }
                guard dots <= 1, let value = Double(String(chars[index..<end])) else { throw CalculatorError("Bad number") }
                tokens.append(.number(value))
                index = end
            } else if c.isLetter {
                var end = index
                while end < chars.count, chars[end].isLetter { end += 1 }
                tokens.append(.name(String(chars[index..<end]).lowercased()))
                index = end
            } else if "+-*/^()!,°√".contains(c) {
                tokens.append(.symbol(c))
                index += 1
            } else {
                throw CalculatorError("Unknown symbol \(c)")
            }
        }
    }

    private var peek: Token? { position < tokens.count ? tokens[position] : nil }

    private mutating func expression() throws -> CalcNode {
        var left = try term()
        while case .symbol(let op)? = peek, op == "+" || op == "-" {
            position += 1
            left = .binary(op, left, try term())
        }
        return left
    }

    private func startsOperand(_ token: Token?) -> Bool {
        switch token {
        case .number?, .name?: return true
        case .symbol(let c)?: return c == "(" || c == "√"
        case nil: return false
        }
    }

    private mutating func term() throws -> CalcNode {
        var left = try unary()
        while true {
            if case .symbol(let op)? = peek, op == "*" || op == "/" {
                position += 1
                left = .binary(op, left, try unary())
            } else if startsOperand(peek) {
                // Writing two things together multiplies them: 2x, 3(4+1), 2pi.
                left = .binary("*", left, try unary())
            } else {
                return left
            }
        }
    }

    private mutating func unary() throws -> CalcNode {
        if case .symbol(let c)? = peek, c == "-" || c == "+" {
            position += 1
            let inner = try unary()
            return c == "-" ? .negate(inner) : inner
        }
        return try power()
    }

    private mutating func power() throws -> CalcNode {
        let base = try postfix()
        if case .symbol("^")? = peek {
            position += 1
            return .binary("^", base, try unary())
        }
        return base
    }

    private mutating func postfix() throws -> CalcNode {
        var node = try primary()
        while true {
            if case .symbol("!")? = peek {
                position += 1
                node = .factorial(node)
            } else if case .symbol("°")? = peek {
                position += 1
                node = .binary("*", node, .binary("/", .number(Double.pi), .number(180)))
            } else {
                return node
            }
        }
    }

    private mutating func primary() throws -> CalcNode {
        guard let token = peek else { throw CalculatorError("Expression ended early") }
        position += 1
        switch token {
        case .number(let value):
            return .number(value)
        case .symbol("("):
            let inner = try expression()
            guard case .symbol(")")? = peek else { throw CalculatorError("Missing )") }
            position += 1
            return inner
        case .symbol("√"):
            return .call("sqrt", [try power()])
        case .name(let name):
            if Self.functions.contains(name) {
                guard case .symbol("(")? = peek else { throw CalculatorError("\(name) needs brackets, like \(name)(x)") }
                position += 1
                var args = [try expression()]
                while case .symbol(",")? = peek {
                    position += 1
                    args.append(try expression())
                }
                guard case .symbol(")")? = peek else { throw CalculatorError("Missing )") }
                position += 1
                return .call(name, args)
            }
            switch name {
            case "pi": return .number(Double.pi)
            case "e": return .number(M_E)
            case "i": return .imaginary
            case "x", "t", "ans": return .variable(name)
            default: throw CalculatorError("Unknown name \(name)")
            }
        default:
            throw CalculatorError("Unexpected \(token)")
        }
    }
}

// MARK: - Evaluation

enum CalculatorEngine {
    // MARK: Superscripts

    static let superscriptValues: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-",
    ]

    private static func superscript(_ plain: String) -> String {
        let table = Dictionary(uniqueKeysWithValues: superscriptValues.map { ($0.value, $0.key) })
        return String(plain.compactMap { table[$0] })
    }

    private static func plain(_ superscripts: String) -> String {
        String(superscripts.compactMap { superscriptValues[$0] })
    }

    /// Shows a whole-number power as a raised number, 4^8 as 4⁸, and keeps one
    /// with a decimal point as it is: x^2.5. Digits typed straight after a
    /// raised number carry on the power, 4⁸ then 1 reads 4⁸¹.
    static func tidy(_ text: String) -> String {
        var result = text
        func replace(_ pattern: String, _ make: (NSTextCheckingResult, NSString) -> String) {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            var output = ""
            var last = 0
            let source = result as NSString
            for match in expression.matches(in: result, range: NSRange(location: 0, length: source.length)) {
                output += source.substring(with: NSRange(location: last, length: match.range.location - last))
                output += make(match, source)
                last = match.range.location + match.range.length
            }
            output += source.substring(from: last)
            result = output
        }
        // A raised number followed by a decimal point was meant as a decimal power.
        replace("([⁰¹²³⁴⁵⁶⁷⁸⁹⁻]+)\\.(?=[0-9])") { match, source in
            "^" + plain(source.substring(with: match.range(at: 1))) + "."
        }
        replace("([⁰¹²³⁴⁵⁶⁷⁸⁹⁻]+)([0-9]+)") { match, source in
            source.substring(with: match.range(at: 1)) + superscript(source.substring(with: match.range(at: 2)))
        }
        replace("\\^(-?[0-9]+)(?![0-9.])") { match, source in
            superscript(source.substring(with: match.range(at: 1)))
        }
        return result
    }

    /// Rounds away the dust left by floating point, so sin(30°) reads 0.5.
    static func snap(_ value: Double) -> Double {
        let half = (value * 2).rounded() / 2
        return abs(value - half) < 1e-13 * max(1, abs(value)) ? half : value
    }

    static func evaluate(_ text: String, angle: CalculatorAngle = .degrees,
                         variables: [String: Complex] = [:]) throws -> Complex {
        try evaluate(try CalculatorParser.parse(text), angle: angle, variables: variables)
    }

    static func evaluate(_ node: CalcNode, angle: CalculatorAngle, variables: [String: Complex]) throws -> Complex {
        func value(_ n: CalcNode) throws -> Complex { try evaluate(n, angle: angle, variables: variables) }
        switch node {
        case .number(let v): return Complex(v)
        case .imaginary: return .i
        case .variable(let name):
            guard let v = variables[name] else { throw CalculatorError("\(name) has no value here") }
            return v
        case .negate(let a):
            let inner = try value(a)
            return -inner
        case .binary(let op, let a, let b):
            let l = try value(a), r = try value(b)
            switch op {
            case "+": return l + r
            case "-": return l - r
            case "*": return l * r
            case "/": return try l / r
            default: return try l.power(r)
            }
        case .factorial(let a):
            let v = try value(a)
            guard v.isReal else { throw CalculatorError("Factorial needs a real number") }
            return Complex(try factorial(v.re))
        case .call(let name, let args):
            return try call(name, try args.map(value), angle: angle)
        }
    }

    static func factorial(_ x: Double) throws -> Double {
        guard x >= 0 || x != x.rounded() else { throw CalculatorError("Factorial of a negative integer is undefined") }
        if x == x.rounded() {
            guard x <= 170 else { throw CalculatorError("Too large") }
            var result = 1.0
            if x >= 2 { for k in 2...Int(x) { result *= Double(k) } }
            return result
        }
        guard x > -170 else { throw CalculatorError("Too large") }
        return tgamma(x + 1)
    }

    private static func call(_ name: String, _ args: [Complex], angle: CalculatorAngle) throws -> Complex {
        guard let first = args.first else { throw CalculatorError("\(name) needs a value") }
        let toRadians = angle == .degrees ? Double.pi / 180 : 1
        func real() throws -> Double {
            guard first.isReal else { throw CalculatorError("\(name) needs a real number") }
            return first.re
        }
        func sinCos() -> (Complex, Complex) {
            let scaled = Complex(first.re * toRadians, first.im * toRadians)
            let s = scaled.sine(), c = scaled.cosine()
            return (Complex(snap(s.re), snap(s.im)), Complex(snap(c.re), snap(c.im)))
        }
        func fromRadians(_ v: Double) -> Complex { Complex(snap(v / toRadians)) }
        func reciprocal(_ v: Complex) throws -> Complex {
            guard v.magnitude > 1e-12 else { throw CalculatorError("Undefined here") }
            return try Complex(1) / v
        }
        switch name {
        case "sin": return sinCos().0
        case "cos": return sinCos().1
        case "tan":
            let (s, c) = sinCos()
            guard c.magnitude > 1e-12 else { throw CalculatorError("tan is undefined here") }
            return try s / c
        case "csc": return try reciprocal(sinCos().0)
        case "sec": return try reciprocal(sinCos().1)
        case "cot":
            let (s, c) = sinCos()
            guard s.magnitude > 1e-12 else { throw CalculatorError("cot is undefined here") }
            return try c / s
        case "asin":
            let v = try real()
            guard abs(v) <= 1 else { throw CalculatorError("asin needs a value from -1 to 1") }
            return fromRadians(asin(v))
        case "acos":
            let v = try real()
            guard abs(v) <= 1 else { throw CalculatorError("acos needs a value from -1 to 1") }
            return fromRadians(acos(v))
        case "atan": return fromRadians(atan(try real()))
        case "acsc":
            let v = try real()
            guard abs(v) >= 1 else { throw CalculatorError("acsc needs a value of at least 1 or at most -1") }
            return fromRadians(asin(1 / v))
        case "asec":
            let v = try real()
            guard abs(v) >= 1 else { throw CalculatorError("asec needs a value of at least 1 or at most -1") }
            return fromRadians(acos(1 / v))
        case "acot":
            let v = try real()
            guard v != 0 else { return fromRadians(Double.pi / 2) }
            return fromRadians(atan(1 / v))
        case "sinh": return Complex(sinh(first.re) * cos(first.im), cosh(first.re) * sin(first.im))
        case "cosh": return Complex(cosh(first.re) * cos(first.im), sinh(first.re) * sin(first.im))
        case "tanh":
            let a = Complex(sinh(first.re) * cos(first.im), cosh(first.re) * sin(first.im))
            let b = Complex(cosh(first.re) * cos(first.im), sinh(first.re) * sin(first.im))
            return try a / b
        case "ln": return try first.ln()
        case "log":
            let v = try first.ln()
            return try v / Complex(Foundation.log(10.0))
        case "exp": return first.exp()
        case "sqrt": return first.sqrt()
        case "cbrt":
            if first.isReal { return Complex(cbrt(first.re)) }
            return try first.power(Complex(1.0 / 3.0))
        case "abs": return Complex(first.magnitude)
        case "conj": return first.conjugate
        case "re": return Complex(first.re)
        case "im": return Complex(first.im)
        case "arg": return Complex(first.argument / toRadians)
        case "fact":
            return Complex(try factorial(try real()))
        default: throw CalculatorError("Unknown function \(name)")
        }
    }

    // MARK: Formatting

    static func formatNumber(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "Undefined" : (value < 0 ? "-∞" : "∞") }
        var v = snap(value)
        if abs(v) < 1e-12 { v = 0 }
        if v == 0 { return "0" }
        // A calculator always writes a dot, whatever the Mac's region.
        let posix = Locale(identifier: "en_US_POSIX")
        if v == v.rounded(), abs(v) < 1e19 { return String(format: "%.0f", locale: posix, v) }
        var text = String(format: "%.12g", locale: posix, v)
        if text.contains("e") {
            // 1.5e+20 reads better as 1.5×10²⁰.
            let parts = text.split(separator: "e")
            if parts.count == 2, let exponent = Int(parts[1]) {
                text = "\(parts[0])×10^\(exponent)"
            }
        }
        return text
    }

    static func format(_ c: Complex) -> String {
        if c.isReal { return formatNumber(c.re) }
        let re = abs(c.re) < 1e-12 ? 0 : c.re
        let imagMagnitude = abs(c.im)
        let imagText = abs(imagMagnitude - 1) < 1e-12 ? "i" : formatNumber(imagMagnitude) + "i"
        if re == 0 { return (c.im < 0 ? "-" : "") + imagText }
        return formatNumber(re) + (c.im < 0 ? " - " : " + ") + imagText
    }

    /// r∠θ for a complex number.
    static func polar(_ c: Complex, angle: CalculatorAngle) -> String {
        let theta = angle == .degrees ? c.argument * 180 / Double.pi : c.argument
        return "\(formatNumber(c.magnitude)) ∠ \(formatNumber(theta))\(angle == .degrees ? "°" : " rad")"
    }

    /// The nearest simple fraction, like 0.75 as 3/4, when there is one.
    static func fraction(_ value: Double) -> String? {
        guard value.isFinite, value != value.rounded(), abs(value) < 1e9 else { return nil }
        let sign = value < 0 ? "-" : ""
        var x = abs(value)
        var (h1, h0) = (1.0, 0.0), (k1, k0) = (0.0, 1.0)
        for _ in 0..<24 {
            let a = x.rounded(.down)
            (h1, h0) = (a * h1 + h0, h1)
            (k1, k0) = (a * k1 + k0, k1)
            if abs(abs(value) - h1 / k1) < 1e-10 * max(1, abs(value)) { break }
            let rest = x - a
            guard rest > 1e-12 else { break }
            x = 1 / rest
        }
        guard k1 <= 10_000, abs(abs(value) - h1 / k1) < 1e-9 * max(1, abs(value)) else { return nil }
        return "\(sign)\(Int(h1))/\(Int(k1))"
    }
}

// MARK: - Calculus

enum CalculatorCalculus {
    // MARK: Printing

    private static func precedence(_ node: CalcNode) -> Int {
        switch node {
        case .binary(let op, _, _):
            switch op { case "+", "-": return 1; case "*", "/": return 2; default: return 4 }
        case .negate: return 3
        case .number(let v) where v < 0: return 3
        default: return 5
        }
    }

    static func print(_ node: CalcNode) -> String {
        func wrapped(_ n: CalcNode, atLeast level: Int) -> String {
            let s = print(n)
            return precedence(n) < level ? "(\(s))" : s
        }
        switch node {
        case .number(let v):
            if abs(v - Double.pi) < 1e-15 { return "π" }
            if abs(v - M_E) < 1e-15 { return "e" }
            return CalculatorEngine.formatNumber(v)
        case .imaginary: return "i"
        case .variable(let n): return n
        case .negate(let a): return "-" + wrapped(a, atLeast: 3)
        case .factorial(let a): return wrapped(a, atLeast: 5) + "!"
        case .call(let name, let args): return name + "(" + args.map(print).joined(separator: ", ") + ")"
        case .binary(let op, let a, let b):
            switch op {
            case "+": return wrapped(a, atLeast: 1) + " + " + wrapped(b, atLeast: 1)
            case "-": return wrapped(a, atLeast: 1) + " - " + wrapped(b, atLeast: 2)
            case "*": return wrapped(a, atLeast: 2) + "·" + wrapped(b, atLeast: 3)
            case "/": return wrapped(a, atLeast: 2) + "/" + wrapped(b, atLeast: 3)
            default:  return wrapped(a, atLeast: 5) + "^" + wrapped(b, atLeast: 5)
            }
        }
    }

    // MARK: Simplifying

    static func simplify(_ node: CalcNode) -> CalcNode {
        switch node {
        case .negate(let a):
            let s = simplify(a)
            if case .number(let v) = s { return .number(-v) }
            if case .negate(let inner) = s { return inner }
            return .negate(s)
        case .binary(let op, let a, let b):
            let l = simplify(a), r = simplify(b)
            if case .number(let x) = l, case .number(let y) = r {
                switch op {
                case "+": return .number(x + y)
                case "-": return .number(x - y)
                case "*": return .number(x * y)
                case "/": if y != 0 { return .number(x / y) }
                default: if x >= 0 || y == y.rounded() { let p = Foundation.pow(x, y); if p.isFinite { return .number(p) } }
                }
            }
            func isNumber(_ n: CalcNode, _ v: Double) -> Bool { if case .number(let x) = n { return x == v }; return false }
            switch op {
            case "+":
                if isNumber(l, 0) { return r }
                if isNumber(r, 0) { return l }
            case "-":
                if isNumber(r, 0) { return l }
                if isNumber(l, 0) { return simplify(.negate(r)) }
            case "*":
                if isNumber(l, 0) || isNumber(r, 0) { return .number(0) }
                if isNumber(l, 1) { return r }
                if isNumber(r, 1) { return l }
                if isNumber(l, -1) { return simplify(.negate(r)) }
                if isNumber(r, -1) { return simplify(.negate(l)) }
                // Keep numbers in front: x·3 reads 3·x.
                if case .number = r {
                    if case .number = l {} else { return .binary("*", r, l) }
                }
            case "/":
                if isNumber(l, 0) { return .number(0) }
                if isNumber(r, 1) { return l }
            default:
                if isNumber(r, 0) { return .number(1) }
                if isNumber(r, 1) { return l }
            }
            return .binary(op, l, r)
        case .call(let name, let args):
            let simplified = args.map(simplify)
            if simplified.count == 1, case .number = simplified[0],
               let value = try? CalculatorEngine.evaluate(.call(name, simplified), angle: .radians, variables: [:]), value.isReal,
               ["sqrt", "abs", "ln", "exp", "cbrt"].contains(name) {
                let v = value.re
                // Only exact results fold: sqrt(4) is 2, but sqrt(2) stays.
                if v == v.rounded() { return .number(v) }
            }
            return .call(name, simplified)
        default:
            return node
        }
    }

    // MARK: Derivative

    static func derivative(_ node: CalcNode, _ v: String) throws -> CalcNode {
        if !node.contains(v) { return .number(0) }
        func d(_ n: CalcNode) throws -> CalcNode { try derivative(n, v) }
        func num(_ x: Double) -> CalcNode { .number(x) }
        switch node {
        case .number, .imaginary: return num(0)
        case .variable: return num(1)
        case .negate(let a): return .negate(try d(a))
        case .factorial: throw CalculatorError("Cannot differentiate a factorial")
        case .binary(let op, let a, let b):
            switch op {
            case "+", "-": return .binary(op, try d(a), try d(b))
            case "*": return .binary("+", .binary("*", try d(a), b), .binary("*", a, try d(b)))
            case "/":
                return .binary("/", .binary("-", .binary("*", try d(a), b), .binary("*", a, try d(b))), .binary("^", b, num(2)))
            default:
                if !b.contains(v) {
                    return .binary("*", .binary("*", b, .binary("^", a, .binary("-", b, num(1)))), try d(a))
                } else if !a.contains(v) {
                    return .binary("*", .binary("*", node, .call("ln", [a])), try d(b))
                }
                // f^g = f^g · (g′ ln f + g f′ / f)
                return .binary("*", node, .binary("+", .binary("*", try d(b), .call("ln", [a])),
                                                  .binary("/", .binary("*", b, try d(a)), a)))
            }
        case .call(let name, let args):
            guard let u = args.first, args.count == 1 else { throw CalculatorError("Cannot differentiate \(name)") }
            let outer: CalcNode
            func call(_ n: String) -> CalcNode { .call(n, [u]) }
            switch name {
            case "sin": outer = call("cos")
            case "cos": outer = .negate(call("sin"))
            case "tan": outer = .binary("^", call("sec"), num(2))
            case "csc": outer = .negate(.binary("*", call("csc"), call("cot")))
            case "sec": outer = .binary("*", call("sec"), call("tan"))
            case "cot": outer = .negate(.binary("^", call("csc"), num(2)))
            case "asin": outer = .binary("/", num(1), .call("sqrt", [.binary("-", num(1), .binary("^", u, num(2)))]))
            case "acos": outer = .negate(.binary("/", num(1), .call("sqrt", [.binary("-", num(1), .binary("^", u, num(2)))])))
            case "atan": outer = .binary("/", num(1), .binary("+", num(1), .binary("^", u, num(2))))
            case "sinh": outer = call("cosh")
            case "cosh": outer = call("sinh")
            case "tanh": outer = .binary("-", num(1), .binary("^", call("tanh"), num(2)))
            case "ln": outer = .binary("/", num(1), u)
            case "log": outer = .binary("/", num(1), .binary("*", u, num(Foundation.log(10.0))))
            case "exp": outer = call("exp")
            case "sqrt": outer = .binary("/", num(1), .binary("*", num(2), call("sqrt")))
            case "cbrt": outer = .binary("/", num(1), .binary("*", num(3), .binary("^", call("cbrt"), num(2))))
            case "abs": outer = .binary("/", u, call("abs"))
            default: throw CalculatorError("Cannot differentiate \(name)")
            }
            return .binary("*", outer, try d(u))
        }
    }

    static func derivative(of text: String, variable: String = "x") throws -> String {
        let node = try CalculatorParser.parse(text)
        guard node.contains(variable) else { return "0" }
        return print(simplify(try derivative(node, variable)))
    }

    // MARK: Integral

    /// The antiderivative when it is one of the standard forms, else nil.
    static func antiderivative(_ node: CalcNode, _ v: String) -> CalcNode? {
        func num(_ x: Double) -> CalcNode { .number(x) }
        let variable = CalcNode.variable(v)
        if !node.contains(v) { return .binary("*", node, variable) }
        // Constant slope a and offset in a·v + b, when the argument is a line.
        func slope(_ u: CalcNode) -> Double? {
            guard let d = try? derivative(u, v), case .number(let a) = simplify(d), a != 0 else { return nil }
            return a
        }
        switch node {
        case .variable: return .binary("/", .binary("^", variable, num(2)), num(2))
        case .negate(let a): return antiderivative(a, v).map { .negate($0) }
        case .binary(let op, let a, let b):
            switch op {
            case "+", "-":
                guard let l = antiderivative(a, v), let r = antiderivative(b, v) else { return nil }
                return .binary(op, l, r)
            case "*":
                if !a.contains(v) { return antiderivative(b, v).map { .binary("*", a, $0) } }
                if !b.contains(v) { return antiderivative(a, v).map { .binary("*", b, $0) } }
                return nil
            case "/":
                if !b.contains(v) { return antiderivative(a, v).map { .binary("/", $0, b) } }
                if !a.contains(v), let k = slope(b) {
                    return .binary("*", .binary("/", a, num(k)), .call("ln", [.call("abs", [b])]))
                }
                return nil
            default:
                guard !b.contains(v), case .number(let n) = simplify(b) else {
                    // a^(k·x + c) with a constant base
                    if !a.contains(v), let k = slope(b) {
                        return .binary("/", node, .binary("*", num(k), .call("ln", [a])))
                    }
                    return nil
                }
                if let k = slope(a) {
                    if n == -1 { return .binary("*", num(1 / k), .call("ln", [.call("abs", [a])])) }
                    return .binary("/", .binary("^", a, num(n + 1)), num(k * (n + 1)))
                }
                // sin(u)² and cos(u)² on a line.
                if n == 2, case .call(let f, let args) = a, args.count == 1, let k = slope(args[0]), f == "sin" || f == "cos" {
                    let u = args[0]
                    let half = CalcNode.binary("/", u, num(2 * k))
                    let wave = CalcNode.binary("/", .call("sin", [.binary("*", num(2), u)]), num(4 * k))
                    return f == "sin" ? .binary("-", half, wave) : .binary("+", half, wave)
                }
                return nil
            }
        case .call(let name, let args):
            guard args.count == 1, let k = slope(args[0]) else { return nil }
            let u = args[0]
            let base: CalcNode
            switch name {
            case "sin": base = .negate(.call("cos", [u]))
            case "cos": base = .call("sin", [u])
            case "tan": base = .negate(.call("ln", [.call("abs", [.call("cos", [u])])]))
            case "exp": base = .call("exp", [u])
            case "sinh": base = .call("cosh", [u])
            case "cosh": base = .call("sinh", [u])
            case "sqrt": base = .binary("*", num(2.0 / 3.0), .binary("^", u, num(1.5)))
            case "ln": base = .binary("-", .binary("*", u, .call("ln", [u])), u)
            default: return nil
            }
            return k == 1 ? base : .binary("/", base, num(k))
        default:
            return nil
        }
    }

    static func antiderivative(of text: String, variable: String = "x") throws -> String {
        let node = try CalculatorParser.parse(text)
        guard let result = antiderivative(node, variable) else {
            throw CalculatorError("No standard antiderivative. Try a definite integral.")
        }
        return print(simplify(result)) + " + C"
    }

    /// ∫ from a to b by adaptive Simpson, in radians.
    static func definiteIntegral(of text: String, from lower: String, to upper: String,
                                 variable: String = "x") throws -> Double {
        let node = try CalculatorParser.parse(text)
        let a = try CalculatorEngine.evaluate(lower, angle: .radians)
        let b = try CalculatorEngine.evaluate(upper, angle: .radians)
        guard a.isReal, b.isReal else { throw CalculatorError("Limits must be real") }
        var samples = 0
        func f(_ x: Double) throws -> Double {
            samples += 1
            guard samples < 200_000 else { throw CalculatorError("Too hard to integrate numerically") }
            let y = try CalculatorEngine.evaluate(node, angle: .radians, variables: [variable: Complex(x)])
            guard y.isReal, y.re.isFinite else { throw CalculatorError("Not a real number at x = \(CalculatorEngine.formatNumber(x))") }
            return y.re
        }
        func simpson(_ fa: Double, _ fm: Double, _ fb: Double, _ lo: Double, _ hi: Double) -> Double {
            (hi - lo) / 6 * (fa + 4 * fm + fb)
        }
        func refine(_ lo: Double, _ hi: Double, _ fa: Double, _ fm: Double, _ fb: Double, _ whole: Double,
                    _ tolerance: Double, _ depth: Int) throws -> Double {
            let mid = (lo + hi) / 2
            let flm = try f((lo + mid) / 2), fmh = try f((mid + hi) / 2)
            let left = simpson(fa, flm, fm, lo, mid), right = simpson(fm, fmh, fb, mid, hi)
            if depth <= 0 || abs(left + right - whole) <= 15 * tolerance {
                return left + right + (left + right - whole) / 15
            }
            return try refine(lo, mid, fa, flm, fm, left, tolerance / 2, depth - 1)
                + refine(mid, hi, fm, fmh, fb, right, tolerance / 2, depth - 1)
        }
        if a.re == b.re { return 0 }
        let lo = min(a.re, b.re), hi = max(a.re, b.re)
        let fa = try f(lo), fb = try f(hi), fm = try f((lo + hi) / 2)
        let value = try refine(lo, hi, fa, fm, fb, simpson(fa, fm, fb, lo, hi), 1e-10, 22)
        return a.re <= b.re ? value : -value
    }
}
