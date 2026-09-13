import AVFoundation
import Testing
@testable import Mime

@MainActor
struct CameraPermissionControllerTests {
    @Test(arguments: [
        (AVAuthorizationStatus.authorized, CameraAccess.authorized),
        (.denied, .denied),
        (.restricted, .restricted),
    ])
    func returnsDecidedAccessWithoutPrompting(status: AVAuthorizationStatus, expected: CameraAccess) async {
        let prompts = PromptRecorder()
        let controller = CameraPermissionController(
            authorizationStatus: { status },
            requestSystemAccess: { prompts.record(answer: true) }
        )

        #expect(await controller.requestAccessIfNeeded() == expected)
        #expect(prompts.count == 0)
    }

    @Test(arguments: [(true, CameraAccess.authorized), (false, .denied)])
    func promptsOnceWhenAccessIsUndecided(answer: Bool, expected: CameraAccess) async {
        let prompts = PromptRecorder()
        let controller = CameraPermissionController(
            authorizationStatus: { .notDetermined },
            requestSystemAccess: { prompts.record(answer: answer) }
        )

        #expect(await controller.requestAccessIfNeeded() == expected)
        #expect(prompts.count == 1)
    }
}

@MainActor
private final class PromptRecorder {
    private(set) var count = 0

    func record(answer: Bool) -> Bool {
        count += 1
        return answer
    }
}
