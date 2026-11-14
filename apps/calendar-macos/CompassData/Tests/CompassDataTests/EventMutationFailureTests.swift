import CompassKit
import XCTest
@testable import CompassData

@MainActor
final class EventMutationFailureTests: XCTestCase {
    func testEditFailureFromPreviousSessionDoesNotShowAnErrorInTheNewSession() async throws {
        let api = MockEventsAPI()
        let environment = try NativeCalendarEnvironment(inMemoryDatabase: true,
            sessionStore: MemorySessionStore(tokens: nil), eventsAPI: api, repositorySource: .remote)
        let model = NativeCalendarRootModel(environment: environment)
        await model.authStore.bootstrap(forceDemoSignedIn: true)
        let event = try StoreSampleEvents.timedEvent(id: "previous-session")
        try EventRepository(database: environment.database).upsert(events: [event], isLocal: false)
        model.loadedEvents = [event]
        api.replaceHandler = { _, _ in
            await model.authStore.handleSessionExpired()
            throw URLError(.notConnectedToInternet)
        }
        await model.replaceEvent(with: event)
        XCTAssertNil(model.statusToastStore.message)
    }

    func testReplaceDeleteAndRsvpFailuresPropagateAndInvalidate() async throws {
        let api = MockEventsAPI()
        api.replaceHandler = { _, _ in throw URLError(.notConnectedToInternet) }
        api.deleteHandler = { _, _ in throw URLError(.notConnectedToInternet) }
        api.rsvpHandler = { throw URLError(.notConnectedToInternet) }
        let environment = try NativeCalendarEnvironment(inMemoryDatabase: true, eventsAPI: api, repositorySource: .remote)
        let event = try StoreSampleEvents.timedEvent(id: "original")
        let repository = EventRepository(database: environment.database)
        let store = environment.eventsStore
        let key = EventRangeQueryKey(scope: .week, source: .remote,
            start: "2026-01-01T00:00:00Z", end: "2026-01-08T00:00:00Z")
        let cache = RangeCache(database: environment.database)
        let input = ReplaceEventInput(content: .init(description: "", kind: "details", location: "", title: "Edited"),
            recurrence: .preserve(.init(kind: "preserve")), scope: .this)
        for action in 0..<3 {
            try repository.upsert(events: [event], isLocal: false)
            try cache.markLoaded(key: key)
            do {
                switch action {
                case 0: try await store.replaceOptimistic(id: event.id, input: input, optimisticEvent: event)
                case 1: try await store.deleteOptimistic(id: event.id, scope: .this)
                default: try await store.rsvpOptimistic(id: event.id, responseStatus: .accepted,
                    scope: "this", optimisticEvent: event)
                }
                XCTFail("A failed mutation must reach its caller")
            } catch let error as URLError {
                XCTAssertEqual(error.code, .notConnectedToInternet)
            }
            XCTAssertEqual(store.inFlightMutations, 0)
            XCTAssertEqual(try store.coverage(for: key), .missing)
        }
    }

    func testFailedEditReconcilesFromServerOnRefresh() async throws {
        let api = MockEventsAPI()
        let environment = try NativeCalendarEnvironment(inMemoryDatabase: true,
            sessionStore: MemorySessionStore(tokens: nil), eventsAPI: api, repositorySource: .remote)
        let model = NativeCalendarRootModel(environment: environment)
        await model.authStore.bootstrap(forceDemoSignedIn: true)
        environment.eventsStore.setSource(.remote)
        let event = try StoreSampleEvents.timedEvent(id: "original")
        let edited = try StoreSampleEvents.timedEvent(id: "original", title: "Failed edit")
        model.viewStore.anchorDate = try XCTUnwrap(CompassDateParsing.parseInEffectiveTimeZone("2026-01-01T00:00:00Z"))
        try EventRepository(database: environment.database).upsert(events: [event], isLocal: false)
        model.loadedEvents = [event]
        api.replaceHandler = { _, _ in throw URLError(.notConnectedToInternet) }
        api.listHandler = { _ in [event] }
        await model.replaceEvent(with: edited)
        XCTAssertEqual(model.statusToastStore.message, "Could not restore event. Try again.")
        await model.refreshVisibleRange()
        XCTAssertEqual(model.loadedEvents, [event])
    }

    func testFailedFormSaveRetainsInputAndRequestsReconciliation() async throws {
        let environment = try NativeCalendarEnvironment(inMemoryDatabase: true)
        let model = NativeCalendarRootModel(environment: environment)
        let draft = GridEventDraft(clientId: EventId(rawValue: "draft"),
            schedule: DraftSchedule(start: Date(), end: Date().addingTimeInterval(3600), kind: .timed),
            title: "Keep my changes")
        model.draftStore.startGridDraft(activity: .keyboardEdit, draft: draft)
        model.draftStore.setTitle("Changed title")
        var expected = draft
        expected.title = "Changed title"
        await model.persistDraftOptimistic(savedId: "draft") { throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(model.draftStore.gridDraft, expected)
        XCTAssertTrue(model.draftStore.status.isFormOpen)
        XCTAssertTrue(model.draftStore.hasUnsavedFormChanges)
        XCTAssertEqual(model.statusToastStore.message, "Could not save event. Try again.")
        XCTAssertTrue(model.testingVisibleRangeRefreshIsScheduled)
    }

    func testRetryRetainsChangedScheduleAgainstOriginalEvent() async throws {
        let environment = try NativeCalendarEnvironment(inMemoryDatabase: true, repositorySource: .remote)
        let model = NativeCalendarRootModel(environment: environment)
        let original = try StoreSampleEvents.timedEvent(id: "edit")
        model.loadedEvents = [original]
        let start = try XCTUnwrap(CompassDateParsing.parseInEffectiveTimeZone("2026-01-01T12:00:00Z"))
        let draft = GridEventDraft(kind: .edit, clientId: original.id,
            schedule: DraftSchedule(start: start, end: start.addingTimeInterval(3600), kind: .timed),
            calendarId: original.calendarId, sourceEventId: original.id)
        let optimistic = try XCTUnwrap(GridEventDraftMapping.optimisticEvent(from: draft, baseline: original))
        model.draftStore.startGridDraft(activity: .keyboardEdit, draft: draft)
        await model.persistDraftOptimistic(savedId: original.id.rawValue) {
            try EventRepository(database: environment.database).upsert(events: [optimistic], isLocal: false)
            throw URLError(.notConnectedToInternet)
        }
        let retryBaseline = model.baselineEvent(for: draft)
        XCTAssertEqual(retryBaseline, original)
        let retry = try XCTUnwrap(GridEventDraftMapping.replaceInput(from: draft,
            originalCalendarId: original.calendarId, scope: .this, baseline: retryBaseline))
        XCTAssertNotNil(retry.schedule, "The retry must resend the time change even though the cache is optimistic")
        model.draftStore.discard()
        XCTAssertNil(model.draftStore.retryEventBaseline)
    }

    func testFailedSaveDoesNotReplaceANewerDraft() async throws {
        let model = NativeCalendarRootModel(environment: try NativeCalendarEnvironment(inMemoryDatabase: true))
        let original = GridEventDraft(clientId: EventId(rawValue: "old"),
            schedule: DraftSchedule(start: Date(), end: Date().addingTimeInterval(3600), kind: .timed))
        var newer = original
        newer.title = "Newer input"
        model.draftStore.startGridDraft(activity: .keyboardEdit, draft: original)
        await model.persistDraftOptimistic(savedId: "old") {
            model.draftStore.startGridDraft(activity: .keyboardEdit, draft: newer)
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(model.draftStore.gridDraft, newer)
    }

    func testFailedDeleteDoesNotRecordSuccessfulUndo() async throws {
        let api = MockEventsAPI()
        api.deleteHandler = { _, _ in throw URLError(.notConnectedToInternet) }
        let environment = try NativeCalendarEnvironment(inMemoryDatabase: true, eventsAPI: api, repositorySource: .remote)
        let model = NativeCalendarRootModel(environment: environment)
        let event = try StoreSampleEvents.timedEvent(id: "original")
        try EventRepository(database: environment.database).upsert(events: [event], isLocal: false)
        model.loadedEvents = [event]
        await model.deleteEvent(event, scope: .this)
        XCTAssertEqual(model.statusToastStore.message, "Could not delete event. Try again.")
        XCTAssertFalse(model.undoStore.canUndo)
    }
}
