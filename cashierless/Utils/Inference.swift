//
//  Inference.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import CoreML
import Vision
import CoreGraphics
import Foundation
import CoreVideo

// MARK: - InferenceEngine

final class InferenceEngine {

    // MARK: - Config
    let confidenceThreshold: Float  = 0.55
    let iouThreshold:        Float  = 0.30
    private let numClasses          = 12

    // MARK: - State
    private var visionModel:   VNCoreMLModel?
    private var request:       VNCoreMLRequest?
    private let tracker        = BoTSORTTracker()
    private var lastPixelBuffer: CVPixelBuffer?

    private(set) var isModelLoaded = false

    var onDetections:  (([DetectionResult]) -> Void)?
    var onModelLoaded: (() -> Void)?

    init() { loadModel() }

    // MARK: - Load Model

    private func loadModel() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let modelURL: URL?
            if let url = Bundle.main.url(forResource: "best", withExtension: "mlmodelc") {
                print("[InferenceEngine] ✅ Found best.mlmodelc")
                modelURL = url
            } else if let url = Bundle.main.url(forResource: "best", withExtension: "mlpackage") {
                print("[InferenceEngine] ✅ Found best.mlpackage")
                modelURL = url
            } else {
                print("[InferenceEngine] ❌ Model tidak ditemukan")
                return
            }

            guard let url = modelURL else { return }

            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                let mlModel = try MLModel(contentsOf: url, configuration: config)
                let desc    = mlModel.modelDescription
                print("[InferenceEngine] inputs:  \(desc.inputDescriptionsByName.keys)")
                print("[InferenceEngine] outputs: \(desc.outputDescriptionsByName.keys)")

                let vnModel = try VNCoreMLModel(for: mlModel)
                let req = VNCoreMLRequest(model: vnModel) { [weak self] req, err in
                    if let err { print("[InferenceEngine] Vision error: \(err)"); return }
                    self?.handleResults(request: req)
                }
                req.imageCropAndScaleOption = .scaleFill

                DispatchQueue.main.async {
                    self.visionModel   = vnModel
                    self.request       = req
                    self.isModelLoaded = true
                    self.onModelLoaded?()
                    print("[InferenceEngine] ✅ Model loaded")
                }
            } catch {
                print("[InferenceEngine] ❌ Load error: \(error)")
            }
        }
    }

    // MARK: - Run

    func run(on pixelBuffer: CVPixelBuffer) {
        guard let request else { return }
        lastPixelBuffer = pixelBuffer
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        DispatchQueue.global(qos: .userInteractive).async {
            do { try handler.perform([request]) }
            catch { print("[InferenceEngine] Perform error: \(error)") }
        }
    }

    // MARK: - Handle Results

    private func handleResults(request: VNRequest) {
        guard let results = request.results, !results.isEmpty else {
            let smoothed = tracker.update(detections: [], pixelBuffer: lastPixelBuffer)
            DispatchQueue.main.async { self.onDetections?(smoothed) }
            return
        }

        var newDetections: [DetectionResult] = []

        if let observations = results as? [VNRecognizedObjectObservation] {
            for obs in observations {
                guard let top = obs.labels.first, top.confidence >= confidenceThreshold else { continue }
                let cls       = classIndexFromLabel(top.identifier)
                let bb        = obs.boundingBox
                let converted = CGRect(x: bb.minX, y: 1.0 - bb.maxY, width: bb.width, height: bb.height)
                newDetections.append(DetectionResult(classIndex: cls, confidence: top.confidence, boundingBox: converted))
            }
        } else if let observations = results as? [VNCoreMLFeatureValueObservation] {
            newDetections = parseRawOutput(observations)
        }

        let afterNMS = applyNMS(detections: newDetections)
        let tracked  = tracker.update(detections: afterNMS, pixelBuffer: lastPixelBuffer)
        DispatchQueue.main.async { self.onDetections?(tracked) }
    }

    // MARK: - Raw Tensor Parser

    private func parseRawOutput(_ observations: [VNCoreMLFeatureValueObservation]) -> [DetectionResult] {
        guard let obs        = observations.first,
              let multiArray = obs.featureValue.multiArrayValue else { return [] }

        let shape     = multiArray.shape.map { $0.intValue }
        let featCount = numClasses + 4
        let anchors:    Int
        let transposed: Bool

        if shape.count == 3 {
            if shape[1] == featCount       { anchors = shape[2]; transposed = false }
            else if shape[2] == featCount  { anchors = shape[1]; transposed = true  }
            else { print("[InferenceEngine] ⚠️ Unexpected shape: \(shape)"); return [] }
        } else if shape.count == 2 {
            if shape[0] == featCount { anchors = shape[1]; transposed = false }
            else                     { anchors = shape[0]; transposed = true  }
        } else {
            print("[InferenceEngine] ⚠️ Cannot handle shape: \(shape)")
            return []
        }

        var results = [DetectionResult]()
        for i in 0..<anchors {
            func val(_ f: Int) -> Float {
                let idx = transposed ? i * featCount + f : f * anchors + i
                return multiArray[idx].floatValue
            }
            let cx = val(0), cy = val(1), w = val(2), h = val(3)
            var maxConf: Float = 0; var maxClass = 0
            for c in 0..<numClasses {
                let conf = val(4 + c)
                if conf > maxConf { maxConf = conf; maxClass = c }
            }
            guard maxConf >= confidenceThreshold else { continue }
            let x  = CGFloat((cx - w / 2) / 640)
            let y  = CGFloat((cy - h / 2) / 640)
            let bw = CGFloat(w / 640)
            let bh = CGFloat(h / 640)
            guard bw > 0.02, bh > 0.02, bw < 0.95, bh < 0.95 else { continue }
            guard x >= -0.1, y >= -0.1 else { continue }
            results.append(DetectionResult(classIndex: maxClass, confidence: maxConf,
                                           boundingBox: CGRect(x: x, y: y, width: bw, height: bh)))
        }
        return results
    }

    // MARK: - NMS per class

    private func applyNMS(detections: [DetectionResult]) -> [DetectionResult] {
        let grouped = Dictionary(grouping: detections) { $0.classIndex }
        var result  = [DetectionResult]()
        for (_, cls) in grouped {
            let sorted     = cls.sorted { $0.confidence > $1.confidence }
            var suppressed = [Bool](repeating: false, count: sorted.count)
            for i in 0..<sorted.count {
                guard !suppressed[i] else { continue }
                result.append(sorted[i])
                for j in (i + 1)..<sorted.count {
                    if iou(sorted[i].boundingBox, sorted[j].boundingBox) > CGFloat(iouThreshold) {
                        suppressed[j] = true
                    }
                }
            }
        }
        return result
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull else { return 0 }
        let iA = inter.width * inter.height
        let uA = a.width * a.height + b.width * b.height - iA
        return uA > 0 ? iA / uA : 0
    }

    private func classIndexFromLabel(_ label: String) -> Int {
        if let idx = Int(label) { return idx }
        for (idx, product) in ProductDatabase.products {
            if product.name.lowercased() == label.lowercased() { return idx }
        }
        return 0
    }
}
