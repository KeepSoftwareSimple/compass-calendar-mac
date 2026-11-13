import CompassKit
import XCTest
@testable import CompassData

@MainActor
final class PaletteSearchResponsivenessTests: XCTestCase {
    func testRapidQueriesCoalesceAndLocalMatchesAppearImmediately() async throws {
        let api = MockEventsAPI()
        var queries: [String] = []
        api.listHandler = { query in
            queries.append(query.q ?? "")
            return []
        }
        let environment = try NativeCalendarEnvironment(inMemoryDatabase: true, eventsAPI: api)
        let model = NativeCalendarRootModel(environment: environment,
            now: { Date(timeIntervalSince1970: 1_767_268_800) })
        await model.authStore.bootstrap(forceDemoSignedIn: true)
        let event = try StoreSampleEvents.timedEvent(id: "coffee", title: "Coffee meeting")
        model.loadedEvents = [event]
        model.toggleCommandPalette()
        model.commandPaletteStore.query = "co"
        model.schedulePaletteEventSearch()
        let first = try XCTUnwrap(model.paletteSearchTask)
        XCTAssertEqual(model.paletteEventSearchHits.map(\.eventId), [event.id.rawValue])
        await Task.yield()
        model.commandPaletteStore.query = "cof"
        model.schedulePaletteEventSearch()
        await model.paletteSearchTask?.value
        await first.value
        XCTAssertEqual(queries, ["cof"])
    }

    func testMatchingRemoteRowsRemainVisibleWhileQueryNarrows() throws {
        let model = NativeCalendarRootModel(environment: try NativeCalendarEnvironment(inMemoryDatabase: true),
            now: { Date(timeIntervalSince1970: 1_767_268_800) })
        let match = try StoreSampleEvents.timedEvent(id: "coffee", title: "Coffee meeting")
        let other = try StoreSampleEvents.timedEvent(id: "coding", title: "Coding session")
        model.toggleCommandPalette()
        model.commandPaletteStore.query = "co"
        model.acceptPaletteSearchResults([match, other], query: "co")
        model.commandPaletteStore.query = "cof"
        model.schedulePaletteEventSearch()
        XCTAssertEqual(model.paletteEventSearchHits.map(\.eventId), [match.id.rawValue])
        XCTAssertEqual(model.paletteEventSearchEvents[match.id.rawValue], match)
        XCTAssertNil(model.paletteEventSearchEvents[other.id.rawValue])
    }

    func testCancelledRequestCannotPublishWhenQueryReturnsToSameText() async throws {
        let api = MockEventsAPI()
        let started = AsyncTestSignal()
        let release = AsyncTestSignal()
        let stale = try StoreSampleEvents.timedEvent(id: "stale", title: "Coffee stale")
        api.listHandler = { _ in
            await started.signal()
            await release.wait()
            return [stale]
        }
        let environment = try NativeCalendarEnvironment(inMemoryDatabase: true, eventsAPI: api)
        let model = NativeCalendarRootModel(environment: environment,
            now: { Date(timeIntervalSince1970: 1_767_268_800) })
        await model.authStore.bootstrap(forceDemoSignedIn: true)
        model.toggleCommandPalette()
        model.commandPaletteStore.query = "coffee"
        model.schedulePaletteEventSearch()
        let first = try XCTUnwrap(model.paletteSearchTask)
        await started.wait()
        model.commandPaletteStore.query = "coffees"
        model.schedulePaletteEventSearch()
        model.commandPaletteStore.query = "coffee"
        api.listHandler = { _ in [] }
        model.schedulePaletteEventSearch()
        await model.paletteSearchTask?.value
        await release.signal()
        await first.value
        XCTAssertTrue(model.paletteEventSearchHits.isEmpty)
        XCTAssertTrue(model.paletteEventSearchEvents.isEmpty)
    }
}
