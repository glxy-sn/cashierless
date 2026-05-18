//
//  HandOverlayView.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import SwiftUI
import Vision

// MARK: - HandOverlayView
// Port langsung dari c2 — termasuk coordinate conversion yang benar
// untuk AVFoundation portrait feed ke Vision normalized coords

struct HandOverlayView: View {
    let landmarks: HandLandmarks?
    let size: CGSize

    var body: some View {
        Canvas { ctx, _ in
            guard let lm = landmarks else { return }

            let screenPoints: [CGPoint?] = HandLandmarks.orderedJoints.map { joint in
                guard let vp = lm.points[joint] else { return nil }
                return convertVisionPoint(vp, to: size)
            }

            // Palm fill
            let palmIndices = [0, 5, 9, 13, 17, 1]
            let palmPts = palmIndices.compactMap { screenPoints[$0] }
            if palmPts.count == palmIndices.count {
                var path = Path()
                path.move(to: palmPts[0])
                palmPts.dropFirst().forEach { path.addLine(to: $0) }
                path.closeSubpath()
                ctx.fill(path, with: .color(.cyan.opacity(0.10)))
            }

            // Wrist → knuckles
            if let wrist = screenPoints[0] {
                for knuckleIdx in HandLandmarks.wristToKnuckle {
                    guard let knuckle = screenPoints[knuckleIdx] else { continue }
                    var path = Path(); path.move(to: wrist); path.addLine(to: knuckle)
                    ctx.stroke(path, with: .color(.white.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }

            // Palm cross
            for (a, b) in HandLandmarks.palmCross {
                guard let ptA = screenPoints[a], let ptB = screenPoints[b] else { continue }
                var path = Path(); path.move(to: ptA); path.addLine(to: ptB)
                ctx.stroke(path, with: .color(.white.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            // Finger segments
            for (a, b) in HandLandmarks.fingerSegments {
                guard let ptA = screenPoints[a], let ptB = screenPoints[b] else { continue }
                var path = Path(); path.move(to: ptA); path.addLine(to: ptB)
                ctx.stroke(path, with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }

            // Dots
            let tipIndices: Set<Int> = [4, 8, 12, 16, 20]
            for (i, joint) in HandLandmarks.orderedJoints.enumerated() {
                guard let pt = screenPoints[i] else { continue }
                let isWrist = (joint == .wrist)
                let isTip   = tipIndices.contains(i)
                let radius: CGFloat  = isWrist ? 7 : (isTip ? 5.5 : 4)
                let dotColor: Color  = isWrist ? .green : (isTip ? .yellow : .white)
                let rect = CGRect(x: pt.x-radius, y: pt.y-radius, width: radius*2, height: radius*2)
                ctx.fill(Path(ellipseIn: rect), with: .color(dotColor))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.45)), lineWidth: 1.2)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate Conversion (port dari c2)
    // Vision portrait frame → screen coords dengan compensate crop offset

    private func convertVisionPoint(_ vp: CGPoint, to screenSize: CGSize) -> CGPoint {
        let cameraAspect: CGFloat = 9.0 / 16.0
        let viewAspect = screenSize.width / screenSize.height

        let scaledW: CGFloat
        let scaledH: CGFloat

        if viewAspect > cameraAspect {
            scaledW = screenSize.width
            scaledH = screenSize.width / cameraAspect
        } else {
            scaledW = screenSize.height * cameraAspect
            scaledH = screenSize.height
        }

        let offsetX = (scaledW - screenSize.width) / 2
        let offsetY = (scaledH - screenSize.height) / 2

        return CGPoint(
            x: vp.x * scaledW - offsetX,
            y: (1 - vp.y) * scaledH - offsetY
        )
    }
}
