//
//  Depth.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import Foundation
import Vision

// MARK: - Product Depth Tracker
// Kamera dari atas menghadap keranjang:
//   box MENGECIL dari baseline → produk masuk keranjang → PUT
//   box MEMBESAR dari baseline → produk keluar keranjang → TAKE

final class ProductDepthTracker {

    // MARK: - Config
    var minOverlapRatio:          CGFloat = 0.10
    var putDepthChangeThreshold:  CGFloat = 0.25   // box harus mengecil 25% untuk PUT
    var takeDepthChangeThreshold: CGFloat = 0.12   // box harus membesar 12% untuk TAKE
    var minHoldingFrames:         Int     = 8
    var maxNoOverlapFrames:       Int     = 30

    // Cooldown per track
    private var lastFiredTrackID: UUID? = nil
    private var lastFiredTime:    Date  = .distantPast
    private let trackCooldown:    TimeInterval = 2.0

    // MARK: - Callbacks
    var onAction: ((HandAction) -> Void)?
    var onDebug:  ((String, CGFloat, CGFloat, CGFloat, Bool) -> Void)?

    // MARK: - State
    private enum State {
        case idle
        case holding(
            baselineArea:  CGFloat,   // area saat pertama overlap — reference untuk PUT dan TAKE
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

    // MARK: - State Machine

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

            // Cooldown per track
            let now = Date()
            if let lastID = lastFiredTrackID,
               lastID == match.detection.id,
               now.timeIntervalSince(lastFiredTime) < trackCooldown {
                onDebug?("cooldown", 0, match.overlapRatio, 0, true)
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
                return
            }
            noOverlapFrames = 0

            let boxArea = match.detection.boundingBox.width * match.detection.boundingBox.height
            smoothedBoxArea = emaAlpha * boxArea + (1 - emaAlpha) * smoothedBoxArea

            let newHoldingFrames = holdingFrames + 1
            // Ratio terhadap baseline — di bawah 1 = mengecil (PUT), di atas 1 = membesar (TAKE)
            let ratio        = smoothedBoxArea / baselineArea
            let debugPhase   = String(format: "holding(%d fr, %.0f%%)", newHoldingFrames, ratio * 100)
            onDebug?(debugPhase, smoothedBoxArea, match.overlapRatio, ratio, true)

            if newHoldingFrames >= minHoldingFrames {
                if ratio < (1.0 - putDepthChangeThreshold) {
                    // Box mengecil 25% dari baseline → PUT
                    lastFiredTrackID = trackID
                    lastFiredTime    = Date()
                    fire(.approachingBasket)
                    return
                } else if ratio > (1.0 + takeDepthChangeThreshold) {
                    // Box membesar 12% dari baseline → TAKE
                    lastFiredTrackID = trackID
                    lastFiredTime    = Date()
                    fire(.leavingBasket)
                    return
                }
            }

            // PENTING: baselineArea TIDAK di-update — tetap pakai nilai awal
            // Ini yang fix bug sebelumnya dimana peakArea terus naik sehingga TAKE tidak pernah trigger
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

    private func fire(_ action: HandAction) {
        onAction?(action)
        resetState()
    }

    private func resetState() {
        state           = .idle
        noOverlapFrames = 0
        smoothedBoxArea = 0
    }

    func reset() {
        resetState()
        lastFiredTrackID = nil
        lastFiredTime    = .distantPast
    }
}
