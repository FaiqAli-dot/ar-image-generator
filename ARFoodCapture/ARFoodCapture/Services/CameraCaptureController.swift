import Foundation
import AVFoundation
import UIKit
import Combine

/// Camera capture with AE/AF/AWB lock once the session is ready.
@MainActor
final class CameraCaptureController: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var permissionDenied = false
    @Published var lockedSettings = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "arfood.camera.session")
    private var device: AVCaptureDevice?
    private var continuation: CheckedContinuation<UIImage, Error>?

    func configure() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var granted = status == .authorized
        if status == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else {
            permissionDenied = true
            return
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                defer {
                    self.session.commitConfiguration()
                    cont.resume()
                }

                if let existing = self.session.inputs as? [AVCaptureDeviceInput] {
                    existing.forEach { self.session.removeInput($0) }
                }
                self.session.outputs.forEach { self.session.removeOutput($0) }

                guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: cam) else { return }
                self.device = cam
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    self.photoOutput.maxPhotoQualityPrioritization = .balanced
                }
            }
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
    }

    func start() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            Task { @MainActor in self.isSessionRunning = true }
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
                self.lockedSettings = false
            }
        }
    }

    func lockExposureWhiteBalanceAndFocus() {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
                if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                }
                device.unlockForConfiguration()
                Task { @MainActor in self.lockedSettings = true }
            } catch {
                // Keep capturing even if lock fails
            }
        }
    }

    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            self.sessionQueue.async {
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraCaptureController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                continuation?.resume(throwing: error)
                continuation = nil
                return
            }
            guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
                continuation?.resume(throwing: CameraError.noImage)
                continuation = nil
                return
            }
            continuation?.resume(returning: image)
            continuation = nil
        }
    }
}

enum CameraError: LocalizedError {
    case noImage
    var errorDescription: String? { "Failed to capture photo" }
}
