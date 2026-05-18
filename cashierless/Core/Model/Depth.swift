//
//  Depth.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import Foundation
import Vision

// MARK: - Product Depth Tracker
// Port langsung dari app c2 — deteksi PUT/TAKE berdasarkan perubahan
// ukuran bounding box produk (proxy depth / Z-axis).

final class ProductDepthTracker {

    // MARK: - Config
    var minOverlapRatio:      CGFloat = 0.10
    var depthChangeThreshold: CGFloat = 0.10
    var minHoldingFrames:     Int     = 3
    var maxNoOverlapFrames:   Int     = 30

    // MARK: - Callbacks
    var onAction: ((HandAction) -> Void)?
    var onDebug:  ((String, CGFloat, CGFloat, CGFloat, Bool) -> Void)?

    // MARK: - State
    private enum State {
        case idle
        case holding(peakArea: CGFloat, currentLabel: String, holdingFrames: Int)
    }

    private var state:            State   = .idle
    private var noOverlapFrames:  Int     = 0
    private var smoothedBoxArea:  CGFloat = 0
    private let emaAlpha:         CGFloat = 0.3

    // MARK: - Process

    func process(landmarks: HandLandmarks?, detections: [DetectionResult], viewSize: CGSize) {
        guard let landmarks else {
            resetState()
            onDebug?("no_hand", 0, 0, 0, false)
            return
        }
        guard let handBBox = computeHandBBox(from: landmarks) else {
            resetState()
            onDebug?("no_hand", 0, 0, 0, false)
            return
        }

        let expandedHand = handBBox.insetBy(dx: -0.08, dy: -0.08)

        var bestMatch: (detection: DetectionResult, label: String, overlapRatio: CGFloat)?
        for det in detections {
            guard let product = det.product else { continue }
            let ratio = overlapRatio(expandedHand, det.boundingBox)
            if ratio >= minOverlapRatio {
                if bestMatch == nil || ratio > bestMatch!.overlapRatio {
                    bestMatch = (det, product.name, ratio)
                }
            }
        }

        evaluate(bestMatch: bestMatch, landmarks: landmarks, viewSize: viewSize)
    }

    // MARK: - State Machine

    private func evaluate(
        bestMatch: (detection: DetectionResult, label: String, overlapRatio: CGFloat)?,
        landmarks: HandLandmarks,
        viewSize: CGSize
    ) {
        switch state {

        case .idle:
            guard let match = bestMatch else {
                noOverlapFrames += 1
                onDebug?("idle", 0, 0, 0, false)
                return
            }
            noOverlapFrames = 0
            let boxArea = match.detection.boundingBox.width * match.detection.boundingBox.height
            state = .holding(peakArea: boxArea, currentLabel: match.label, holdingFrames: 1)
            smoothedBoxArea = boxArea
            onDebug?("holding_start", boxArea, match.overlapRatio, 0, true)

        case .holding(let peakArea, let label, let holdingFrames):
            guard let match = bestMatch else {
                noOverlapFrames += 1
                if noOverlapFrames > maxNoOverlapFrames { resetState() }
                return
            }
            noOverlapFrames = 0
            let boxArea = match.detection.boundingBox.width * match.detection.boundingBox.height
            smoothedBoxArea = smoothedBoxArea == 0
                ? boxArea
                : emaAlpha * boxArea + (1 - emaAlpha) * smoothedBoxArea

            let newHoldingFrames = holdingFrames + 1
            let peakAreaRatio    = smoothedBoxArea / peakArea
            let debugPhase       = String(format: "holding(%.0f%%)", peakAreaRatio * 100)
            onDebug?(debugPhase, smoothedBoxArea, match.overlapRatio, peakAreaRatio, true)

            if newHoldingFrames >= minHoldingFrames {
                if smoothedBoxArea < peakArea * (1 - depthChangeThreshold) {
                    fire(.approachingBasket)
                    return
                } else if smoothedBoxArea > peakArea * (1 + depthChangeThreshold) {
                    fire(.leavingBasket)
                    return
                }
            }

            state = .holding(
                peakArea: max(peakArea, smoothedBoxArea),
                currentLabel: label,
                holdingFrames: newHoldingFrames
            )
        }
    }

    // MARK: - Helpers

    private func computeHandBBox(from lm: HandLandmarks) -> CGRect? {
        let pts = Array(lm.points.values)
        guard pts.count >= 3 else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in pts { minX = min(minX,p.x); maxX = max(maxX,p.x); minY = min(minY,p.y); maxY = max(maxY,p.y) }
        return CGRect(x: minX, y: 1.0 - maxY, width: maxX - minX, height: maxY - minY)
    }

    private func overlapRatio(_ hand: CGRect, _ product: CGRect) -> CGFloat {
        let inter = hand.intersection(product)
        guard !inter.isNull else { return 0 }
        let productArea = product.width * product.height
        return productArea > 0 ? (inter.width * inter.height) / productArea : 0
    }

    private func fire(_ action: HandAction) { onAction?(action); resetState() }

    private func resetState() {
        state = .idle
        noOverlapFrames = 0
        smoothedBoxArea = 0
    }

    func reset() { resetState() }
}
