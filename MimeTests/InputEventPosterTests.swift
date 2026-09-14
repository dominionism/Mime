import CoreGraphics
import Testing
@testable import Mime

@MainActor
struct InputEventPosterTests {
    @Test func nextApplicationUsesCommandTab() throws {
        let poster = FakeInputEventPoster()
        try SystemActionExecutor(poster: poster).perform(.nextApplication)

        let expected: [(CGKeyCode, CGEventFlags)] = [(SystemActionExecutor.tabKeyCode, [.maskCommand])]
        #expect(poster.events == expected)
    }

    @Test func previousApplicationUsesCommandShiftTab() throws {
        let poster = FakeInputEventPoster()
        try SystemActionExecutor(poster: poster).perform(.previousApplication)

        let expected: [(CGKeyCode, CGEventFlags)] = [(SystemActionExecutor.tabKeyCode, [.maskCommand, .maskShift])]
        #expect(poster.events == expected)
    }

    @Test func closeCurrentTabUsesCommandW() throws {
        let poster = FakeInputEventPoster()
        try SystemActionExecutor(poster: poster).perform(.closeCurrentTabOrWindow)

        let expected: [(CGKeyCode, CGEventFlags)] = [(SystemActionExecutor.wKeyCode, [.maskCommand])]
        #expect(poster.events == expected)
    }

    @Test func systemPosterRefusesWithoutAccessibilityTrust() {
        let poster = SystemInputEventPoster(isAccessibilityTrusted: { false })

        #expect(throws: InputEventError.accessibilityNotAllowed) {
            try poster.postKeyPress(keyCode: 48, flags: [.maskCommand])
        }
    }

    @Test func systemGestureActionsAreDistinct() {
        #expect(SystemGestureAction.nextApplication != .previousApplication)
        #expect(SystemGestureAction.closeCurrentTabOrWindow != .nextApplication)
    }
}

@MainActor
private final class FakeInputEventPoster: InputEventPosting {
    private(set) var events: [(CGKeyCode, CGEventFlags)] = []

    func postKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        events.append((keyCode, flags))
    }
}

private func == (lhs: [(CGKeyCode, CGEventFlags)], rhs: [(CGKeyCode, CGEventFlags)]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1 }
}
