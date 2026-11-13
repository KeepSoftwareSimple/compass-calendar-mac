import CompassKit
import XCTest
@testable import CompassData

@MainActor
final class CalendarStartupTests: XCTestCase {
    override func tearDown() async throws {
        StartupTransport.handler = nil
        try await super.tearDown()
    }

    func testCachedCalendarPaintsBeforeMetadataAndLifePreferencesDoNotBlockFreshGrid() async throws {
        let fixture = try DemoSeedFixture.load()
        let event = try XCTUnwrap(fixture.events.first?.event)
        let calendarData = try JSONEncoder().encode(CalendarListResponse(calendars: [fixture.calendarListItem()]))
        let metadataStarted = expectation(description: "Calendar metadata request")
        let lifeStarted = expectation(description: "Life preferences request")
        let hiddenStarted = expectation(description: "Hidden events request")
        let releaseMetadata = AsyncTestSignal()
        let releaseLife = AsyncTestSignal()
        let releaseHidden = AsyncTestSignal()
        StartupTransport.handler = { request in
            if request.url?.path.hasSuffix("/calendars") == true {
                metadataStarted.fulfill()
                await releaseMetadata.wait()
                return .init(status: 200, data: calendarData)
            }
            if request.url?.path.hasSuffix("/life-preferences") == true {
                lifeStarted.fulfill()
                await releaseLife.wait()
                return .init(status: 200, data: Data(#"{"preferences":null,"revision":0}"#.utf8))
            }
            return .init(status: 404, data: Data())
        }
        let hidden = MockUserAPI()
        hidden.hiddenIdsHandler = {
            hiddenStarted.fulfill()
            await releaseHidden.wait()
            return []
        }
        let api = MockEventsAPI()
        var freshRangeLoaded = false
        api.listHandler = { _ in
            freshRangeLoaded = true
            return [event]
        }
        let environment = try makeEnvironment(api: api, hidden: hidden)
        try AccountCacheIdentity.record(userId: "startup-user", repository: environment.userMetadataRepository)
        try environment.calendarRepository.upsert(calendars: [fixture.calendarListItem()])
        try EventRepository(database: environment.database).upsert(events: [event], isLocal: false)
        try HiddenEventRepository(database: environment.database).replaceAll(eventIds: ["cached-hidden"])
        let model = NativeCalendarRootModel(environment: environment, demoPresentation: fixture)
        let startup = Task { await model.start() }
        await fulfillment(of: [metadataStarted, hiddenStarted], timeout: 3)
        XCTAssertTrue(model.loadedEvents.contains { $0.id == event.id })
        XCTAssertTrue(environment.hiddenEventsStore.hiddenEventIds.contains("cached-hidden"))
        XCTAssertFalse(freshRangeLoaded)
        await releaseMetadata.signal()
        await releaseHidden.signal()
        await fulfillment(of: [lifeStarted], timeout: 3)
        XCTAssertTrue(freshRangeLoaded, "The fresh calendar must be usable before Life preferences finish")
        XCTAssertTrue(model.loadedEvents.contains { $0.id == event.id })
        await releaseLife.signal()
        await startup.value
    }

    func testCancellingStartupDuringMetadataStopsEventAndPreferenceLoads() async throws {
        let started = expectation(description: "Metadata request")
        let release = AsyncTestSignal()
        let requests = StartupRequestLog()
        StartupTransport.handler = { request in
            await requests.record(request.url?.path ?? "")
            if request.url?.path.hasSuffix("/calendars") == true {
                started.fulfill()
                await release.wait()
            }
            return .init(status: 404, data: Data())
        }
        let api = MockEventsAPI()
        var rangeRequests = 0
        api.listHandler = { _ in rangeRequests += 1; return [] }
        let environment = try makeEnvironment(api: api, hidden: MockUserAPI())
        let model = NativeCalendarRootModel(environment: environment)
        let startup = Task { await model.start() }
        await fulfillment(of: [started], timeout: 3)
        startup.cancel()
        await release.signal()
        await startup.value
        XCTAssertEqual(rangeRequests, 0)
        let paths = await requests.paths
        XCTAssertFalse(paths.contains { $0.hasSuffix("/life-preferences") })
    }

    private func makeEnvironment(api: MockEventsAPI, hidden: MockUserAPI) throws -> NativeCalendarEnvironment {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StartupTransport.self]
        let frontToken = Data(#"{"uid":"startup-user"}"#.utf8).base64EncodedString()
        return try NativeCalendarEnvironment(appURL: URL(string: "https://compass.invalid")!,
            inMemoryDatabase: true,
            sessionStore: MemorySessionStore(tokens: SessionTokens(accessToken: "test", refreshToken: "test", frontToken: frontToken)),
            eventsAPI: api, repositorySource: .remote, urlSession: URLSession(configuration: configuration), hiddenEventsRemoteClient: hidden)
    }
}

private final class StartupTransport: URLProtocol, @unchecked Sendable {
    struct Response: Sendable { let status: Int; let data: Data }
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) async -> Response)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        Task {
            let response = await handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private actor StartupRequestLog {
    private(set) var paths: [String] = []
    func record(_ path: String) { paths.append(path) }
}
