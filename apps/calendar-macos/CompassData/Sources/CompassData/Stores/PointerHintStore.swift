import CompassKit
import Foundation

@MainActor
@Observable
public final class PointerHintStore {
    public private(set) var isVisible = false
    public private(set) var attempt: PointerHintAttempt?
    /// Event title for UI tests while the event-card pointer hint is visible.
    public private(set) var focusedGridEventLabel: String?

    private var shownIntents: Set<PointerClickTarget> = []
    private var sessionCount = 0
    private let sessionCap = 3
    /// Web `pointer-hint.store` `HINT_VISIBLE_MS` (pulse-driven auto-hide).
    private let autoHideDelay: Duration = .milliseconds(2500)
    private let sleep: @Sendable (Duration) async throws -> Void
    private var hideTask: Task<Void, Never>?

    public convenience init() {
        self.init(sleep: { try await Task.sleep(for: $0) })
    }

    init(sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.sleep = sleep
    }

    public func pulse(
        target: PointerClickTarget,
        registry: ShortcutRegistry,
        slotClick: GridPointerSlotClickContext? = nil,
        focusedGridEventLabel: String? = nil
    ) {
        guard sessionCount < sessionCap else { return }
        guard !shownIntents.contains(target) else { return }
        guard let attempt = PointerHintMessaging.attempt(
            for: target,
            registry: registry,
            slotClick: slotClick
        ) else { return }
        shownIntents.insert(target)
        sessionCount += 1
        self.attempt = attempt
        self.focusedGridEventLabel = target == .eventCard ? focusedGridEventLabel : nil
        isVisible = true
        scheduleAutoHide()
    }

    public func updateFocusedGridEventLabel(_ label: String?) {
        focusedGridEventLabel = label
    }

    public func hide() {
        hideTask?.cancel()
        hideTask = nil
        isVisible = false
        focusedGridEventLabel = nil
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        let sleep = self.sleep
        let delay = autoHideDelay
        hideTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch { return }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }
}
