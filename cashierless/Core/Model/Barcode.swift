//
//  Barcode.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import AVFoundation
import Foundation
import Combine

// MARK: - BarcodeEngine

final class BarcodeEngine: NSObject, ObservableObject {

    @Published var isRunning:  Bool = false
    @Published var error:      CameraError? = nil
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    let session = AVCaptureSession()

    private let sessionQueue    = DispatchQueue(label: "com.cashierless.barcode.session", qos: .userInitiated)
    private var metadataOutput  = AVCaptureMetadataOutput()
    private var captureDevice:  AVCaptureDevice?
    private var isConfigured    = false
    private var sessionStartTime: Date = .distantPast

    private var rotationCoordinator:     AVCaptureDevice.RotationCoordinator?
    private var previewRotationObserver: NSKeyValueObservation?

    private var lastScannedValue: String = ""
    private var lastScannedTime:  Date   = .distantPast
    private let cooldownSeconds: TimeInterval = 1.5
    private let warmupSeconds:   TimeInterval = 2.0

    private let supportedTypes: [AVMetadataObject.ObjectType] = [
        .ean13, .ean8, .upce, .code128, .code39, .qr, .itf14
    ]

    var onScan: ((BarcodeResult) -> Void)?

    override init() {
        super.init()
        // Configure langsung saat init agar previewLayer siap
        // sebelum view pertama kali muncul
        setupSession()
    }

    deinit { previewRotationObserver?.invalidate() }

    // MARK: - Setup

    private func setupSession() {
        guard !isConfigured else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            buildSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.buildSession() }
                else { DispatchQueue.main.async { self?.error = .permissionDenied } }
            }
        default:
            DispatchQueue.main.async { self.error = .permissionDenied }
        }
    }

    private func buildSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }

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
            self.captureDevice = device

            try? device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()

            guard self.session.canAddOutput(self.metadataOutput) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.error = .outputSetupFailed }
                return
            }
            self.session.addOutput(self.metadataOutput)
            self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            let available = self.metadataOutput.availableMetadataObjectTypes
            self.metadataOutput.metadataObjectTypes = self.supportedTypes.filter { available.contains($0) }
            self.metadataOutput.rectOfInterest = CGRect(x: 0.25, y: 0.15, width: 0.5, height: 0.7)

            let layer = AVCaptureVideoPreviewLayer(session: self.session)
            layer.videoGravity = .resizeAspectFill

            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
            self.rotationCoordinator = coordinator
            self.applyRotation(coordinator, to: layer)
            self.previewRotationObserver = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self, weak layer] c, _ in
                guard let l = layer else { return }
                DispatchQueue.main.async { self?.applyRotation(c, to: l) }
            }

            self.session.commitConfiguration()
            self.isConfigured = true

            DispatchQueue.main.async { self.previewLayer = layer }
        }
    }

    private func applyRotation(_ c: AVCaptureDevice.RotationCoordinator, to layer: AVCaptureVideoPreviewLayer) {
        guard let conn = layer.connection else { return }
        let angle = c.videoRotationAngleForHorizonLevelPreview
        if conn.isVideoRotationAngleSupported(angle) { conn.videoRotationAngle = angle }
    }

    // MARK: - Start / Stop

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Re-attach delegate kalau sebelumnya dilepas setelah scan
            if self.metadataOutput.metadataObjectsCallbackQueue == nil {
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
                self.sessionStartTime = Date()
            }
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
        guard let device = captureDevice ?? AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}

// MARK: - Delegate

extension BarcodeEngine: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(sessionStartTime) > warmupSeconds else { return }

        for metadata in metadataObjects {
            guard
                let readable = metadata as? AVMetadataMachineReadableCodeObject,
                let value    = readable.stringValue,
                !value.isEmpty,
                !value.hasPrefix("(")
            else { continue }

            if value == lastScannedValue,
               now.timeIntervalSince(lastScannedTime) < cooldownSeconds { continue }

            lastScannedValue = value
            lastScannedTime  = now

            let symbology = readable.type.rawValue
                .replacingOccurrences(of: "org.gs1.", with: "")
                .replacingOccurrences(of: "com.apple.", with: "")
                .uppercased()

            // Langsung disable delegate setelah 1 scan berhasil
            // mencegah scan berulang selama ViewModel masih proses
            metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)

            onScan?(BarcodeResult(value: value, symbology: symbology))
            return
        }
    }
}
