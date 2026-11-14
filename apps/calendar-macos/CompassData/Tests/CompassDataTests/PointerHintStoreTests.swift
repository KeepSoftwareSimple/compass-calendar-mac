import CompassKit
import Observation
import XCTest
@testable import CompassData

@MainActor
final class PointerHintStoreTests: XCTestCase {
    func testPulseShowsHintAndHideClearsVisibility() throws {
        let store = PointerHintStore()
        let registry = try ShortcutRegistry()
        store.pulse(target: .allDaySlot, registry: registry)
        XCTAssertTrue(store.isVisible)
        XCTAssertNotNil(store.attempt)
        store.hide()
        XCTAssertFalse(store.isVisible)
        XCTAssertNil(store.focusedGridEventLabel)
    }

    func testHideCancelsScheduledAutoHide() async throws {
        let scheduled = expectation(description: "Auto-hide scheduled")
        let completed = expectation(description: "Cancelled sleeper completed")
        let release = AsyncTestSignal()
        let store = PointerHintStore(sleep: { delay in
            XCTAssertEqual(delay, .milliseconds(2500))
            scheduled.fulfill()
            await release.wait()
            XCTAssertTrue(Task.isCancelled)
            completed.fulfill()
        })
        let registry = try ShortcutRegistry()
        store.pulse(target: .allDaySlot, registry: registry)
        await fulfillment(of: [scheduled], timeout: 2.6)
        store.hide()
        await release.signal()
        await fulfillment(of: [completed], timeout: 2.6)
        XCTAssertFalse(store.isVisible)
    }

    func testAutoHideMatchesWebVisibleWindow() async throws {
        let scheduled = expectation(description: "Auto-hide scheduled")
        let hidden = expectation(description: "Hint hidden after sleeper returns")
        let release = AsyncTestSignal()
        let store = PointerHintStore(sleep: { delay in
            XCTAssertEqual(delay, .milliseconds(2500))
            scheduled.fulfill()
            await release.wait()
        })
        let registry = try ShortcutRegistry()
        store.pulse(target: .allDaySlot, registry: registry)
        XCTAssertTrue(store.isVisible)
        await fulfillment(of: [scheduled], timeout: 2.6)
        withObservationTracking {
            _ = store.isVisible
        } onChange: {
            hidden.fulfill()
        }
        await release.signal()
        await fulfillment(of: [hidden], timeout: 2.6)
        XCTAssertFalse(store.isVisible)
    }
}
