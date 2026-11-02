import AppKit
import Foundation

/// The script on the island's teleprompter and where the reading has got to.
/// It only runs while the page is showing: leaving the page pauses it.
final class NotchTeleprompterService: ObservableObject {
    static let shared = NotchTeleprompterService()

    @Published private(set) var script: String
    @Published private(set) var lines: [String]
    @Published private(set) var index = 0
    /// Seconds into the current line.
    @Published private(set) var lineElapsed: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var wpm: Int
    @Published var isEditing = false
    @Published private(set) var size: NotchTeleprompterSize
    /// Width the script's lines fill: the page's width less its padding and
    /// the marker beside the current line. Until the page reports its own, a
    /// medium island's.
    private(set) var layoutWidth: CGFloat = 420

    private let defaults: UserDefaults
    private var ticker: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: DefaultsKey.notchTeleprompterScript) ?? ""
        script = stored
        size = NotchTeleprompterSize.current(in: defaults)
        lines = Self.wrap(stored, width: 420)
        let speed = defaults.object(forKey: DefaultsKey.notchTeleprompterWPM) as? Int
        wpm = NotchTeleprompterSupport.clampedWPM(speed ?? NotchTeleprompterSupport.defaultWPM)
    }

    /// The island stays open while a script is playing or being written.
    var keepsIslandOpen: Bool { isPlaying || isEditing }

    var hasScript: Bool { !lines.isEmpty }
    var elapsed: TimeInterval {
        NotchTeleprompterSupport.start(of: index, in: lines, wpm: wpm) + lineElapsed
    }
    var total: TimeInterval { NotchTeleprompterSupport.totalDuration(lines, wpm: wpm) }
    var progress: Double { total > 0 ? min(1, max(0, elapsed / total)) : 0 }
    var isAtEnd: Bool {
        guard let last = lines.last else { return false }
        return index == lines.count - 1
            && lineElapsed >= NotchTeleprompterSupport.duration(of: last, wpm: wpm)
    }

    // MARK: Script

    func setScript(_ text: String) {
        guard text != script else { return }
        script = text
        defaults.set(text, forKey: DefaultsKey.notchTeleprompterScript)
        lines = Self.wrap(text, width: layoutWidth)
        index = min(index, max(0, lines.count - 1))
        lineElapsed = 0
        if lines.isEmpty { pause() }
    }

    /// The script split to fill the current width at the size the current
    /// line is shown in.
    private static func wrap(_ text: String, width: CGFloat) -> [String] {
        let font = NSFont.systemFont(ofSize: Self.lineFontSize, weight: .bold)
        return NotchTeleprompterSupport.lines(from: text, width: width) { string in
            ceil((string as NSString).size(withAttributes: [.font: font]).width)
        }
    }

    static let lineFontSize: CGFloat = 19

    /// The page reports how wide a line can be. A new width splits the script
    /// again, keeping the reader on the same word and the same time through it.
    func setLayoutWidth(_ width: CGFloat) {
        let width = (max(0, width) * 2).rounded() / 2
        guard width >= 40, abs(width - layoutWidth) >= 1 else { return }
        let fraction = lines.indices.contains(index)
            ? lineElapsed / NotchTeleprompterSupport.duration(of: lines[index], wpm: wpm) : 0
        let position = NotchTeleprompterSupport.wordPosition(index: index, fraction: fraction, in: lines)
        layoutWidth = width
        lines = Self.wrap(script, width: layoutWidth)
        guard !lines.isEmpty else { index = 0; lineElapsed = 0; return }
        let place = NotchTeleprompterSupport.place(wordPosition: position, in: lines)
        index = place.index
        lineElapsed = place.fraction * NotchTeleprompterSupport.duration(of: lines[place.index], wpm: wpm)
    }

    func setSize(_ next: NotchTeleprompterSize) {
        guard next != size else { return }
        size = next
        defaults.set(next.rawValue, forKey: DefaultsKey.notchTeleprompterSize)
        NotchService.shared.refreshPresentation()
    }

    func cycleSize() { setSize(size.next) }

    /// The text on the clipboard, if it holds any.
    static func clipboardText() -> String? {
        let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    // MARK: Reading

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        guard hasScript, !isPlaying else { return }
        if isAtEnd { restart() }
        isPlaying = true
        var last = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            let now = Date()
            self?.advance(by: now.timeIntervalSince(last))
            last = now
        }
    }

    func pause() {
        ticker?.invalidate(); ticker = nil
        if isPlaying { isPlaying = false }
    }

    func restart() {
        index = 0
        lineElapsed = 0
    }

    func nextLine() {
        guard index < lines.count - 1 else { return }
        index += 1
        lineElapsed = 0
    }

    func previousLine() {
        // A second press goes back a line; the first returns to this one's start.
        if lineElapsed > 1.5 || index == 0 { lineElapsed = 0; return }
        index -= 1
        lineElapsed = 0
    }

    /// Jumps to a point in the script, 0 for the start and 1 for the end.
    func seek(to fraction: Double) {
        guard hasScript else { return }
        let target = min(1, max(0, fraction)) * total
        let place = NotchTeleprompterSupport.position(at: target, in: lines, wpm: wpm)
        index = place.index
        lineElapsed = place.offset
    }

    func setWPM(_ value: Int) {
        let next = NotchTeleprompterSupport.clampedWPM(value)
        guard next != wpm else { return }
        // Keeps the place in the current line when the speed changes.
        let fraction = lines.indices.contains(index)
            ? lineElapsed / NotchTeleprompterSupport.duration(of: lines[index], wpm: wpm) : 0
        wpm = next
        defaults.set(next, forKey: DefaultsKey.notchTeleprompterWPM)
        if lines.indices.contains(index) {
            lineElapsed = fraction * NotchTeleprompterSupport.duration(of: lines[index], wpm: wpm)
        }
    }

    func adjustWPM(by steps: Int) {
        setWPM(NotchTeleprompterSupport.steppedWPM(wpm, by: steps))
    }

    private func advance(by seconds: TimeInterval) {
        guard isPlaying, lines.indices.contains(index) else { return }
        lineElapsed += seconds
        var length = NotchTeleprompterSupport.duration(of: lines[index], wpm: wpm)
        while lineElapsed >= length {
            if index < lines.count - 1 {
                lineElapsed -= length
                index += 1
                length = NotchTeleprompterSupport.duration(of: lines[index], wpm: wpm)
            } else {
                lineElapsed = length
                pause()
                return
            }
        }
    }

    func stop() {
        pause()
        isEditing = false
    }
}
