//
//  CameraManager.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//
import AVFoundation
import Foundation
import Combine

// MARK: - CameraManager

final class CameraManager: NSObject, ObservableObject {

    @Published var isRunning:         Bool = false
    @Published var permissionGranted: Bool = false
    @Published var error:             CameraError? = nil

    let session = AVCaptureSession()
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    private let videoOutput    = AVCaptureVideoDataOutput()
    private let sessionQueue   = DispatchQueue(label: "com.cashierless.camera.session",   qos: .userInitiated)
    private let inferenceQueue = DispatchQueue(label: "com.cashierless.camera.inference", qos: .userInteractive)

    private var rotationCoordinator:     AVCaptureDevice.RotationCoordinator?
    private var previewRotationObserver: NSKeyValueObservation?
    private var captureRotationObserver: NSKeyValueObservation?

    private var frameCounter = 0
    private let frameSkip    = 2
    private var isConfigured = false

    var onFrame: ((CVPixelBuffer) -> Void)?

    override init() {
        super.init()
        checkPermission()
    }

    deinit {
        previewRotationObserver?.invalidate()
        captureRotationObserver?.invalidate()
    }

    // MARK: - Permission

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    if granted { self?.configure() }
                    else { self?.error = .permissionDenied }
                }
            }
        default:
            DispatchQueue.main.async { self.error = .permissionDenied }
        }
    }

    // MARK: - Configure

    private func configure() {
        guard !isConfigured else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1920x1080

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input  = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.error = .cameraUnavailable }
                return
            }
            self.session.addInput(input)

            try? device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus)     { device.focusMode     = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()

            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.inferenceQueue)

            guard self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.error = .outputSetupFailed }
                return
            }
            self.session.addOutput(self.videoOutput)

            let layer = AVCaptureVideoPreviewLayer(session: self.session)
            layer.videoGravity = .resizeAspectFill
            self.setupRotation(device: device, output: self.videoOutput, previewLayer: layer)

            self.session.commitConfiguration()
            self.isConfigured = true

            DispatchQueue.main.async { self.previewLayer = layer }
        }
    }

    // MARK: - Rotation (iOS 17+)

    private func setupRotation(device: AVCaptureDevice, output: AVCaptureVideoDataOutput, previewLayer: AVCaptureVideoPreviewLayer) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        applyPreviewRotation(coordinator, to: previewLayer)
        applyCaptureRotation(coordinator, to: output)

        previewRotationObserver = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self, weak previewLayer] c, _ in
            guard let pl = previewLayer else { return }
            DispatchQueue.main.async { self?.applyPreviewRotation(c, to: pl) }
        }
        captureRotationObserver = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] c, _ in
            self?.applyCaptureRotation(c, to: output)
        }
    }

    private func applyPreviewRotation(_ c: AVCaptureDevice.RotationCoordinator, to layer: AVCaptureVideoPreviewLayer) {
        guard let conn = layer.connection else { return }
        let angle = c.videoRotationAngleForHorizonLevelPreview
        if conn.isVideoRotationAngleSupported(angle) { conn.videoRotationAngle = angle }
    }

    private func applyCaptureRotation(_ c: AVCaptureDevice.RotationCoordinator, to output: AVCaptureVideoDataOutput) {
        guard let conn = output.connection(with: .video) else { return }
        let angle = c.videoRotationAngleForHorizonLevelCapture
        if conn.isVideoRotationAngleSupported(angle) { conn.videoRotationAngle = angle }
    }

    // MARK: - Start / Stop

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
        guard frameCounter % frameSkip == 0 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}

// MARK: - CameraError

enum CameraError: LocalizedError, Equatable {
    case permissionDenied
    case cameraUnavailable
    case outputSetupFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:  return "Izin kamera diperlukan. Aktifkan di Settings."
        case .cameraUnavailable: return "Kamera tidak tersedia."
        case .outputSetupFailed: return "Gagal menyiapkan output kamera."
        }
    }
}
