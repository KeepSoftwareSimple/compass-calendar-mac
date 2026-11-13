import CompassKit
import XCTest
@testable import CompassData

@MainActor
final class VisibleRangeRefreshTests: XCTestCase {
    func testCachedWeekPaintsBeforeNetworkAndOlderWeekCannotReplaceNewerView() async throws {
        let api = MockEventsAPI()
        let environment = try NativeCalendarEnvironment(inMemoryDatabase: true,
            sessionStore: MemorySessionStore(tokens: nil), eventsAPI: api, repositorySource: .remote)
        let event = try StoreSampleEvents.timedEvent(id: "cached")
        let model = NativeCalendarRootModel(environment: environment)
        await model.authStore.bootstrap(forceDemoSignedIn: true)
        environment.eventsStore.setSource(.remote)
        model.viewStore.anchorDate = try XCTUnwrap(CompassDateParsing.parseInEffectiveTimeZone("2026-01-01T00:00:00Z"))
        try EventRepository(database: environment.database).upsert(events: [event], isLocal: false)
        let started = AsyncTestSignal()
        let release = AsyncTestSignal()
        api.listHandler = { _ in
            await started.signal()
            await release.wait()
            return [event]
        }
        let oldRefresh = Task { await model.refreshVisibleRange() }
        await started.wait()
        XCTAssertEqual(model.loadedEvents, [event], "Cached events should paint while the request is suspended")
        model.viewStore.anchorDate = try XCTUnwrap(CompassDateParsing.parseInEffectiveTimeZone("2026-02-01T00:00:00Z"))
        api.listHandler = { _ in [] }
        await model.refreshVisibleRange()
        let currentPresentation = model.timeGridState
        let cards = currentPresentation.snapshot(colWidths: currentPresentation.resolvedColumnWidths()).cards
        XCTAssertFalse(cards.contains { $0.eventId == event.id.rawValue })
        await release.signal()
        await oldRefresh.value
        XCTAssertEqual(model.timeGridState, currentPresentation,
            "An older request must not repaint the newly selected week")
        XCTAssertTrue(model.loadedEvents.contains { $0.id == event.id },
            "Offscreen context must remain available for notification and recurrence actions")
    }
}
