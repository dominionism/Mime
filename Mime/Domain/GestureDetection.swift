import Foundation

/// A result retained for this app session, without camera images or joint positions.
struct GestureDetection: Equatable, Sendable {
    let gesture: GestureID
    let detectedAt: Date
}

/// A dynamic gesture result retained for the current app session.
struct MotionGestureDetection: Equatable, Sendable {
    let gesture: MotionGesture
    let detectedAt: Date
}
