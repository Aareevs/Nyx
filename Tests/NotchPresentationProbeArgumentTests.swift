import Foundation

/// Any mode of the Developer presentation probe runs it on its own, rather
/// than launching the whole app, while ordinary launches still reach the app.
/// `Mode` is the table `runAndExit` dispatches on and `isRequested` the
/// production check, both generated from source.
enum NotchPresentationProbeArgumentTests {
    static func run(_ suite: TestSuite) {
        let binary = "/Applications/Nyx (Developer).app/Contents/MacOS/NyxDeveloper"
        for mode in Probe.Mode.allCases {
            suite.expect(Probe.isRequested(by: [binary, mode.rawValue]),
                         "\(mode.rawValue) on its own runs the presentation probe")
        }
        suite.expect(Probe.isRequested(by: [binary, "--media-layout", "--glass"]),
                     "--media-layout with --glass runs the presentation probe")
        for launch in [[binary], [binary, "-featureAvailable.notch", "NO"], [binary, "--unrelated-flag"]] {
            suite.expect(!Probe.isRequested(by: launch), "\(launch.dropFirst()) launches the app")
        }
    }
}
