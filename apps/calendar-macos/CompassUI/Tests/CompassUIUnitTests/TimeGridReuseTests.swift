import AppKit
import CompassKit
import XCTest
@testable import CompassUI

@MainActor
final class TimeGridReuseTests: XCTestCase {
    func testFocusAndUnchangedUpdatesPreserveHeaderAndHourLabelViews() {
        let savedZone = EffectiveTimeZone.identifier
        defer { EffectiveTimeZone.identifier = savedZone }
        EffectiveTimeZone.identifier = "UTC"
        var state = TimeGridState(scenario: GridLayoutSnapshotFixtures.parityScenario(layoutMode: .week, visibleDateKeys: ["2026-05-17", "2026-05-18"]))
        let view = TimeGridView(state: state, theme: .lightBeach)
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.layoutSubtreeIfNeeded()
        view.update(state: state, theme: .lightBeach)
        let header = descendants(view).first { $0.identifier?.rawValue == state.scenario.visibleDateKeys.first }
        let hour = descendants(view).compactMap { $0 as? NSTextField }.first { $0.stringValue == "1 AM" }
        XCTAssertNotNil(header)
        XCTAssertNotNil(hour)
        state.focusedEventId = state.scenario.timedEvents.first?.eventId
        view.update(state: state, theme: .lightBeach)
        view.update(state: state, theme: .lightBeach)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(descendants(view).contains { $0 === header })
        XCTAssertTrue(descendants(view).contains { $0 === hour })

        view.update(state: state, theme: .darkAbyss)
        XCTAssertFalse(descendants(view).contains { $0 === header })
        XCTAssertFalse(descendants(view).contains { $0 === hour })
    }

    func testHeaderHintsStillUpdateWhenFocusChromeIsReused() {
        var state = TimeGridState(scenario: GridLayoutSnapshotFixtures.parityScenario(layoutMode: .week, visibleDateKeys: ["2026-05-17", "2026-05-18"]))
        let view = TimeGridView(state: state, theme: .lightBeach)
        let header = descendants(view).first { $0.identifier?.rawValue == state.scenario.visibleDateKeys.first }
        state.showDayJumpPrefixes = true
        view.update(state: state, theme: .lightBeach)
        XCTAssertFalse(descendants(view).contains { $0 === header })
        XCTAssertTrue(descendants(view).contains { $0 is WeekDayColumnHeaderControl })
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }
}
