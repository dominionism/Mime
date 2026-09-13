/// Estimates how many samples arrive per second from their timestamps.
struct FrameRateMeter {
    private var lastTimestamp: Double?
    private var averageInterval: Double?

    /// The smoothed rate in samples per second, available once two samples have arrived.
    var framesPerSecond: Double? {
        averageInterval.map { 1 / $0 }
    }

    mutating func record(_ timestamp: Double) {
        defer { self.lastTimestamp = timestamp }
        guard let lastTimestamp, timestamp > lastTimestamp else { return }

        // A moving average keeps the readout steady without storing a history of samples.
        let interval = timestamp - lastTimestamp
        averageInterval = averageInterval.map { $0 * 0.9 + interval * 0.1 } ?? interval
    }
}
