//
//  ReID.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import CoreML
import UIKit
import Accelerate
import CoreVideo
import CoreImage

// MARK: - ReIDEmbedder
// Port dari c2 — OSNet x1_0 CoreML + HSV fallback
// Dipakai oleh InferenceEngine untuk stabilkan track via cosine similarity

final class ReIDEmbedder {

    static let shared = ReIDEmbedder()

    private var mlModel:      MLModel?
    private var isUsingCoreML = false
    private let ciContext      = CIContext()

    private init() { loadModel() }

    // MARK: - Load

    private func loadModel() {
        guard
            let url = Bundle.main.url(forResource: "osnet_x1_0", withExtension: "mlpackage")
                   ?? Bundle.main.url(forResource: "osnet_x1_0", withExtension: "mlmodelc")
        else {
            print("[ReIDEmbedder] ℹ️ osnet_x1_0 tidak ditemukan → HSV fallback")
            return
        }
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            mlModel       = try MLModel(contentsOf: url, configuration: cfg)
            isUsingCoreML = true
            print("[ReIDEmbedder] ✅ OSNet x1_0 loaded. Dim: \(ReIDConfig.embeddingDim)")
        } catch {
            print("[ReIDEmbedder] ⚠️ Gagal load: \(error) → HSV fallback")
        }
    }

    // MARK: - Embed

    func embed(pixelBuffer: CVPixelBuffer, bbox: CGRect) -> [Float] {
        guard let crop = cropRegion(from: pixelBuffer, bbox: bbox) else {
            return [Float](repeating: 0, count: ReIDConfig.embeddingDim)
        }
        return embed(image: crop)
    }

    /// Interface yang dipakai BoTSORTTracker — sama dengan retailapp2
    func embed(image: UIImage) -> [Float] {
        if isUsingCoreML, let model = mlModel {
            return embedWithCoreML(image: image, model: model) ?? embedWithHSV(image: image)
        }
        return embedWithHSV(image: image)
    }

    // MARK: - CoreML path

    private func embedWithCoreML(image: UIImage, model: MLModel) -> [Float]? {
        let size = CGSize(width: ReIDConfig.inputSize, height: ReIDConfig.inputSize)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let cgImage = resized?.cgImage else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault,
                            ReIDConfig.inputSize, ReIDConfig.inputSize,
                            kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: ReIDConfig.inputSize, height: ReIDConfig.inputSize,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        ctx?.draw(cgImage, in: CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(pb, [])

        guard
            let feat = try? MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pb)]),
            let out   = try? model.prediction(from: feat)
        else { return nil }

        // Cari output key secara dinamis — tidak hardcode "embedding"
        // karena nama bisa beda tiap model (e.g. "var_2215", "embedding", "output")
        let outputKey = out.featureNames.first ?? "embedding"
        guard
            let val = out.featureValue(for: outputKey),
            let arr = val.multiArrayValue
        else { return nil }

        print("[ReIDEmbedder] output key: \(outputKey), shape: \(arr.shape)")

        let count  = min(arr.count, ReIDConfig.embeddingDim)
        var result = [Float](repeating: 0, count: ReIDConfig.embeddingDim)
        for i in 0..<count { result[i] = arr[i].floatValue }
        return l2Normalize(result)
    }

    // MARK: - HSV fallback

    private func embedWithHSV(image: UIImage) -> [Float] {
        let bins = 32
        let size = CGSize(width: 64, height: 64)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard
            let cg   = resized?.cgImage,
            let data = cg.dataProvider?.data,
            let ptr  = CFDataGetBytePtr(data)
        else { return [Float](repeating: 0, count: ReIDConfig.embeddingDim) }

        let bpp = cg.bitsPerPixel / 8
        let row = cg.bytesPerRow
        var h = [Float](repeating: 0, count: bins)
        var s = [Float](repeating: 0, count: bins)
        var v = [Float](repeating: 0, count: bins)
        var total: Float = 0

        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let off = y * row + x * bpp
                let r   = Float(ptr[off]) / 255
                let g   = Float(ptr[off+1]) / 255
                let b   = Float(ptr[off+2]) / 255
                let (hh, ss, vv) = rgbToHSV(r: r, g: g, b: b)
                h[min(Int(hh * Float(bins)), bins-1)] += 1
                s[min(Int(ss * Float(bins)), bins-1)] += 1
                v[min(Int(vv * Float(bins)), bins-1)] += 1
                total += 1
            }
        }
        if total > 0 {
            for i in 0..<bins { h[i] /= total; s[i] /= total; v[i] /= total }
        }

        var combined = h + s + v   // 96 dims
        let dim = ReIDConfig.embeddingDim
        if combined.count < dim {
            combined += [Float](repeating: 0, count: dim - combined.count)
        } else if combined.count > dim {
            combined = Array(combined.prefix(dim))
        }
        return l2Normalize(combined)
    }

    // MARK: - Helpers

    func cropRegion(from pixelBuffer: CVPixelBuffer, bbox: CGRect) -> UIImage? {
        let pw   = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let ph   = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let crop = CGRect(
            x:      bbox.minX * pw,
            y:      bbox.minY * ph,
            width:  bbox.width  * pw,
            height: bbox.height * ph
        ).integral
        let bounds = CGRect(x: 0, y: 0, width: pw, height: ph)
        let safe   = crop.intersection(bounds)
        guard !safe.isNull, safe.width > 0, safe.height > 0 else { return nil }

        let ci = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: safe)
        guard let cg = ciContext.createCGImage(ci, from: safe) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0; var na: Float = 0; var nb: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot,   vDSP_Length(a.count))
        vDSP_svesq(a, 1, &na,           vDSP_Length(a.count))
        vDSP_svesq(b, 1, &nb,           vDSP_Length(b.count))
        let denom = sqrt(na) * sqrt(nb)
        guard denom > 1e-8 else { return 0 }
        return Double(dot / denom)
    }

    func l2Normalize(_ v: [Float]) -> [Float] {
        var sq: Float = 0
        vDSP_svesq(v, 1, &sq, vDSP_Length(v.count))
        let norm = sqrt(sq)
        guard norm > 1e-8 else { return v }
        var r = v; var s = Float(1.0 / norm)
        vDSP_vsmul(v, 1, &s, &r, 1, vDSP_Length(v.count))
        return r
    }

    private func rgbToHSV(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
        let mx = max(r, g, b); let mn = min(r, g, b); let d = mx - mn
        var h: Float = 0
        if d > 0 {
            if      mx == r { h = (g - b) / d }
            else if mx == g { h = 2 + (b - r) / d }
            else            { h = 4 + (r - g) / d }
            h /= 6; if h < 0 { h += 1 }
        }
        return (h, mx > 0 ? d / mx : 0, mx)
    }
}

// MARK: - ReID Config

enum ReIDConfig {
    static let embeddingDim:  Int    = 512
    static let inputSize:     Int    = 128
    static let emaAlpha:      Float  = 0.4    // embedding EMA update speed
    static let simThreshold:  Double = 0.55   // cosine similarity threshold untuk rescue match
    static let iouWeight:     Double = 0.5    // bobot IoU dalam cost matrix
    static let reidWeight:    Double = 0.5    // bobot ReID dalam cost matrix
}
