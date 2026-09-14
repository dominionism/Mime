import Testing
@testable import Mime

struct GestureGateTests {
    @Test func startsListening() {
        #expect(GestureGate().phase == .listening(wakeProgress: 0))
    }

    @Test func armsOnceAClosedFistIsHeldLongEnough() {
        var driver = GateDriver()

        driver.show(.fist, samples: samplesToHold(GestureGate.wakeHold) - 1)
        #expect(driver.gate.phase.stage == .listening)

        driver.show(.fist, samples: 1)
        #expect(driver.gate.phase.stage == .armed)
    }

    @Test func reportsWakeProgressWhileTheFistIsHeld() {
        var driver = GateDriver()
        driver.show(.fist, samples: 11)

        guard case .listening(let progress) = driver.gate.phase else {
            Issue.record("Expected listening, got \(driver.gate.phase)")
            return
        }
        #expect(abs(progress - 10 * GateDriver.frame / GestureGate.wakeHold) < 1e-9)
    }

    @Test(arguments: [nil, GestureID.oneFinger])
    func anInterruptionRestartsTheWakeHold(interruption: GestureID?) {
        var driver = GateDriver()
        let almostAwake = samplesToHold(GestureGate.wakeHold) - 1

        driver.show(.fist, samples: almostAwake)
        driver.show(interruption, samples: 1)
        driver.show(.fist, samples: almostAwake)

        #expect(driver.gate.phase.stage == .listening)
    }

    @Test func aGapBetweenSamplesRestartsTheHold() {
        var gate = GestureGate()
        let fist = recognized(.fist)

        for timestamp in [1.0, 1.25, 1.5] {
            gate.update(with: fist, at: timestamp)
        }
        gate.update(with: fist, at: 1.875)
        #expect(gate.phase.stage == .listening)

        gate.update(with: fist, at: 2.125)
        gate.update(with: fist, at: 2.375)
        #expect(gate.phase.stage == .listening)

        gate.update(with: fist, at: 2.625)
        #expect(gate.phase.stage == .armed)
    }

    @Test func aBackwardTimestampResetsAnArmedGate() {
        var gate = GestureGate()
        let fist = recognized(.fist)
        let one = recognized(.oneFinger)

        for index in 0...20 {
            gate.update(with: fist, at: 100 + Double(index) * GateDriver.frame)
        }
        #expect(gate.phase.stage == .armed)

        // A new capture clock starts at zero. The old armed deadline must not survive it.
        gate.update(with: one, at: 0)
        for index in 1...20 {
            gate.update(with: one, at: Double(index) * GateDriver.frame)
        }

        #expect(gate.phase.stage == .listening)
    }

    @Test func ignoresCommandPosesUntilWoken() {
        var driver = GateDriver()

        let commands = driver.show(.oneFinger, samples: 96)

        #expect(commands.isEmpty)
        #expect(driver.gate.phase.stage == .listening)
    }

    @Test func quickModeAcceptsACommandOnTheFirstRecognizedFrame() {
        var gate = GestureGate(mode: .quick)

        let command = gate.update(with: recognized(.threeFingers), at: GateDriver.frame)

        #expect(command == .threeFingers)
        #expect(gate.phase.stage == .cooldown)
    }

    @Test func quickModeIgnoresTheWakeFist() {
        var gate = GestureGate(mode: .quick)

        #expect(gate.update(with: recognized(.fist), at: GateDriver.frame) == nil)
        #expect(gate.update(with: recognized(.fist), at: 2 * GateDriver.frame) == nil)
        #expect(gate.phase.stage == .listening)
        #expect(gate.update(with: recognized(.oneFinger), at: 2 + GateDriver.frame) == .oneFinger)
    }

    @Test func resettingQuickModeKeepsItsActivationMode() {
        var gate = GestureGate(mode: .quick)
        gate.reset()

        #expect(gate.mode == .quick)
        #expect(gate.phase == .listening(wakeProgress: 0))
    }

    @Test func emitsAHeldCommandExactlyOnce() {
        var driver = GateDriver()
        driver.wake()

        let early = driver.show(.oneFinger, samples: samplesToHold(GestureGate.commandHold) - 1)
        let onTime = driver.show(.oneFinger, samples: 1)
        let afterwards = driver.show(.oneFinger, samples: 96)

        #expect(early.isEmpty)
        #expect(onTime == [.oneFinger])
        #expect(afterwards.isEmpty)
        #expect(driver.gate.phase.stage == .cooldown)
    }

    @Test(arguments: GestureID.commands)
    func emitsEveryFingerCount(command: GestureID) {
        var driver = GateDriver()
        driver.wake()

        let commands = driver.show(command, samples: samplesToHold(GestureGate.commandHold))

        #expect(commands == [command])
    }

    @Test func showsTheCandidateCommandWhileItIsHeld() {
        var driver = GateDriver()
        driver.wake()
        driver.show(.threeFingers, samples: 7)

        guard case .armed(_, let candidate, let progress) = driver.gate.phase else {
            Issue.record("Expected armed, got \(driver.gate.phase)")
            return
        }
        #expect(candidate == .threeFingers)
        #expect(abs(progress - 6 * GateDriver.frame / GestureGate.commandHold) < 1e-9)
    }

    @Test func switchingFingerCountsRestartsTheCommandHold() {
        var driver = GateDriver()
        driver.wake()
        let almostHeld = samplesToHold(GestureGate.commandHold) - 1

        driver.show(.oneFinger, samples: almostHeld)
        let early = driver.show(.twoFingers, samples: almostHeld)
        let onTime = driver.show(.twoFingers, samples: 1)

        #expect(early.isEmpty)
        #expect(onTime == [.twoFingers])
    }

    @Test func aLostHandRestartsTheCommandHold() {
        var driver = GateDriver()
        driver.wake()
        let almostHeld = samplesToHold(GestureGate.commandHold) - 1

        driver.show(.oneFinger, samples: almostHeld)
        driver.show(nil, samples: 1)
        let commands = driver.show(.oneFinger, samples: almostHeld)

        #expect(commands.isEmpty)
    }

    @Test func countsDownWhileArmed() {
        var driver = GateDriver()
        driver.wake()
        driver.show(nil, samples: 32)

        #expect(driver.gate.phase == .armed(secondsLeft: 2, candidate: nil, commandProgress: 0))
    }

    @Test func armedWindowClosesAfterThreeSeconds() {
        var driver = GateDriver()
        driver.wake()

        driver.show(nil, samples: samples(in: GestureGate.armedDuration) - 1)
        #expect(driver.gate.phase.stage == .armed)

        driver.show(nil, samples: 1)
        #expect(driver.gate.phase.stage == .listening)
    }

    @Test func aCommandMustFinishBeforeTheWindowCloses() {
        var driver = GateDriver()
        driver.wake()
        driver.show(nil, samples: samples(in: GestureGate.armedDuration) - 8)

        let commands = driver.show(.oneFinger, samples: samplesToHold(GestureGate.commandHold))

        #expect(commands.isEmpty)
        #expect(driver.gate.phase.stage == .listening)
    }

    @Test func theWakeFistIsNeverACommand() {
        var driver = GateDriver()
        driver.wake()

        let commands = driver.show(.fist, samples: samples(in: GestureGate.armedDuration))

        #expect(commands.isEmpty)
        #expect(driver.gate.phase.stage == .listening)
    }

    @Test func aFistHeldPastTheWindowMustBeHeldAgainToRearm() {
        var driver = GateDriver()
        driver.wake()
        driver.show(.fist, samples: samples(in: GestureGate.armedDuration))

        driver.show(.fist, samples: samplesToHold(GestureGate.wakeHold) - 1)
        #expect(driver.gate.phase.stage == .listening)

        driver.show(.fist, samples: 1)
        #expect(driver.gate.phase.stage == .armed)
    }

    @Test func coolsDownForTwoSecondsAfterACommand() {
        var driver = GateDriver()
        driver.wake()
        driver.show(.oneFinger, samples: samplesToHold(GestureGate.commandHold))

        driver.show(nil, samples: samples(in: GestureGate.cooldownDuration) - 1)
        #expect(driver.gate.phase.stage == .cooldown)

        driver.show(nil, samples: 1)
        #expect(driver.gate.phase.stage == .listening)
    }

    @Test func keepsCoolingDownUntilThePoseIsReleased() {
        var driver = GateDriver()
        driver.wake()
        driver.show(.oneFinger, samples: samplesToHold(GestureGate.commandHold))

        driver.show(.oneFinger, samples: samples(in: 5))
        #expect(driver.gate.phase == .cooldown(command: .oneFinger, secondsLeft: 0))

        driver.show(nil, samples: samplesToHold(GestureGate.releaseHold) - 1)
        #expect(driver.gate.phase.stage == .cooldown)

        driver.show(nil, samples: 1)
        #expect(driver.gate.phase.stage == .listening)
    }

    @Test func aBriefReleaseDoesNotCount() {
        var driver = GateDriver()
        driver.wake()
        driver.show(.oneFinger, samples: samplesToHold(GestureGate.commandHold))
        driver.show(.oneFinger, samples: samples(in: GestureGate.cooldownDuration))
        let almostReleased = samplesToHold(GestureGate.releaseHold) - 1

        driver.show(nil, samples: almostReleased)
        driver.show(.oneFinger, samples: 1)
        driver.show(nil, samples: almostReleased)

        #expect(driver.gate.phase.stage == .cooldown)
    }

    @Test func aScoreJustBelowTheReleaseScoreCountsAsReleased() {
        var driver = GateDriver()
        driver.wake()
        driver.show(.oneFinger, samples: samplesToHold(GestureGate.commandHold))
        driver.show(.oneFinger, samples: samples(in: GestureGate.cooldownDuration))

        driver.feed(classification([.oneFinger: GestureGate.releaseScore]), samples: 32)
        #expect(driver.gate.phase.stage == .cooldown)

        driver.feed(
            classification([.oneFinger: GestureGate.releaseScore - 0.01]),
            samples: samplesToHold(GestureGate.releaseHold)
        )
        #expect(driver.gate.phase.stage == .listening)
    }

    @Test func anotherCommandNeedsAnotherWake() {
        var driver = GateDriver()
        driver.wake()
        driver.show(.oneFinger, samples: samplesToHold(GestureGate.commandHold))
        driver.show(nil, samples: samples(in: GestureGate.cooldownDuration))

        let withoutWaking = driver.show(.twoFingers, samples: 64)
        driver.wake()
        let afterWaking = driver.show(.twoFingers, samples: samplesToHold(GestureGate.commandHold))

        #expect(withoutWaking.isEmpty)
        #expect(afterWaking == [.twoFingers])
    }

    @Test func aFistRaisedDuringTheCooldownMustBeHeldAgain() {
        var driver = GateDriver()
        driver.wake()
        driver.show(.oneFinger, samples: samplesToHold(GestureGate.commandHold))

        driver.show(.fist, samples: samples(in: GestureGate.cooldownDuration))
        #expect(driver.gate.phase.stage == .listening)

        driver.show(.fist, samples: samplesToHold(GestureGate.wakeHold) - 1)
        #expect(driver.gate.phase.stage == .listening)

        driver.show(.fist, samples: 1)
        #expect(driver.gate.phase.stage == .armed)
    }

    @Test func resetReturnsToListening() {
        var driver = GateDriver()
        driver.wake()
        var gate = driver.gate

        gate.reset()

        #expect(gate.phase == .listening(wakeProgress: 0))
    }
}

private enum Stage {
    case listening, armed, cooldown
}

private extension GestureGatePhase {
    var stage: Stage {
        switch self {
        case .listening: .listening
        case .armed: .armed
        case .cooldown: .cooldown
        }
    }
}

/// Feeds a gate samples 1/32 of a second apart, a spacing whose timestamps are exact in binary.
private struct GateDriver {
    static let frame = 1.0 / 32

    private(set) var gate = GestureGate()
    private var sampleCount = 0

    @discardableResult
    mutating func feed(_ classification: PoseClassification?, samples count: Int) -> [GestureID] {
        var commands: [GestureID] = []
        for _ in 0..<count {
            sampleCount += 1
            if let command = gate.update(with: classification, at: Double(sampleCount) * Self.frame) {
                commands.append(command)
            }
        }
        return commands
    }

    @discardableResult
    mutating func show(_ gesture: GestureID?, samples count: Int) -> [GestureID] {
        feed(gesture.map(recognized), samples: count)
    }

    mutating func wake() {
        show(.fist, samples: samplesToHold(GestureGate.wakeHold))
    }
}

private func samplesToHold(_ seconds: Double) -> Int {
    samples(in: seconds) + 1
}

private func samples(in seconds: Double) -> Int {
    Int((seconds / GateDriver.frame).rounded(.up))
}

private func recognized(_ gesture: GestureID) -> PoseClassification {
    classification([gesture: 1])
}

private func classification(_ scores: [GestureID: Double]) -> PoseClassification {
    PoseClassification(scores: scores, pose: CuratedGestureClassifier.recognizedPose(in: scores))
}
