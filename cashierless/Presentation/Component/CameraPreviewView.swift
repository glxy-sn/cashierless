import SwiftUI
import AVFoundation
import UIKit

// MARK: - CameraPreviewView
// Menggunakan ObservedObject agar otomatis re-render
// saat previewLayer tersedia (async dari sessionQueue)

struct CameraPreviewView: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        Group {
            if let layer = cameraManager.previewLayer {
                PreviewLayerView(previewLayer: layer)
            } else {
                Color.black
            }
        }
    }
}

// MARK: - BarcodeCameraPreviewView

struct BarcodeCameraPreviewView: View {
    @ObservedObject var barcodeEngine: BarcodeEngine

    var body: some View {
        Group {
            if let layer = barcodeEngine.previewLayer {
                PreviewLayerView(previewLayer: layer)
            } else {
                Color.black
            }
        }
    }
}

// MARK: - PreviewLayerView (UIViewRepresentable)
// Terima layer yang sudah pasti ada — tidak perlu cek nil

struct PreviewLayerView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.setPreviewLayer(previewLayer)
    }
}

// MARK: - PreviewUIView

final class PreviewUIView: UIView {
    private var attachedLayer: AVCaptureVideoPreviewLayer?

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        // Sudah terpasang dengan layer yang sama — cukup update frame
        if attachedLayer === layer {
            layer.frame = bounds
            return
        }
        // Lepas layer lama jika ada
        attachedLayer?.removeFromSuperlayer()

        attachedLayer = layer
        layer.frame   = bounds
        self.layer.insertSublayer(layer, at: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachedLayer?.frame = bounds
    }
}

// MARK: - CameraPermissionDeniedView

struct CameraPermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(white: 0.25))
            Text("Izin Kamera Diperlukan")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
            Text("Buka Settings → Privacy → Kamera\nlalu aktifkan akses untuk aplikasi ini.")
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
            Button("Buka Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.bordered)
            .tint(Color.appGreen)
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}
