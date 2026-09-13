import AVFoundation

/// Why the camera could not start.
enum CameraCaptureError: Error, Equatable {
    case noCamera
    case cameraUnavailable
    case configurationFailed

    var message: String {
        switch self {
        case .noCamera: "No camera found"
        case .cameraUnavailable: "The camera is unavailable"
        case .configurationFailed: "The camera couldn't be started"
        }
    }
}

/// Owns Mime's single capture session and hands each camera frame to `onFrame` on a dedicated serial queue.
///
/// Session setup, start, and stop run in order on `sessionQueue`, and frames arrive only on `frameQueue`. That
/// confinement is what makes the unchecked `Sendable` conformance safe.
final class CameraCaptureService: NSObject, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.dominionism.Mime.capture.session")
    private let frameQueue = DispatchQueue(label: "com.dominionism.Mime.capture.frames", qos: .userInteractive)
    private let onFrame: (CMSampleBuffer) -> Void
    private var isConfigured = false

    init(onFrame: @escaping (CMSampleBuffer) -> Void) {
        self.onFrame = onFrame
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sessionQueue.async { [self] in
                do {
                    try configureIfNeeded()
                    if !session.isRunning {
                        session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Stops the session, which releases the camera and turns off its indicator light.
    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let camera = AVCaptureDevice.systemPreferredCamera ?? AVCaptureDevice.default(for: .video) else {
            throw CameraCaptureError.noCamera
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
            throw CameraCaptureError.cameraUnavailable
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        // Drop frames that arrive while the previous one is still being analyzed instead of queueing them.
        output.alwaysDiscardsLateVideoFrames = true
        // Keep the camera's YUV format, which Vision reads directly, instead of paying for a BGRA conversion.
        if output.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        }
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw CameraCaptureError.configurationFailed
        }
        session.addOutput(output)

        // Keep frames unmirrored so joint positions match what the camera actually sees.
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        isConfigured = true
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame(sampleBuffer)
    }
}
