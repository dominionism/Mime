/// How Mime begins a command recognition cycle.
enum GestureActivationMode: String, CaseIterable, Codable, Equatable, Sendable {
    /// Require a closed fist before accepting a finger-count command.
    case wakeThenCommand
    /// Accept a held finger-count command directly, without the wake pose.
    case quick

    var name: String {
        switch self {
        case .wakeThenCommand: "Safe: wake then command"
        case .quick: "Quick: show fingers directly"
        }
    }

    var detail: String {
        switch self {
        case .wakeThenCommand: "Hold ✊, then hold 1–5 fingers."
        case .quick: "Show 1–5 fingers to launch immediately. Casual poses can launch apps."
        }
    }
}
