import Foundation

/// The color picker panel's maths: conversions, hex text, contrast grades and
/// the recent list.
enum ColorPickerMathTests {
    static func run(_ suite: TestSuite) {
        func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.001) -> Bool { abs(a - b) < tolerance }

        // The sample color from the design: #FF6B4A.
        let rgb = ColorPickerMath.rgb(fromHex: "#FF6B4A")
        suite.expect(rgb != nil && near(rgb!.red, 1) && near(rgb!.green, 107 / 255) && near(rgb!.blue, 74 / 255),
                     "color picker: hex reads into channels")
        suite.expect(ColorPickerMath.rgb(fromHex: "f60")?.green == 0.4, "color picker: short hex expands")
        suite.expect(ColorPickerMath.rgb(fromHex: "ff6b4a") != nil, "color picker: hex without a hash reads")
        suite.expect(ColorPickerMath.rgb(fromHex: "#GG0000") == nil && ColorPickerMath.rgb(fromHex: "#12345") == nil
                     && ColorPickerMath.rgb(fromHex: "") == nil, "color picker: bad hex is refused")
        suite.expect(ColorPickerMath.hex(red: 1, green: 107 / 255, blue: 74 / 255) == "#FF6B4A", "color picker: hex writes")
        suite.expect(ColorPickerMath.hex(red: 1, green: 107 / 255, blue: 74 / 255, bare: true) == "FF6B4A",
                     "color picker: bare hex has no hash")
        suite.expect(ColorPickerMath.rgbString(red: 1, green: 107 / 255, blue: 74 / 255) == "rgb(255, 107, 74)",
                     "color picker: rgb text")
        suite.expect(ColorPickerMath.hslString(red: 1, green: 107 / 255, blue: 74 / 255) == "hsl(11, 100%, 65%)",
                     "color picker: hsl text")

        // HSB round trips, including the greys and the corners of the square.
        let samples: [(Double, Double, Double)] = [
            (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 107.0 / 255, 74.0 / 255),
            (0.2, 0.4, 0.6), (0.5, 0.5, 0.5), (0.0, 0.0, 0.0), (1.0, 1.0, 1.0)]
        for sample in samples {
            let color = ColorPickerMath.color(red: sample.0, green: sample.1, blue: sample.2)
            let back = ColorPickerMath.rgb(from: color)
            suite.expect(near(back.red, sample.0) && near(back.green, sample.1) && near(back.blue, sample.2),
                         "color picker: \(sample) survives a trip through HSB")
        }
        let red = ColorPickerMath.color(red: 1, green: 0, blue: 0)
        suite.expect(near(red.hue, 0) && near(red.saturation, 1) && near(red.brightness, 1), "color picker: red is hue 0")
        suite.expect(near(ColorPickerMath.color(red: 0, green: 1, blue: 0).hue, 1.0 / 3), "color picker: green is a third round")
        suite.expect(near(ColorPickerMath.color(red: 0, green: 0, blue: 1).hue, 2.0 / 3), "color picker: blue is two thirds round")
        suite.expect(ColorPickerMath.color(red: 0.4, green: 0.4, blue: 0.4).saturation == 0, "color picker: grey has no saturation")
        let wrapped = ColorPickerMath.rgb(from: ColorPickerColor(hue: 1, saturation: 1, brightness: 1))
        suite.expect(near(wrapped.red, 1) && near(wrapped.green, 0) && near(wrapped.blue, 0),
                     "color picker: hue 1 wraps back to red")

        // Contrast: the design shows 2.8 on white and 7.5 on black for #FF6B4A.
        let design = ColorPickerMath.contrast(red: 1, green: 107 / 255, blue: 74 / 255)
        suite.expect(near(design.onWhite, 2.8, 0.15) && near(design.onBlack, 7.5, 0.4), "color picker: sample contrast")
        let blackOnWhite = ColorPickerMath.contrast(red: 0, green: 0, blue: 0)
        suite.expect(near(blackOnWhite.onWhite, 21, 0.01) && near(blackOnWhite.onBlack, 1, 0.01),
                     "color picker: black against white is 21 to 1")
        suite.expect(ColorContrastGrade(ratio: 7) == .aaa && ColorContrastGrade(ratio: 6.99) == .aa
                     && ColorContrastGrade(ratio: 4.5) == .aa && ColorContrastGrade(ratio: 4.49) == .aaLarge
                     && ColorContrastGrade(ratio: 3) == .aaLarge && ColorContrastGrade(ratio: 2.99) == .low,
                     "color picker: WCAG grade thresholds")
        suite.expect(ColorContrastGrade.aaa.label == "AAA" && ColorContrastGrade.low.label == "LOW",
                     "color picker: grade labels")

        // Recent colors.
        var recents = ColorPickerMath.addingRecent("#ff6b4a", to: [])
        recents = ColorPickerMath.addingRecent("#00FF00", to: recents)
        suite.expect(recents == ["#00FF00", "#FF6B4A"], "color picker: newest recent first, upper case")
        recents = ColorPickerMath.addingRecent("#FF6B4A", to: recents)
        suite.expect(recents == ["#FF6B4A", "#00FF00"], "color picker: a repeat moves to the front")
        var many: [String] = []
        for value in 0..<15 { many = ColorPickerMath.addingRecent(String(format: "#%06X", value), to: many) }
        suite.expect(many.count == ColorPickerMath.recentLimit && many.first == "#00000E",
                     "color picker: recents keep the newest ten")
    }
}
