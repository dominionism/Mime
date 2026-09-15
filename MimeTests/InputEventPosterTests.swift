import CoreGraphics
import Testing
@testable import Mime

@MainActor
struct InputEventPosterTests {
    @Test func swipeActionsCycleAppsWithoutPostingKeyboardEvents() throws {
        let poster = FakeInputEventPoster()
        let workspace = FakeApplicationSwitchWorkspace()
        let executor = SystemActionExecutor(poster: poster, applicationCycler: RunningApplicationCycler(workspace: workspace))
        try executor.perform(.nextApplication)
        try executor.perform(.nextApplication)
        try executor.perform(.previousApplication)
        #expect(workspace.activations == [2, 3, 2])
        #expect(poster.events.isEmpty)
    }

    @Test func repeatedSwipesTraverseAndWrapAllRunningApps() throws {
        let workspace = FakeApplicationSwitchWorkspace()
        let cycler = RunningApplicationCycler(workspace: workspace)
        for _ in 0..<4 { try cycler.cycle(.next) }
        #expect(workspace.activations == [2, 3, 1, 2])
    }

    @Test func reversingDirectionRetracesTheStableOrder() throws {
        let workspace = FakeApplicationSwitchWorkspace()
        let cycler = RunningApplicationCycler(workspace: workspace)
        try cycler.cycle(.next)
        workspace.applicationProcessIdentifiers = [3, 2, 1]
        try cycler.cycle(.previous)
        #expect(workspace.activations == [2, 1])
    }

    @Test func appLaunchesAndExitsUpdateTheCycle() throws {
        let workspace = FakeApplicationSwitchWorkspace()
        let cycler = RunningApplicationCycler(workspace: workspace)
        try cycler.cycle(.next)
        workspace.applicationProcessIdentifiers = [1, 2, 4]
        try cycler.cycle(.next)
        try cycler.cycle(.next)
        #expect(workspace.activations == [2, 4, 1])
    }

    @Test func fastSwipesContinueFromPendingActivation() throws {
        let workspace = FakeApplicationSwitchWorkspace()
        workspace.updatesFrontmostOnActivation = false
        let cycler = RunningApplicationCycler(workspace: workspace)
        try cycler.cycle(.next)
        try cycler.cycle(.next)
        #expect(workspace.activations == [2, 3])
    }

    @Test func delayedIntermediateActivationDoesNotSwallowTheNextSwipe() throws {
        let workspace = FakeApplicationSwitchWorkspace()
        workspace.updatesFrontmostOnActivation = false
        let cycler = RunningApplicationCycler(workspace: workspace)
        try cycler.cycle(.next)
        try cycler.cycle(.next)
        workspace.frontmostProcessIdentifier = 2
        try cycler.cycle(.next)
        #expect(workspace.activations == [2, 3, 1])
    }

    @Test func reversingDuringAnIntermediateActivationUsesTheLatestSelection() throws {
        let workspace = FakeApplicationSwitchWorkspace()
        workspace.updatesFrontmostOnActivation = false
        let cycler = RunningApplicationCycler(workspace: workspace)
        try cycler.cycle(.next)
        try cycler.cycle(.next)
        workspace.frontmostProcessIdentifier = 2
        try cycler.cycle(.previous)
        #expect(workspace.activations == [2, 3, 2])
    }

    @Test func expiredActivationHistoryUsesTheActualFrontmostApp() throws {
        let workspace = FakeApplicationSwitchWorkspace()
        workspace.updatesFrontmostOnActivation = false
        var timestamp = 0.0
        let cycler = RunningApplicationCycler(workspace: workspace, now: { timestamp })
        try cycler.cycle(.next)
        try cycler.cycle(.next)
        timestamp = RunningApplicationCycler.pendingActivationLifetime + 0.01
        try cycler.cycle(.next)
        #expect(workspace.activations == [2, 3, 2])
    }

    @Test func focusOutsidePendingActivationHistoryImmediatelyBecomesTheOrigin() throws {
        let workspace = FakeApplicationSwitchWorkspace()
        workspace.applicationProcessIdentifiers = [1, 2, 3, 4]
        workspace.updatesFrontmostOnActivation = false
        let cycler = RunningApplicationCycler(workspace: workspace)
        try cycler.cycle(.next)
        try cycler.cycle(.next)
        workspace.frontmostProcessIdentifier = 4
        try cycler.cycle(.next)
        #expect(workspace.activations == [2, 3, 1])
    }

    @Test func manuallyChangingFocusBecomesTheNewCycleOrigin() throws {
        let workspace = FakeApplicationSwitchWorkspace()
        let cycler = RunningApplicationCycler(workspace: workspace)
        try cycler.cycle(.next)
        workspace.frontmostProcessIdentifier = 3
        try cycler.cycle(.next)
        #expect(workspace.activations == [2, 1])
    }

    @Test func refusedActivationReportsFailureAndDoesNotAdvance() throws {
        let workspace = FakeApplicationSwitchWorkspace()
        let cycler = RunningApplicationCycler(workspace: workspace)
        workspace.acceptsActivation = false
        #expect(throws: ApplicationSwitchError.activationRefused) { try cycler.cycle(.next) }
        workspace.acceptsActivation = true
        try cycler.cycle(.next)
        #expect(workspace.activations == [2, 2])
    }

    @Test func oneAlreadyFrontmostAppDoesNotPretendToSwitch() {
        let workspace = FakeApplicationSwitchWorkspace()
        workspace.applicationProcessIdentifiers = [1]
        let cycler = RunningApplicationCycler(workspace: workspace)
        #expect(throws: ApplicationSwitchError.noOtherApplications) { try cycler.cycle(.next) }
        #expect(workspace.activations.isEmpty)
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

@MainActor
private final class FakeApplicationSwitchWorkspace: ApplicationSwitchWorkspace {
    var applicationProcessIdentifiers: [Int32] = [1, 2, 3]
    var frontmostProcessIdentifier: Int32? = 1
    var updatesFrontmostOnActivation = true
    var acceptsActivation = true
    private(set) var activations: [Int32] = []

    func activate(processIdentifier: Int32) -> Bool {
        activations.append(processIdentifier)
        if acceptsActivation && updatesFrontmostOnActivation { frontmostProcessIdentifier = processIdentifier }
        return acceptsActivation
    }
}
