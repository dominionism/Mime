/// A curated hand pose that Mime recognizes.
///
/// A closed fist is reserved for waking Mime and can never be assigned an action. The five finger-count poses are
/// commands, which keeps the vocabulary easy to remember and leaves room for custom static poses later.
enum GestureID: String, CaseIterable, Sendable {
    case fist
    case oneFinger
    case twoFingers
    case threeFingers
    case fourFingers
    case fiveFingers

    /// The poses that can trigger a command once Mime is awake.
    static let commands: [GestureID] = [.oneFinger, .twoFingers, .threeFingers, .fourFingers, .fiveFingers]

    var isWake: Bool {
        self == .fist
    }

    var isCommand: Bool {
        !isWake
    }

    var name: String {
        switch self {
        case .fist: "Closed fist"
        case .oneFinger: "One finger"
        case .twoFingers: "Two fingers"
        case .threeFingers: "Three fingers"
        case .fourFingers: "Four fingers"
        case .fiveFingers: "Five fingers"
        }
    }

    var emoji: String {
        switch self {
        case .fist: "✊"
        case .oneFinger: "☝️"
        case .twoFingers: "✌️"
        case .threeFingers: "3️⃣"
        case .fourFingers: "4️⃣"
        case .fiveFingers: "✋"
        }
    }
}
