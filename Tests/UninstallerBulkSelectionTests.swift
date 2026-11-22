// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Nyx

import AppKit

/// Production selection and summaries run against the flow fixture. Scanning
/// stays simulated; no files are removed.
enum UninstallerBulkSelectionTests {
    private typealias Bulk = UninstallerSupport.BulkSelection
    private typealias Fixture = UninstallerFlowTests

    static func run(_ suite: TestSuite) {
        suite.expect(Bulk(included: 0, total: 0) == .none,
                     "an empty results list shows an empty box")
        suite.expect(Bulk(included: 0, total: 3) == .none,
                     "no chosen rows show an empty box")
        suite.expect(Bulk(included: 1, total: 3) == .some,
                     "some chosen rows show a mixed box")
        suite.expect(Bulk(included: 3, total: 3) == .all,
                     "every chosen row shows a checked box")
        suite.expect(Bulk(included: 2, total: 2) == .all,
                     "a full list of two reads the same as a full list of many")

        suite.expect(Bulk.none.nextInclude && Bulk.some.nextInclude,
                     "clicking an empty or mixed box selects everything")
        suite.expect(!Bulk.all.nextInclude,
                     "clicking a full box clears the selection")
        modelChecks(suite)
    }

    private static func modelChecks(_ suite: TestSuite) {
        let uninstaller = Fixture.Uninstaller()
        uninstaller.phase = .results
        for include in [true, false] {
            uninstaller.setAllIncluded(include)
            suite.expect(uninstaller.items.isEmpty && uninstaller.bulkSelection == .none
                         && uninstaller.selectedSize == 0 && uninstaller.totalSize == 0
                         && !uninstaller.canRemoveSelected,
                         "bulk selection leaves an empty result empty and cannot enable removal")
        }

        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("bulk-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Editor.app", isDirectory: true)
        do {
            try UninstallerTrashTests.writeBundle(at: appURL, id: "org.nyx.fixture.editor")
            uninstaller.targetSelection = UninstallerSupport.selection(for: appURL)
        } catch {
            suite.expect(false, "could not create the bulk selection fixture: \(error)")
            return
        }
        let original = [
            Fixture.Leftover(url: appURL, category: .app, size: 100),
            Fixture.Leftover(url: appURL.appendingPathExtension("support"), category: .support, size: 20),
            Fixture.Leftover(url: appURL.appendingPathExtension("cache"), category: .caches, size: 30,
                             confidence: .related, include: false),
            Fixture.Leftover(url: appURL.appendingPathExtension("plist"), category: .preferences, size: 40,
                             confidence: .related, include: false),
        ]
        uninstaller.items = original
        uninstaller.target = Fixture.Target(name: "Editor", bundleID: "org.nyx.fixture.editor",
                                            url: appURL, icon: NSImage())
        func expectSelection(_ flags: [Bool], _ state: Bulk, _ count: Int, _ size: Int64, _ context: String) {
            var expected = original
            for index in expected.indices { expected[index].include = flags[index] }
            // Fixture equality also checks IDs, paths, categories, sizes and confidence.
            suite.expect(uninstaller.items == expected,
                         "\(context) changes only the requested inclusion flags on the same rows")
            suite.expect(uninstaller.bulkSelection == state
                         && uninstaller.items.filter(\.include).count == count
                         && uninstaller.selectedSize == size && uninstaller.totalSize == 190,
                         "\(context) updates the mixed state, count and byte totals together")
        }
        expectSelection([true, true, false, false], .some, 2, 120, "initial mixed results")
        uninstaller.setAllIncluded(uninstaller.bulkSelection.nextInclude)
        expectSelection([true, true, true, true], .all, 4, 190, "selecting all including optional rows")
        uninstaller.setInclude(false, for: original[2].id)
        expectSelection([true, true, false, true], .some, 3, 160, "unchecking one optional exception")
        uninstaller.setAllIncluded(uninstaller.bulkSelection.nextInclude)
        expectSelection([true, true, true, true], .all, 4, 190, "selecting all after an exception")
        uninstaller.setAllIncluded(uninstaller.bulkSelection.nextInclude)
        expectSelection([false, false, false, false], .none, 0, 0, "clearing a full selection")
        suite.expect(!uninstaller.canRemoveSelected, "clearing every row disables removal")
        uninstaller.setAllIncluded(uninstaller.bulkSelection.nextInclude)
        expectSelection([true, true, true, true], .all, 4, 190, "selecting all from nothing")
        suite.expect(uninstaller.phase == .results && uninstaller.canRemoveSelected,
                     "selection changes only prepare a removable selection and never start removal")

        uninstaller.items = original
        uninstaller.phase = .removing
        suite.expect(uninstaller.isRemoving, "the production guard recognizes a removal in progress")
        for include in [false, true] {
            uninstaller.setAllIncluded(include)
            expectSelection([true, true, false, false], .some, 2, 120, "blocked bulk change during removal")
        }
        uninstaller.setInclude(false, for: original[0].id)
        expectSelection([true, true, false, false], .some, 2, 120, "blocked per-row change during removal")
        uninstaller.phase = .results
        uninstaller.setAllIncluded(false)
        expectSelection([false, false, false, false], .none, 0, 0, "editing again after removal stops")
    }
}
