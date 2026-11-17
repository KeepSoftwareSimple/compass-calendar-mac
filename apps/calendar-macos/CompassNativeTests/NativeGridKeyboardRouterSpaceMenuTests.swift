import AppKit
import CompassData
import CompassKit
import XCTest

@MainActor
final class NativeGridKeyboardRouterSpaceMenuTests: XCTestCase {
    func testSpaceOpensEventMenuOnFocusedSavedEvent() async throws {
        let (model, router) = try await makeRouter()
        model.focusEvent(eventId: "demo-morning-standup")
        XCTAssertFalse(model.eventMenuStore.isOpen)

        XCTAssertTrue(router.handleKeyDown(try spaceKeyDown()))
        XCTAssertTrue(model.eventMenuStore.isOpen)
    }

    func testEnterOpensFormWithoutOpeningEventMenu() async throws {
        let (model, router) = try await makeRouter()
        model.focusEvent(eventId: "demo-morning-standup")
        XCTAssertFalse(model.eventMenuStore.isOpen)

        XCTAssertTrue(router.handleKeyDown(try enterKeyDown()))
        XCTAssertFalse(model.eventMenuStore.isOpen)
        XCTAssertTrue(model.isEventFormVisible)
    }

    func testSpaceOnPastePlaceDraftIsSwallowedWithoutMenu() async throws {
        let (model, router) = try await makeRouter()
        let event = try XCTUnwrap(model.loadedEvents.first)
        model.focusEvent(eventId: event.id.rawValue)

        XCTAssertTrue(router.handleKeyDown(try key("c", code: 8, modifiers: .command)))
        XCTAssertEqual(model.draftStore.status.activity, .pastePlace)

        XCTAssertTrue(router.handleKeyDown(try spaceKeyDown()))
        XCTAssertFalse(model.eventMenuStore.isOpen)
    }

    private func makeRouter() async throws -> (NativeCalendarRootModel, NativeGridKeyboardRouter) {
        _ = NSApplication.shared
        let model = NativeCalendarRootModel(
            environment: try NativeCalendarEnvironment(inMemoryDatabase: true),
            demoPresentation: try DemoSeedFixture.load())
        await model.start()
        model.viewStore.view = .week
        let router = NativeGridKeyboardRouter(model: model, registry: try ShortcutRegistry())
        router.dispatcher.pushScope(.grid)
        return (model, router)
    }

    private func spaceKeyDown() throws -> NSEvent {
        try key(" ", code: 49)
    }

    private func enterKeyDown() throws -> NSEvent {
        try key("\r", code: 36)
    }

    private func key(
        _ characters: String,
        code: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code))
    }
}