import Foundation

enum NotchTapTests {
    /// A quiet laptop at 800 readings a second, with an optional fingertip: the
    /// light drops from 100 to `dip` lux at `at` seconds and comes back 0.35 s
    /// later, and the motion sensors jolt for 30 ms when `motion` is set.
    private static func taps(dip: Double? = nil, motion: Bool = true, jolt: Bool = true, at: Double = 1.5,
                             seconds: Double = 4, sensitivity: Double = 1.1) -> Int {
        var detector = NotchTapSignalDetector(sensitivity: sensitivity)
        var found = 0
        var time = 0.0
        var nextLight = 0.0
        var seed: UInt64 = 7
        func noise() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 40) / Double(1 << 24) - 0.5 }
        detector.reset(at: 0)
        while time < seconds {
            let shaking = jolt && motion && time >= at && time < at + 0.03
            let a = SIMD3(0.0003 * noise(), 0.0003 * noise(), -1 + 0.0003 * noise())
                + (shaking ? SIMD3(0.02 * sin(time * 900), 0, 0.02 * cos(time * 900)) : .zero)
            let g = SIMD3(0.02 * noise(), 0.02 * noise(), 0.02 * noise())
                + (shaking ? SIMD3(2.0 * sin(time * 700), 2.0 * cos(time * 700), 0) : .zero)
            detector.accel(a, at: time)
            detector.gyro(g, at: time + 0.0001)
            if time >= nextLight {
                let covered = dip != nil && time >= at && time < at + 0.35
                if detector.light(covered ? dip! : 100 + noise() * 0.4, at: time) { found += 1 }
                nextLight += 0.1
            }
            time += 0.00125
        }
        return found
    }

    static func run(_ suite: TestSuite) {
        suite.expect(taps() == 0, "tap: a still laptop finds nothing")
        suite.expect(taps(dip: nil, motion: true) == 0, "tap: a jolt with no change in light is a bump on the desk, not a tap")
        suite.expect(taps(dip: 40, motion: false) == 0, "tap: the light dipping with no jolt is a passing shadow, not a tap")
        suite.expect(taps(dip: 40, motion: true) == 1, "tap: a fingertip shading the light with a jolt is one tap")
        suite.expect(taps(dip: 99.9, motion: true) == 0, "tap: a barely visible dip is not enough")

        let defaults = UserDefaults(suiteName: "com.nyx.tests.tap.\(UUID().uuidString)")!
        suite.expect(!NotchTapSupport.isEnabled(in: defaults), "tap: it is off until turned on")
        defaults.set(true, forKey: DefaultsKey.notchTapToOpen)
        suite.expect(NotchTapSupport.isEnabled(in: defaults), "tap: turning it on is remembered")
    }
}
