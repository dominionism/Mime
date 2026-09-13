/// A curated hand pose that Mime recognizes.
///
/// Open palm is reserved for waking Mime and can never be assigned an action. The other four are command poses.
enum GestureID: String, CaseIterable, Sendable {
    case openPalm
    case fist
    case thumbsUp
    case vSign
    case indexPoint

    /// The poses that can trigger a command once Mime is awake.
    static let commands: [GestureID] = [.fist, .thumbsUp, .vSign, .indexPoint]

    var isCommand: Bool {
        self != .openPalm
    }

    var name: String {
        switch self {
        case .openPalm: "Open palm"
        case .fist: "Fist"
        case .thumbsUp: "Thumbs-up"
        case .vSign: "V sign"
        case .indexPoint: "Pointing finger"
        }
    }

    var emoji: String {
        switch self {
        case .openPalm: "✋"
        case .fist: "✊"
        case .thumbsUp: "👍"
        case .vSign: "✌️"
        case .indexPoint: "☝️"
        }
    }
}
