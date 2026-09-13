import SwiftUI

/// Shows what hand tracking sees as an abstract skeleton of joints and bones. It never displays camera images.
struct HandTrackingDiagnosticsView: View {
    let isActive: Bool
    let sample: HandPoseSample?
    let framesPerSecond: Double?

    var body: some View {
        let hand = isActive ? sample?.hand : nil

        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                if let hand {
                    HandSkeleton.draw(hand, in: &context, size: size)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .overlay {
                if !isActive {
                    Text("Turn on to see what Mime tracks")
                        .foregroundStyle(.secondary)
                } else if hand == nil {
                    Text("No hand in view")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(caption(for: hand))
                Spacer()
                if isActive, let framesPerSecond {
                    Text("\(Int(framesPerSecond.rounded())) fps")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func caption(for hand: DetectedHand?) -> String {
        guard let hand else {
            return "Shows joint positions only. No video is displayed or saved."
        }
        let confidence = Int((hand.confidence * 100).rounded())
        return "\(hand.chirality.label) · \(confidence)% confidence"
    }
}

/// The skeleton's bones, and how joint positions map into a view.
enum HandSkeleton {
    static let bones: [(HandJoint, HandJoint)] = [
        (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
        (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
        (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
        (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
        (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
        (.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP),
    ]

    /// Converts a joint from Vision's image space into view space, mirrored so the skeleton moves the same way
    /// your hand does.
    static func viewPoint(for position: HandJointPosition, in size: CGSize) -> CGPoint {
        CGPoint(x: (1 - position.x) * size.width, y: (1 - position.y) * size.height)
    }

    static func draw(_ hand: DetectedHand, in context: inout GraphicsContext, size: CGSize) {
        var bonePath = Path()
        for (start, end) in bones {
            guard let startPosition = hand.joints[start], let endPosition = hand.joints[end] else { continue }
            bonePath.move(to: viewPoint(for: startPosition, in: size))
            bonePath.addLine(to: viewPoint(for: endPosition, in: size))
        }
        context.stroke(bonePath, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        for position in hand.joints.values {
            let center = viewPoint(for: position, in: size)
            let dot = Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            // Fainter dots mark joints Vision is less sure about.
            context.fill(dot, with: .color(.primary.opacity(Double(position.confidence))))
        }
    }
}

private extension HandChirality {
    var label: String {
        switch self {
        case .left: "Left hand"
        case .right: "Right hand"
        case .unknown: "Hand"
        }
    }
}
