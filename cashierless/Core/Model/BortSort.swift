//
//  BortSort.swift
//  cashierless
//
//  Created by Shafa Tiara on 19/05/26.
//

import CoreGraphics
import CoreImage
import CoreML
import UIKit
import Accelerate
import Vision

// MARK: - BoT-SORT Tracker
// Port dari DeepSortTracker temenmu
// Kalman Filter + Two-stage association + ReID OSNet x1_0

// MARK: - Kalman Filter (Constant Velocity)
// State: [cx, cy, w, h, vx, vy, vw, vh]

struct KalmanFilter {
    var cx, cy, w, h: Double
    var vx, vy, vw, vh: Double
    var pcx, pcy, pw, ph: Double
    var pvx, pvy, pvw, pvh: Double

    static let stdWeightPos: Double = 1.0 / 20.0
    static let stdWeightVel: Double = 1.0 / 160.0

    init(bbox: CGRect) {
        cx = Double(bbox.midX); cy = Double(bbox.midY)
        w  = Double(bbox.width); h  = Double(bbox.height)
        vx = 0; vy = 0; vw = 0; vh = 0
        let sp = KalmanFilter.stdWeightPos
        pcx = (2*sp*w)*(2*sp*w); pcy = (2*sp*h)*(2*sp*h)
        pw  = (2*sp*w)*(2*sp*w); ph  = (2*sp*h)*(2*sp*h)
        pvx = (10*sp*w)*(10*sp*w); pvy = (10*sp*h)*(10*sp*h)
        pvw = (10*sp*w)*(10*sp*w); pvh = (10*sp*h)*(10*sp*h)
    }

    mutating func predict() -> CGRect {
        let sp = KalmanFilter.stdWeightPos
        let sv = KalmanFilter.stdWeightVel
        let qp = sp * w; let qv = sv * w
        vx *= 0.5; vy *= 0.5; vw *= 0.5; vh *= 0.5
        cx += vx; cy += vy; w += vw; h += vh
        w = max(w, 1e-4); h = max(h, 1e-4)
        pcx += pvx + qp*qp; pcy += pvy + qp*qp
        pw  += pvw + qp*qp; ph  += pvh + qp*qp
        pvx += qv*qv; pvy += qv*qv
        pvw += qv*qv; pvh += qv*qv
        return toRect()
    }

    mutating func update(z: CGRect) -> CGRect {
        let zx = Double(z.midX); let zy = Double(z.midY)
        let zw = Double(z.width); let zh = Double(z.height)
        let sp = KalmanFilter.stdWeightPos
        let rp = sp * w; let rq = 2 * sp * w
        let Kcx = pcx/(pcx+rp*rp); let Kcy = pcy/(pcy+rp*rp)
        let Kw  = pw/(pw+rq*rq);   let Kh  = ph/(ph+rq*rq)
        let inn_cx = zx-cx; let inn_cy = zy-cy
        vx = vx*0.2 + inn_cx*0.1; vy = vy*0.2 + inn_cy*0.1
        vw = vw*0.2 + (zw-w)*0.1; vh = vh*0.2 + (zh-h)*0.1
        cx += Kcx*inn_cx; cy += Kcy*inn_cy
        w  += Kw*(zw-w);  h  += Kh*(zh-h)
        w = max(w, 1e-4); h = max(h, 1e-4)
        pcx *= (1-Kcx); pcy *= (1-Kcy)
        pw  *= (1-Kw);  ph  *= (1-Kh)
        pvx *= 0.9; pvy *= 0.9; pvw *= 0.9; pvh *= 0.9
        return toRect()
    }

    func toRect() -> CGRect {
        CGRect(x: cx-w/2, y: cy-h/2, width: w, height: h)
    }

    mutating func applyMotion(dx: Double, dy: Double) {
        cx += dx; cy += dy
    }
}

// MARK: - TrackedObject

struct TrackedObject: Identifiable {
    let id:          UUID
    var classIndex:  Int
    var confidence:  Float
    var boundingBox: CGRect       // raw detection box
    var kalmanBox:   CGRect       // Kalman predicted/updated box
    var embedding:   [Float]
    var velocity:    CGVector = .zero
    var missingFrames: Int  = 0
    var hitCount:      Int  = 1
}

// MARK: - BoTSORTTracker

final class BoTSORTTracker {

    private(set) var tracks:         [TrackedObject]   = []
    private var kalmanFilters:       [UUID: KalmanFilter] = [:]
    private let ciContext             = CIContext()

    // Config
    private let highConfThreshold:   Float  = 0.55
    private let iouAssocThreshold:   Double = 0.30
    private let embeddingWeight:      Double = 0.40
    private let reidRescueThreshold:  Double = 0.45
    private let maxMissingFrames:     Int    = 10
    private let minHitCountToDisplay: Int    = 1
    private let detectionNmsThreshold: Double = 0.65

    // MARK: - Update

    func update(detections: [DetectionResult], pixelBuffer: CVPixelBuffer?) -> [DetectionResult] {

        // 1. Kalman predict
        for i in 0..<tracks.count {
            let id = tracks[i].id
            var kf = kalmanFilters[id] ?? KalmanFilter(bbox: tracks[i].kalmanBox)
            let predicted = kf.predict()
            kalmanFilters[id] = kf
            tracks[i].kalmanBox = predicted
        }

        // 2. Two-stage association
        let highConf = detections.filter { $0.confidence >= highConfThreshold }
        let lowConf  = detections.filter { $0.confidence <  highConfThreshold }

        var matchedPairs:      [(trackIdx: Int, det: DetectionResult)] = []
        var unmatchedTrackIdxs = Set(tracks.indices)
        var unmatchedHighDets  = Set(highConf.indices)

        // Stage 1: high-conf vs all tracks (IoU + ReID)
        if !tracks.isEmpty && !highConf.isEmpty {
            let nT = tracks.count; let nD = highConf.count
            var cost = [[Double]](repeating: [Double](repeating: 1.0, count: nD), count: nT)
            for t in 0..<nT {
                for d in 0..<nD {
                    guard tracks[t].classIndex == highConf[d].classIndex else {
                        cost[t][d] = 1.0; continue
                    }
                    let overlap = iouRect(tracks[t].kalmanBox, highConf[d].boundingBox)
                    if overlap < 0.01 { cost[t][d] = 1.0; continue }
                    let iouCost  = 1.0 - overlap
                    var reidCost = 1.0
                    if let pb = pixelBuffer, !tracks[t].embedding.isEmpty {
                        let emb = extractEmbedding(pixelBuffer: pb, bbox: highConf[d].boundingBox)
                        reidCost = 1.0 - ReIDEmbedder.cosineSimilarity(tracks[t].embedding, emb)
                    }
                    cost[t][d] = (1 - embeddingWeight) * iouCost + embeddingWeight * reidCost
                }
            }
            for (t, d) in greedyMatch(costMatrix: cost, threshold: 1.0 - iouAssocThreshold) {
                matchedPairs.append((t, highConf[d]))
                unmatchedTrackIdxs.remove(t)
                unmatchedHighDets.remove(d)
            }
        }

        // Stage 2: low-conf vs unmatched tracks (IoU only)
        let unmatchedTrackList = Array(unmatchedTrackIdxs)
        if !unmatchedTrackList.isEmpty && !lowConf.isEmpty {
            let nT = unmatchedTrackList.count; let nD = lowConf.count
            var cost = [[Double]](repeating: [Double](repeating: 1.0, count: nD), count: nT)
            for (ti, t) in unmatchedTrackList.enumerated() {
                for d in 0..<nD {
                    guard tracks[t].classIndex == lowConf[d].classIndex else { continue }
                    cost[ti][d] = 1.0 - iouRect(tracks[t].kalmanBox, lowConf[d].boundingBox)
                }
            }
            for (ti, d) in greedyMatch(costMatrix: cost, threshold: 1.0 - iouAssocThreshold) {
                let t = unmatchedTrackList[ti]
                matchedPairs.append((t, lowConf[d]))
                unmatchedTrackIdxs.remove(t)
            }
        }

        // 3. Increment missingFrames untuk yang tidak ter-match
        let matchedIdxs = Set(matchedPairs.map { $0.trackIdx })
        for t in 0..<tracks.count where !matchedIdxs.contains(t) {
            tracks[t].missingFrames += 1
        }

        // 4. Update matched tracks
        for (t, det) in matchedPairs {
            var kf = kalmanFilters[tracks[t].id] ?? KalmanFilter(bbox: tracks[t].kalmanBox)
            let updated = kf.update(z: det.boundingBox)
            kalmanFilters[tracks[t].id] = kf
            tracks[t].boundingBox   = det.boundingBox
            tracks[t].kalmanBox     = updated
            tracks[t].confidence    = det.confidence
            tracks[t].missingFrames = 0
            tracks[t].hitCount     += 1
            // EMA embedding
            if let pb = pixelBuffer {
                let newEmb = extractEmbedding(pixelBuffer: pb, bbox: det.boundingBox)
                tracks[t].embedding = blendEmbedding(old: tracks[t].embedding, new: newEmb, alpha: 0.4)
            }
        }

        // 5. Init new tracks untuk unmatched high-conf
        let unmatchedDets = unmatchedHighDets.map { highConf[$0] }
            .sorted { $0.confidence > $1.confidence }
        var newBoxes = [CGRect]()

        for det in unmatchedDets {
            let overlapsExisting = tracks.contains {
                $0.missingFrames == 0 &&
                iouRect($0.boundingBox, det.boundingBox) > detectionNmsThreshold
            }
            guard !overlapsExisting else { continue }
            let overlapsNew = newBoxes.contains {
                iouRect($0, det.boundingBox) > detectionNmsThreshold
            }
            guard !overlapsNew else { continue }

            var emb = [Float](repeating: 0, count: ReIDConfig.embeddingDim)
            if let pb = pixelBuffer {
                emb = extractEmbedding(pixelBuffer: pb, bbox: det.boundingBox)
            }
            let kf = KalmanFilter(bbox: det.boundingBox)
            var newTrack = TrackedObject(
                id:          UUID(),
                classIndex:  det.classIndex,
                confidence:  det.confidence,
                boundingBox: det.boundingBox,
                kalmanBox:   det.boundingBox,
                embedding:   emb
            )
            kalmanFilters[newTrack.id] = kf
            tracks.append(newTrack)
            newBoxes.append(det.boundingBox)
        }

        // 6. Hapus track yang sudah terlalu lama hilang
        let removed = tracks.filter { $0.missingFrames > maxMissingFrames }
        for t in removed { kalmanFilters.removeValue(forKey: t.id) }
        tracks.removeAll { $0.missingFrames > maxMissingFrames }

        // 7. Return visible tracks sebagai DetectionResult
        return tracks
            .filter { $0.hitCount >= minHitCountToDisplay && $0.missingFrames == 0 }
            .map { t in
                DetectionResult(
                    id:          t.id,
                    classIndex:  t.classIndex,
                    confidence:  t.confidence,
                    boundingBox: t.kalmanBox
                )
            }
    }

    // MARK: - Helpers

    private func iouRect(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        guard !inter.isNull else { return 0 }
        let iA = Double(inter.width * inter.height)
        let uA = Double(a.width*a.height) + Double(b.width*b.height) - iA
        return uA > 0 ? iA/uA : 0
    }

    private func greedyMatch(costMatrix: [[Double]], threshold: Double) -> [(Int, Int)] {
        guard !costMatrix.isEmpty, !costMatrix[0].isEmpty else { return [] }
        let nT = costMatrix.count, nD = costMatrix[0].count
        var pairs: [(Double, Int, Int)] = []
        for t in 0..<nT { for d in 0..<nD { pairs.append((costMatrix[t][d], t, d)) } }
        pairs.sort { $0.0 < $1.0 }
        var matched = [(Int,Int)](); var usedT = Set<Int>(); var usedD = Set<Int>()
        for (cost, t, d) in pairs {
            if cost > threshold { break }
            if usedT.contains(t) || usedD.contains(d) { continue }
            matched.append((t, d)); usedT.insert(t); usedD.insert(d)
        }
        return matched
    }

    private func extractEmbedding(pixelBuffer: CVPixelBuffer, bbox: CGRect) -> [Float] {
        let pw = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let ph = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let crop = CGRect(x: bbox.minX*pw, y: bbox.minY*ph,
                          width: bbox.width*pw, height: bbox.height*ph).integral
        let bounds = CGRect(x: 0, y: 0, width: pw, height: ph)
        let safe   = crop.intersection(bounds)
        guard !safe.isNull, safe.width > 0, safe.height > 0 else {
            return [Float](repeating: 0, count: ReIDConfig.embeddingDim)
        }
        let ci = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: safe)
        guard let cg = ciContext.createCGImage(ci, from: safe) else {
            return [Float](repeating: 0, count: ReIDConfig.embeddingDim)
        }
        return ReIDEmbedder.shared.embed(image: UIImage(cgImage: cg))
    }

    private func blendEmbedding(old: [Float], new: [Float], alpha: Float) -> [Float] {
        guard old.count == new.count else { return new }
        return zip(old, new).map { o, n in o*(1-alpha) + n*alpha }
    }
}
