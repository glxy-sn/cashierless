//
//  Depth.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import Foundation
import Vision

// MARK: - Product Depth Tracker
// Sekarang hanya dipakai untuk debug overlay (phase, boxArea, overlap, ratio).
// Logic PUT/TAKE sudah dipindah ke BasketManager berbasis Re-ID track awareness.

final class ProductDepthTracker {

    // MARK: - Config
    var minOverlapRatio:          CGFloat = 0.10
    var putDepthChangeThreshold:  CGFloat = 0.25
    var takeDepthChangeThreshold: CGFloat = 0.12
    var minHoldingFrames:         Int     = 8
    var maxNoOverlapFrames:       Int     = 30

    // MARK: - Callbacks
    // onAction tidak dipakai lagi oleh BasketManager (dibiarkan untuk kompatibilitas)
    var onAction: ((HandAction) -> Void)?
    var onDebug:  ((String, CGFloat, CGFloat, CGFloat, Bool) -> Void)?

    // MARK: - State
    private enum State {
        case idle
        case holding(
            baselineArea:  CGFloat,
            currentLabel:  String,
            trackID:       UUID?,
            holdingFrames: Int
        )
    }

    private var state:           State   = .idle
    private var noOverlapFrames: Int     = 0
    private var smoothedBoxArea: CGFloat = 0
    private let emaAlpha:        CGFloat = 0.3

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

        evaluate(bestMatch: bestMatch)
    }

    // MARK: - State Machine (debug only — tidak fire action ke BasketManager)

    private func evaluate(
        bestMatch: (detection: DetectionResult, label: String, overlapRatio: CGFloat)?
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
            state = .holding(
                baselineArea:  boxArea,
                currentLabel:  match.label,
                trackID:       match.detection.id,
                holdingFrames: 1
            )
            smoothedBoxArea = boxArea
            onDebug?("holding_start", boxArea, match.overlapRatio, 1.0, true)

        case .holding(let baselineArea, let label, let trackID, let holdingFrames):
            guard let match = bestMatch else {
                noOverlapFrames += 1
                if noOverlapFrames > maxNoOverlapFrames { resetState() }
                onDebug?("holding_lost(\(noOverlapFrames)fr)", smoothedBoxArea, 0, smoothedBoxArea / baselineArea, true)
                return
            }
            noOverlapFrames = 0

            let boxArea = match.detection.boundingBox.width * match.detection.boundingBox.height
            smoothedBoxArea = emaAlpha * boxArea + (1 - emaAlpha) * smoothedBoxArea

            let newHoldingFrames = holdingFrames + 1
            let ratio        = smoothedBoxArea / baselineArea
            let debugPhase   = String(format: "holding(%d fr, %.0f%%)", newHoldingFrames, ratio * 100)
            onDebug?(debugPhase, smoothedBoxArea, match.overlapRatio, ratio, true)

            // Tetap update state untuk debug, tapi TIDAK fire action
            state = .holding(
                baselineArea:  baselineArea,
                currentLabel:  label,
                trackID:       trackID,
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
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: 1.0 - maxY, width: maxX - minX, height: maxY - minY)
    }

    private func overlapRatio(_ hand: CGRect, _ product: CGRect) -> CGFloat {
        let inter = hand.intersection(product)
        guard !inter.isNull else { return 0 }
        let productArea = product.width * product.height
        return productArea > 0 ? (inter.width * inter.height) / productArea : 0
    }

    private func resetState() {
        state           = .idle
        noOverlapFrames = 0
        smoothedBoxArea = 0
    }

    func reset() { resetState() }
}
