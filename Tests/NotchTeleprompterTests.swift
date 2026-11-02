import Foundation

/// How a script breaks into lines, how long each stays up, and when the
/// island is kept out of recordings.
enum NotchTeleprompterTests {
    static func run(_ suite: TestSuite) {
        let support = NotchTeleprompterSupport.self
        // Width is counted in characters here, so no fonts are needed.
        let chars: (String) -> CGFloat = { CGFloat($0.count) }

        suite.expect(support.lines(from: "", width: 50, measure: chars) == [], "teleprompter: an empty script has no lines")
        suite.expect(support.lines(from: "  \n\n \t\n", width: 50, measure: chars) == [], "teleprompter: blank lines are not lines")
        suite.expect(support.lines(from: "Hello there\n\nSecond line", width: 50, measure: chars) == ["Hello there", "Second line"],
                     "teleprompter: each script line is a line, blanks dropped")
        suite.expect(support.lines(from: "aa bb cc dd ee ff", width: 8, measure: chars) == ["aa bb cc", "dd ee ff"],
                     "teleprompter: a line takes as many words as fit across the width")
        suite.expect(support.lines(from: "aa bb cc dd ee ff", width: 100, measure: chars) == ["aa bb cc dd ee ff"],
                     "teleprompter: a wide page keeps a whole sentence on one line")
        suite.expect(support.lines(from: "hi extraordinarily x", width: 10, measure: chars) == ["hi", "extraordinarily", "x"],
                     "teleprompter: a word that does not fit moves to the next line, and a very long one stands alone")
        suite.expect(support.lines(from: "a b\n\nc", width: 100, measure: chars) == ["a b", "c"],
                     "teleprompter: every typed line break starts a new line")
        suite.expect(support.lines(from: "It lives in the notch. Then more words", width: 100, measure: chars)
                        == ["It lives in the notch. Then more words"],
                     "teleprompter: a full stop alone does not end a line")
        suite.expect(support.lines(from: "Hi. Yo", width: 100, measure: chars) == ["Hi. Yo"],
                     "teleprompter: a short line stays whole even with a full stop in it")

        // The reader keeps their place in the words when the width changes.
        let wide = support.lines(from: "aa bb cc dd ee ff", width: 8, measure: chars)
        let narrow = support.lines(from: "aa bb cc dd ee ff", width: 5, measure: chars)
        suite.expect(narrow == ["aa bb", "cc dd", "ee ff"], "teleprompter: a narrower page splits into more lines")
        let word = support.wordPosition(index: 1, fraction: 0, in: wide)
        suite.expect(word == 3, "teleprompter: a line start is the count of words before it")
        let moved = support.place(wordPosition: word, in: narrow)
        suite.expect(moved.index == 1 && moved.fraction == 0.5,
                     "teleprompter: the same word is found again after the script is split differently")
        suite.expect(support.place(wordPosition: 99, in: narrow) == (2, 1) && support.place(wordPosition: 1, in: []) == (0, 0),
                     "teleprompter: a place past the end rests on the last line, an empty script has none")
        suite.expect(support.wordPosition(index: 9, fraction: 0.5, in: wide) == 0,
                     "teleprompter: a line that does not exist has no word position")

        suite.expect(support.lines(from: "one\r\ntwo", width: 50, measure: chars) == ["one", "two"], "teleprompter: Windows line breaks split too")

        suite.expect(support.wordCount("  one   two\nthree ") == 3, "teleprompter: words count across any spacing")
        suite.expect(support.duration(of: String(repeating: "word ", count: 10), wpm: 120) == 5,
                     "teleprompter: ten words at 120 WPM take five seconds")
        suite.expect(support.duration(of: "Hi", wpm: 300) == support.minimumLineSeconds,
                     "teleprompter: a very short line still stays up a moment")

        suite.expect(support.clampedWPM(10) == 60 && support.clampedWPM(999) == 300 && support.clampedWPM(155) == 155,
                     "teleprompter: speed stays within 60 to 300")
        suite.expect(support.steppedWPM(150, by: 1) == 155 && support.steppedWPM(150, by: -1) == 145,
                     "teleprompter: the speed moves five at a time")
        suite.expect(support.steppedWPM(152, by: 1) == 155, "teleprompter: stepping lands on a multiple of five")
        suite.expect(support.steppedWPM(300, by: 1) == 300 && support.steppedWPM(60, by: -1) == 60,
                     "teleprompter: stepping stops at the ends")

        let lines = [String(repeating: "w ", count: 10), String(repeating: "w ", count: 5), "tail words here"]
        // At 60 WPM: 10 s, 5 s and 3 s.
        suite.expect(support.totalDuration(lines, wpm: 60) == 18, "teleprompter: the total adds each line")
        suite.expect(support.start(of: 2, in: lines, wpm: 60) == 15, "teleprompter: a line starts after the ones before it")
        let early = support.position(at: 12, in: lines, wpm: 60)
        suite.expect(early.index == 1 && early.offset == 2, "teleprompter: a time lands inside its line")
        let boundary = support.position(at: 10, in: lines, wpm: 60)
        suite.expect(boundary.index == 1 && boundary.offset == 0, "teleprompter: a line boundary belongs to the next line")
        let past = support.position(at: 99, in: lines, wpm: 60)
        suite.expect(past.index == 2 && past.offset == 3, "teleprompter: past the end rests on the last line's end")
        suite.expect(support.position(at: 5, in: [], wpm: 60) == (0, 0), "teleprompter: no lines, no place")

        suite.expect(support.clock(7) == "0:07" && support.clock(25.9) == "0:25" && support.clock(65) == "1:05",
                     "teleprompter: times read as minutes and seconds")
        suite.expect(support.clock(3669) == "1:01:09" && support.clock(-4) == "0:00",
                     "teleprompter: hours show, negatives clamp")

        let defaults = UserDefaults(suiteName: "com.nyx.tests.teleprompter")!
        defaults.removePersistentDomain(forName: "com.nyx.tests.teleprompter")
        suite.expect(support.hidesFromCaptures(in: defaults), "teleprompter: hidden from recordings unless turned off")
        suite.expect(!support.sharesWithCaptures(page: .teleprompter, expanded: true, in: defaults),
                     "teleprompter: the open page stays out of recordings by default")
        suite.expect(support.sharesWithCaptures(page: .teleprompter, expanded: false, in: defaults),
                     "teleprompter: the closed island is not hidden")
        suite.expect(support.sharesWithCaptures(page: .music, expanded: true, in: defaults),
                     "teleprompter: other pages keep showing in recordings")
        defaults.set(false, forKey: DefaultsKey.notchTeleprompterHideFromCaptures)
        suite.expect(support.sharesWithCaptures(page: .teleprompter, expanded: true, in: defaults),
                     "teleprompter: turning the setting off shows the page in recordings")
        defaults.set(false, forKey: DefaultsKey.notchShowInCaptures)
        suite.expect(!support.sharesWithCaptures(page: .music, expanded: true, in: defaults),
                     "teleprompter: the island's own hide-from-captures choice still wins")
        defaults.removePersistentDomain(forName: "com.nyx.tests.teleprompter")

        suite.expect(NotchTeleprompterSize.medium.widthScale == 1 && NotchTeleprompterSize.medium.heightScale == 1,
                     "teleprompter: medium is the size the page always had")
        suite.expect(NotchTeleprompterSize.medium.widthScale == 1 && NotchTeleprompterSize.large.widthScale > 1
                     && NotchTeleprompterSize.medium.heightScale == 1 && NotchTeleprompterSize.large.heightScale > 1,
                     "teleprompter: medium is today's size and large grows both ways")
        suite.expect(NotchTeleprompterSize.medium.next == .large
                     && NotchTeleprompterSize.large.next == .medium, "teleprompter: the resize control switches between the two sizes")
        suite.expect(NotchTeleprompterSize.current(in: defaults) == .medium, "teleprompter: the size defaults to medium")
        defaults.set("large", forKey: DefaultsKey.notchTeleprompterSize)
        suite.expect(NotchTeleprompterSize.current(in: defaults) == .large, "teleprompter: a chosen size is read back")
        defaults.set("huge", forKey: DefaultsKey.notchTeleprompterSize)
        suite.expect(NotchTeleprompterSize.current(in: defaults) == .medium, "teleprompter: an unknown size falls back to medium")

        defaults.removePersistentDomain(forName: "com.nyx.tests.teleprompter")

        let strings = FeatureStrings.notchTeleprompter(.enUS)
        suite.expect(String(format: strings.lineFormat, 4, 15) == "Line 4 of 15", "teleprompter: the line counter reads as written")
    }
}
