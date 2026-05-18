//
//  HandTracker.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import Vision
import CoreGraphics
import Foundation
import Combine

// MARK: - HandAction

enum HandAction: Equatable {
    case approachingBasket  // PUT
    case leavingBasket      // TAKE
    case idle
}

// MARK: - HandLandmarks

struct HandLandmarks {
    let points: [VNHumanHandPoseObservation.JointName: CGPoint]

    static let orderedJoints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP,   .ringPIP,  .ringDIP,  .ringTip,
        .littleMCP, .littlePIP,.littleDIP,.littleTip
    ]
    static let fingerSegments: [(Int,Int)] = [
        (1,2),(2,3),(3,4),(5,6),(6,7),(7,8),
        (9,10),(10,11),(11,12),(13,14),(14,15),(15,16),(17,18),(18,19),(19,20)
    ]
    static let wristToKnuckle: [Int] = [1, 5, 9, 13, 17]
    static let palmCross: [(Int,Int)] = [(5,9),(9,13),(13,17)]

    /// Bounding-box area dari semua landmark — makin besar = makin dekat kamera
    var palmArea: CGFloat {
        let pts = Array(points.values)
        guard pts.count >= 3 else { return 0 }
        var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in pts { minX=min(minX,p.x); maxX=max(maxX,p.x); minY=min(minY,p.y); maxY=max(maxY,p.y) }
        return (maxX-minX)*(maxY-minY)
    }
}

// MARK: - HandPoseProcessor

final class HandPoseProcessor {
    private let handPoseRequest: VNDetectHumanHandPoseRequest
    private let onLandmarks: (HandLandmarks?) -> Void

    init(onLandmarks: @escaping (HandLandmarks?) -> Void) {
        self.onLandmarks = onLandmarks
        self.handPoseRequest = VNDetectHumanHandPoseRequest()
        self.handPoseRequest.maximumHandCount = 1
    }

    func processFrame(pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([handPoseRequest])
            guard let obs = handPoseRequest.results?.first else {
                onLandmarks(nil); return
            }
            var pts: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
            for joint in HandLandmarks.orderedJoints {
                if let p = try? obs.recognizedPoint(joint), p.confidence > 0.1 {
                    pts[joint] = p.location
                }
            }
            onLandmarks(HandLandmarks(points: pts))
        } catch {
            print("[HandPose] Error: \(error)")
            onLandmarks(nil)
        }
    }
}

// MARK: - GesturePhase

private enum GesturePhase: CustomStringConvertible {
    case idle
    case large(peakArea: CGFloat, hadProduct: Bool)
    case small(troughArea: CGFloat, hadProduct: Bool)

    var description: String {
        switch self {
        case .idle:                return "idle"
        case .large(let a, let p): return String(format:"large(%.3f,prod=%@)",a,p ? "Y":"N")
        case .small(let a, let p): return String(format:"small(%.3f,prod=%@)",a,p ? "Y":"N")
        }
    }
}

// MARK: - HandTracker

final class HandTracker: ObservableObject {

    // Config
    var confidenceThreshold: Float  = 0.1
    var largeAreaThreshold:  CGFloat = 0.01
    var shrinkRatio:         CGFloat = 0.3
    var growRatio:           CGFloat = 1.5
    var minSmallFrames:      Int     = 3
    var maxMissingFrames:    Int     = 50

    // Callbacks
    var onAction:        ((HandAction) -> Void)?
    var onWristPosition: ((CGFloat) -> Void)?
    var onLandmarks:     ((HandLandmarks?) -> Void)?
    var onDebug:         ((String, CGFloat, Bool) -> Void)?

    /// Diupdate dari luar setiap frame — ada produk di frame atau tidak
    var hasProductInFrame: Bool = false

    // State
    private var phase:         GesturePhase = .idle
    private var smallFrames:   Int          = 0
    private var missingFrames: Int          = 0
    private var smoothedArea:  CGFloat      = 0
    private let emaAlpha:      CGFloat      = 0.4

    // MARK: - Process

    func process(observations: [VNHumanHandPoseObservation]) {
        guard let obs = observations.first else {
            missingFrames += 1
            if missingFrames > maxMissingFrames { resetPhase() }
            onLandmarks?(nil)
            return
        }
        missingFrames = 0

        guard let wristPt = try? obs.recognizedPoint(.wrist),
              wristPt.confidence > confidenceThreshold else {
            onLandmarks?(nil)
            return
        }

        var pts: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
        for joint in HandLandmarks.orderedJoints {
            if let p = try? obs.recognizedPoint(joint), p.confidence > confidenceThreshold {
                pts[joint] = p.location
            }
        }
        let landmarks = HandLandmarks(points: pts)
        onLandmarks?(landmarks)
        onWristPosition?(wristPt.location.y)

        let rawArea  = landmarks.palmArea
        smoothedArea = smoothedArea == 0 ? rawArea : emaAlpha * rawArea + (1 - emaAlpha) * smoothedArea

        onDebug?(phase.description, smoothedArea, hasProductInFrame)
        evaluate(area: smoothedArea)
    }

    // MARK: - State Machine

    private func evaluate(area: CGFloat) {
        switch phase {

        case .idle:
            guard area >= largeAreaThreshold else { return }
            phase       = .large(peakArea: area, hadProduct: hasProductInFrame)
            smallFrames = 0

        case .large(let peakArea, let hadProduct):
            if area > peakArea {
                phase = .large(peakArea: area, hadProduct: hadProduct)
                return
            }
            if area < peakArea * shrinkRatio {
                phase       = .small(troughArea: area, hadProduct: hadProduct)
                smallFrames = 1
            }

        case .small(let troughArea, let hadProduct):
            smallFrames += 1
            let currentTrough = min(troughArea, area)
            phase = .small(troughArea: currentTrough, hadProduct: hadProduct)

            guard area > currentTrough * growRatio else { return }
            guard smallFrames >= minSmallFrames else { resetPhase(); return }

            let hasNow = hasProductInFrame
            if hadProduct && !hasNow      { fire(.approachingBasket) }
            else if !hadProduct && hasNow { fire(.leavingBasket) }
            else                          { resetPhase() }
        }
    }

    private func fire(_ action: HandAction) { onAction?(action); resetPhase() }

    private func resetPhase() {
        phase         = .idle
        smallFrames   = 0
        missingFrames = 0
    }

    func reset() {
        resetPhase()
        hasProductInFrame = false
        smoothedArea      = 0
    }
}

// MARK: - HandLandmarks extension

extension HandLandmarks {
    var wristPosition: CGPoint? {
        guard let wrist = points[.wrist] else { return nil }
        return CGPoint(x: wrist.x, y: 1.0 - wrist.y)
    }
}
