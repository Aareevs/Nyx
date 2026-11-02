import Foundation

/// A color as the picker's two controls hold it: the hue slider and the
/// saturation/brightness square, each 0...1.
struct ColorPickerColor: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double
}

/// WCAG grade of a contrast ratio between text and its background.
enum ColorContrastGrade: Equatable {
    case aaa, aa, aaLarge, low

    init(ratio: Double) {
        if ratio >= 7 { self = .aaa }
        else if ratio >= 4.5 { self = .aa }
        else if ratio >= 3 { self = .aaLarge }
        else { self = .low }
    }

    var label: String {
        switch self {
        case .aaa: return "AAA"
        case .aa: return "AA"
        case .aaLarge: return "LARGE"
        case .low: return "LOW"
        }
    }
}

/// The pure color maths behind the color picker panel.
enum ColorPickerMath {
    static let defaultHex = "#FF6B4A"
    static let recentLimit = 10

    static func rgb(from color: ColorPickerColor) -> (red: Double, green: Double, blue: Double) {
        let h = min(max(color.hue, 0), 1) * 6
        let s = min(max(color.saturation, 0), 1)
        let v = min(max(color.brightness, 0), 1)
        let sector = Int(h) % 6
        let f = h - Double(Int(h))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch sector {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    static func color(red: Double, green: Double, blue: Double) -> ColorPickerColor {
        let r = min(max(red, 0), 1), g = min(max(green, 0), 1), b = min(max(blue, 0), 1)
        let high = max(r, g, b), low = min(r, g, b)
        let delta = high - low
        var hue = 0.0
        if delta > 0.000001 {
            if high == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if high == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return ColorPickerColor(hue: hue, saturation: high <= 0 ? 0 : delta / high, brightness: high)
    }

    /// "#RRGGBB", or "RRGGBB" when `bare`.
    static func hex(red: Double, green: Double, blue: Double, bare: Bool = false) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: bare ? "%02X%02X%02X" : "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Reads "#RGB", "#RRGGBB" and the same without the hash.
    static func rgb(fromHex text: String) -> (red: Double, green: Double, blue: Double)? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = digits.flatMap { [$0, $0] }.map(String.init).joined() }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// "rgb(255, 107, 74)".
    static func rgbString(red: Double, green: Double, blue: Double) -> String {
        ColorValue.string(red: red, green: green, blue: blue, format: .rgb)
    }

    /// "hsl(11, 100%, 65%)".
    static func hslString(red: Double, green: Double, blue: Double) -> String {
        ColorValue.string(red: red, green: green, blue: blue, format: .hsl)
    }

    // MARK: Contrast

    static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ value: Double) -> Double {
            let c = min(max(value, 0), 1)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    static func contrastRatio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Contrast of the color against white and against black, the two
    /// backgrounds the picker shows it on.
    static func contrast(red: Double, green: Double, blue: Double) -> (onWhite: Double, onBlack: Double) {
        let l = relativeLuminance(red: red, green: green, blue: blue)
        return (contrastRatio(l, 1), contrastRatio(l, 0))
    }

    // MARK: Recent colors

    /// The color moved to the front, once, keeping the newest few.
    static func addingRecent(_ hex: String, to recents: [String], limit: Int = recentLimit) -> [String] {
        let key = hex.uppercased()
        return Array(([key] + recents.filter { $0.uppercased() != key }).prefix(limit))
    }
}
