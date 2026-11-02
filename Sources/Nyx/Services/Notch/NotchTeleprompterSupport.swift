import Foundation

/// The teleprompter's script handling: how a script breaks into the lines
/// shown on the island, and how long each one stays up at a reading speed.
/// How large the island opens on the teleprompter page. Medium is the size it
/// had before the choice existed.
enum NotchTeleprompterSize: String, CaseIterable {
    case medium, large

    var widthScale: CGFloat {
        switch self {
        case .medium: return 1
        case .large: return 1.4
        }
    }

    var heightScale: CGFloat {
        switch self {
        case .medium: return 1
        case .large: return 1.6
        }
    }

    /// The next size, wrapping from the largest back to the normal size.
    var next: NotchTeleprompterSize {
        switch self {
        case .medium: return .large
        case .large: return .medium
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> NotchTeleprompterSize {
        defaults.string(forKey: DefaultsKey.notchTeleprompterSize).flatMap(NotchTeleprompterSize.init(rawValue:)) ?? .medium
    }
}

enum NotchTeleprompterSupport {
    static let wpmRange = 60...300
    static let wpmStep = 5
    static let defaultWPM = 150
    /// A very short line still stays up long enough to be read.
    static let minimumLineSeconds: TimeInterval = 1.2

    static func clampedWPM(_ value: Int) -> Int {
        min(max(value, wpmRange.lowerBound), wpmRange.upperBound)
    }

    /// The speed moved by whole steps, landing on a multiple of the step.
    static func steppedWPM(_ value: Int, by steps: Int) -> Int {
        let base = Int((Double(value) / Double(wpmStep)).rounded()) * wpmStep
        return clampedWPM(base + steps * wpmStep)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Every line the user typed starts a new line; a long one wraps only when
    /// the next word would no longer fit across `width`, so each line holds as
    /// many words as it can. A word wider than the whole line sits alone and
    /// is shrunk by the view. `measure` is the width of a string as shown.
    /// Blank lines are dropped.
    static func lines(from script: String, width: CGFloat, measure: (String) -> CGFloat) -> [String] {
        var result: [String] = []
        for paragraph in script.components(separatedBy: .newlines) {
            let words = paragraph.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { continue }
            var chunk = ""
            for word in words {
                if chunk.isEmpty { chunk = word; continue }
                let candidate = chunk + " " + word
                if measure(candidate) <= width {
                    chunk = candidate
                } else {
                    result.append(chunk)
                    chunk = word
                }
            }
            if !chunk.isEmpty { result.append(chunk) }
        }
        return result
    }

    /// Where the reader is in the script as a count of words, so the place
    /// survives the script being split into different lines.
    static func wordPosition(index: Int, fraction: Double, in lines: [String]) -> Double {
        guard lines.indices.contains(index) else { return 0 }
        let before = lines.prefix(index).reduce(0) { $0 + wordCount($1) }
        return Double(before) + min(1, max(0, fraction)) * Double(wordCount(lines[index]))
    }

    /// The line holding a word position, and how far through that line it is.
    static func place(wordPosition: Double, in lines: [String]) -> (index: Int, fraction: Double) {
        guard !lines.isEmpty else { return (0, 0) }
        var remaining = max(0, wordPosition)
        for (index, line) in lines.enumerated() {
            let count = Double(max(1, wordCount(line)))
            if remaining < count { return (index, remaining / count) }
            remaining -= count
        }
        return (lines.count - 1, 1)
    }

    static func duration(of line: String, wpm: Int) -> TimeInterval {
        max(minimumLineSeconds, Double(wordCount(line)) * 60 / Double(max(1, wpm)))
    }

    static func totalDuration(_ lines: [String], wpm: Int) -> TimeInterval {
        lines.reduce(0) { $0 + duration(of: $1, wpm: wpm) }
    }

    /// Time before the line at `index` begins.
    static func start(of index: Int, in lines: [String], wpm: Int) -> TimeInterval {
        lines.prefix(max(0, index)).reduce(0) { $0 + duration(of: $1, wpm: wpm) }
    }

    /// The line playing at a time, with how far into it that time is.
    static func position(at time: TimeInterval, in lines: [String], wpm: Int) -> (index: Int, offset: TimeInterval) {
        guard !lines.isEmpty else { return (0, 0) }
        var remaining = max(0, time)
        for (index, line) in lines.enumerated() {
            let length = duration(of: line, wpm: wpm)
            if remaining < length { return (index, remaining) }
            remaining -= length
        }
        let last = lines.count - 1
        return (last, duration(of: lines[last], wpm: wpm))
    }

    /// "0:07", or "1:05:09" past an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
                         : String(format: "%d:%02d", minutes, secs)
    }

    /// Whether the island's window may appear in recordings and screenshots.
    /// The teleprompter page can stay out of them while it is open, so a script
    /// read from the island never shows up in a video of the screen.
    static func sharesWithCaptures(page: NotchModule, expanded: Bool, in defaults: UserDefaults = .standard) -> Bool {
        guard NotchSupport.showsInCaptures(in: defaults) else { return false }
        return !(expanded && page == .teleprompter && hidesFromCaptures(in: defaults))
    }

    static func hidesFromCaptures(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchTeleprompterHideFromCaptures) as? Bool ?? true
    }
}
