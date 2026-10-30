import Foundation

/// The calculator's engine against answers worked out by hand.
enum CalculatorEngineTests {
    static func run(_ suite: TestSuite) {
        func value(_ text: String, _ angle: CalculatorAngle = .degrees) -> String {
            do { return CalculatorEngine.format(try CalculatorEngine.evaluate(text, angle: angle)) }
            catch let error as CalculatorError { return "error: \(error.message)" }
            catch { return "error" }
        }
        func check(_ text: String, _ expected: String, _ angle: CalculatorAngle = .degrees) {
            suite.expect(value(text, angle) == expected, "calculator: \(text) = \(expected), got \(value(text, angle))")
        }

        // Basics, order of operations and implicit multiplication.
        check("2+3*4", "14")
        check("(2+3)*4", "20")
        check("10/4", "2.5")
        check("2^10", "1024")
        check("-2^2", "-4")
        check("2^-1", "0.5")
        check("2(3+4)", "14")
        check("3pi", CalculatorEngine.formatNumber(3 * Double.pi))
        check("sqrt(144)", "12")
        check("√9", "3")
        check("cbrt(27)", "3")
        check("1/0", "error: Cannot divide by zero")
        check("2+", "error: Expression ended early")
        check("(2+3", "error: Missing )")

        // Factorial.
        check("5!", "120")
        check("0!", "1")
        check("20!", "2432902008176640000")
        check("(-1)!", "error: Factorial of a negative integer is undefined")
        check("171!", "error: Too large")
        check("fact(4)", "24")
        suite.expect(abs(((try? CalculatorEngine.evaluate("0.5!").re) ?? 0) - 0.886226925452758) < 1e-9, "calculator: 0.5! is half the root of pi")

        // Trigonometry in degrees and in radians.
        check("sin(30)", "0.5")
        check("cos(60)", "0.5")
        check("sin(90)", "1")
        check("cos(90)", "0")
        check("sin(180)", "0")
        check("tan(45)", "1")
        check("tan(90)", "error: tan is undefined here")
        check("csc(30)", "2")
        check("sec(60)", "2")
        check("cot(45)", "1")
        check("sin(pi/2)", "1", .radians)
        check("asin(0.5)", "30")
        check("acos(0.5)", "60")
        check("atan(1)", "45")
        check("atan(1)", CalculatorEngine.formatNumber(Double.pi / 4), .radians)
        check("asin(2)", "error: asin needs a value from -1 to 1")
        check("sin(30°)", "0.5", .radians)
        check("sinh(0)", "0")
        check("ln(e)", "1")
        check("log(1000)", "3")

        // Complex numbers.
        check("i*i", "-1")
        check("(1+2i)*(3-i)", "5 + 5i")
        check("(1+i)/(1-i)", "i")
        check("sqrt(-4)", "2i")
        check("sqrt(-1)", "i")
        check("abs(3+4i)", "5")
        check("conj(2+3i)", "2 - 3i")
        check("re(2+3i)", "2")
        check("im(2+3i)", "3")
        check("(1+i)^2", "2i")
        check("e^(i*pi)", "-1", .radians)
        check("arg(i)", "90")
        check("arg(i)", CalculatorEngine.formatNumber(Double.pi / 2), .radians)
        suite.expect(CalculatorEngine.polar(Complex(0, 2), angle: .degrees) == "2 ∠ 90°", "calculator: polar form of 2i")

        // Raised powers read and evaluate like ^.
        check("4⁸", "65536")
        check("2⁻¹", "0.5")
        check("5²", "25")
        check("2³!", "64")
        check("(2³)!", "40320")
        check("(1+i)²", "2i")
        check("2x²", "error: x has no value here")
        suite.expect(CalculatorEngine.tidy("4^8") == "4⁸", "calculator: 4^8 is shown as 4⁸")
        suite.expect(CalculatorEngine.tidy("x^-2") == "x⁻²", "calculator: x^-2 is shown as x⁻²")
        suite.expect(CalculatorEngine.tidy("2^10+3^2") == "2¹⁰+3²", "calculator: every whole power in a sum is raised")
        suite.expect(CalculatorEngine.tidy("4⁸1") == "4⁸¹", "calculator: digits after a power carry it on")
        suite.expect(CalculatorEngine.tidy("2^2.5") == "2^2.5", "calculator: a decimal power stays as typed")
        suite.expect(CalculatorEngine.tidy("2².5") == "2^2.5", "calculator: a decimal point after a raised power turns it back")
        suite.expect(CalculatorEngine.tidy("e^x") == "e^x" && CalculatorEngine.tidy("2^(3)") == "2^(3)", "calculator: powers of a letter or bracket stay as typed")
        suite.expect(CalculatorEngine.tidy("3·x^2") == "3·x²", "calculator: a derivative reads 3·x²")

        // Fractions.
        suite.expect(CalculatorEngine.fraction(0.75) == "3/4", "calculator: 0.75 is 3/4")
        suite.expect(CalculatorEngine.fraction(1.0 / 3.0) == "1/3", "calculator: one third is 1/3")
        suite.expect(CalculatorEngine.fraction(-0.125) == "-1/8", "calculator: -0.125 is -1/8")
        suite.expect(CalculatorEngine.fraction(2) == nil, "calculator: a whole number is not shown as a fraction")
        suite.expect(CalculatorEngine.fraction(Double.pi) == nil, "calculator: pi has no simple fraction")

        // Differentiation.
        func derivative(_ text: String) -> String { (try? CalculatorCalculus.derivative(of: text)) ?? "error" }
        suite.expect(derivative("x^3") == "3·x^2", "calculator: d/dx x^3 is 3x², got \(derivative("x^3"))")
        suite.expect(derivative("5") == "0", "calculator: a constant has derivative 0")
        suite.expect(derivative("3x") == "3", "calculator: d/dx 3x is 3, got \(derivative("3x"))")
        suite.expect(derivative("sin(x)") == "cos(x)", "calculator: d/dx sin x is cos x, got \(derivative("sin(x)"))")
        suite.expect(derivative("cos(x)") == "-sin(x)", "calculator: d/dx cos x is -sin x, got \(derivative("cos(x)"))")
        suite.expect(derivative("e^x") == "e^x·ln(e)" || derivative("e^x") == "e^x", "calculator: d/dx e^x, got \(derivative("e^x"))")
        suite.expect(derivative("ln(x)") == "1/x", "calculator: d/dx ln x is 1/x, got \(derivative("ln(x)"))")
        // Numerically check harder ones against a difference quotient.
        for (text, point) in [("x^2*sin(x)", 1.3), ("sin(x)/x", 0.9), ("sqrt(x^2+1)", 2.0), ("x^x", 1.7), ("tan(2x)", 0.3),
                              ("atan(x)", 0.8), ("exp(3x)", 0.2), ("ln(x^2+1)", 1.1)] {
            guard let text = try? CalculatorCalculus.derivative(of: text),
                  let symbolic = try? CalculatorEngine.evaluate(text, angle: .radians, variables: ["x": Complex(point)]),
                  let original = try? CalculatorParser.parse(text) else {
                suite.expect(false, "calculator: derivative of \(text) can be evaluated"); continue
            }
            _ = original
            _ = symbolic
        }
        func slopeAt(_ expression: String, _ x: Double) -> Double? {
            guard let derived = try? CalculatorCalculus.derivative(of: expression),
                  let exact = try? CalculatorEngine.evaluate(derived, angle: .radians, variables: ["x": Complex(x)]),
                  let hi = try? CalculatorEngine.evaluate(expression, angle: .radians, variables: ["x": Complex(x + 1e-6)]),
                  let lo = try? CalculatorEngine.evaluate(expression, angle: .radians, variables: ["x": Complex(x - 1e-6)])
            else { return nil }
            return abs(exact.re - (hi.re - lo.re) / 2e-6) < 1e-5 * max(1, abs(exact.re)) ? exact.re : nil
        }
        for (text, point) in [("x^2*sin(x)", 1.3), ("sin(x)/x", 0.9), ("sqrt(x^2+1)", 2.0), ("x^x", 1.7), ("tan(2x)", 0.3),
                              ("atan(x)", 0.8), ("exp(3x)", 0.2), ("ln(x^2+1)", 1.1), ("(x+1)^3", 0.5), ("2^x", 1.4)] {
            suite.expect(slopeAt(text, point) != nil, "calculator: the derivative of \(text) matches its slope at \(point)")
        }

        // Integration.
        func antiderivative(_ text: String) -> String { (try? CalculatorCalculus.antiderivative(of: text)) ?? "none" }
        suite.expect(antiderivative("x^2") == "x^3/3 + C", "calculator: ∫x² is x³/3 + C, got \(antiderivative("x^2"))")
        suite.expect(antiderivative("1/x") == "ln(abs(x)) + C", "calculator: ∫1/x is ln|x| + C, got \(antiderivative("1/x"))")
        suite.expect(antiderivative("cos(x)") == "sin(x) + C", "calculator: ∫cos x is sin x + C, got \(antiderivative("cos(x)"))")
        suite.expect(antiderivative("sin(x)*cos(x)") == "none", "calculator: a product it cannot solve says so")
        // An antiderivative differentiates back to the original.
        for (text, point) in [("3x^2+2x+1", 1.2), ("sin(2x)", 0.7), ("exp(3x)", 0.4), ("1/(2x+1)", 0.5), ("sqrt(x)", 2.0),
                              ("(2x+3)^4", 0.3), ("sin(x)^2", 0.9), ("2^x", 1.1), ("cos(3x+1)", 0.2)] {
            guard let anti = try? CalculatorCalculus.antiderivative(of: text),
                  let withoutC = anti.components(separatedBy: " + C").first else {
                suite.expect(false, "calculator: ∫\(text) has an antiderivative"); continue
            }
            suite.expect(slopeAt(withoutC, point).map { abs($0 - ((try? CalculatorEngine.evaluate(text, angle: .radians,
                            variables: ["x": Complex(point)]).re) ?? .nan)) < 1e-4 } == true,
                         "calculator: the derivative of ∫\(text) is the original")
        }
        func definite(_ text: String, _ a: String, _ b: String) -> Double? {
            try? CalculatorCalculus.definiteIntegral(of: text, from: a, to: b)
        }
        suite.expect(abs((definite("sin(x)", "0", "pi") ?? 0) - 2) < 1e-8, "calculator: ∫₀^π sin x is 2")
        suite.expect(abs((definite("x^2", "0", "3") ?? 0) - 9) < 1e-8, "calculator: ∫₀³ x² is 9")
        suite.expect(abs((definite("1/x", "1", "e") ?? 0) - 1) < 1e-8, "calculator: ∫₁^e 1/x is 1")
        suite.expect(abs((definite("x", "3", "0") ?? 0) + 4.5) < 1e-8, "calculator: reversing the limits flips the sign")
        suite.expect(abs((definite("exp(-x^2)", "-5", "5") ?? 0) - Foundation.sqrt(Double.pi)) < 1e-6, "calculator: the Gaussian integral is √π")
        suite.expect(definite("1/x", "0", "1") == nil, "calculator: ∫₀¹ 1/x does not converge and says so")
    }
}
