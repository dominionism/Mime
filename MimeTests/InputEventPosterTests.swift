import CoreGraphics
import Testing
@testable import Mime

@MainActor
struct InputEventPosterTests {
    @Test func nextApplicationUsesCommandTab() throws {
        let poster = FakeInputEventPoster()
        try SystemActionExecutor(poster: poster).perform(.nextApplication)

        let expected: [(CGKeyCode, Bool, CGEventFlags)] = [
            (SystemActionExecutor.commandKeyCode, true, [.maskCommand]),
            (SystemActionExecutor.tabKeyCode, true, [.maskCommand]),
            (SystemActionExecutor.tabKeyCode, false, [.maskCommand]),
            (SystemActionExecutor.commandKeyCode, false, [])
        ]
        #expect(poster.events == expected)
    }

    @Test func previousApplicationUsesCommandShiftTab() throws {
        let poster = FakeInputEventPoster()
        try SystemActionExecutor(poster: poster).perform(.previousApplication)

        let expected: [(CGKeyCode, Bool, CGEventFlags)] = [
            (SystemActionExecutor.commandKeyCode, true, [.maskCommand]),
            (SystemActionExecutor.shiftKeyCode, true, [.maskCommand, .maskShift]),
            (SystemActionExecutor.tabKeyCode, true, [.maskCommand, .maskShift]),
            (SystemActionExecutor.tabKeyCode, false, [.maskCommand, .maskShift]),
            (SystemActionExecutor.shiftKeyCode, false, [.maskCommand]),
            (SystemActionExecutor.commandKeyCode, false, [])
        ]
        #expect(poster.events == expected)
    }

    @Test func closeCurrentTabUsesCommandW() throws {
        let poster = FakeInputEventPoster()
        try SystemActionExecutor(poster: poster).perform(.closeCurrentTabOrWindow)

        let expected: [(CGKeyCode, Bool, CGEventFlags)] = [
            (SystemActionExecutor.commandKeyCode, true, [.maskCommand]),
            (SystemActionExecutor.wKeyCode, true, [.maskCommand]),
            (SystemActionExecutor.wKeyCode, false, [.maskCommand]),
            (SystemActionExecutor.commandKeyCode, false, [])
        ]
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
    private(set) var events: [(CGKeyCode, Bool, CGEventFlags)] = []

    func postKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        events.append((keyCode, true, flags))
        events.append((keyCode, false, flags))
    }

    func postKeyChord(_ chord: [(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags)]) throws {
        events.append(contentsOf: chord.map { ($0.keyCode, $0.keyDown, $0.flags) })
    }
}

private func == (lhs: [(CGKeyCode, Bool, CGEventFlags)], rhs: [(CGKeyCode, Bool, CGEventFlags)]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
        $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1 && $0.0.2 == $0.1.2
    }
}
