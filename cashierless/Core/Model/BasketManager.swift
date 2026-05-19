//
//  BasketManager.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import Foundation
import UIKit
import Combine
import Vision

// MARK: - BasketManager
// Port dari c2 — orchestrator hand gesture + product depth tracking

@MainActor
final class BasketManager: ObservableObject {

    @Published var landmarks:         HandLandmarks? = nil
    @Published var debugPhase:        String  = "idle"
    @Published var debugBoxArea:      CGFloat = 0
    @Published var debugOverlapRatio: CGFloat = 0
    @Published var debugAreaRatio:    CGFloat = 0
    @Published var debugIsHolding:    Bool    = false
    @Published var itemCount:         Int     = 0

    let depthTracker = ProductDepthTracker()

    lazy var handPoseProcessor = HandPoseProcessor { [weak self] landmarks in
        Task { @MainActor in self?.landmarks = landmarks }
    }

    // Gunakan closure strong reference, bukan weak protocol reference
    // Sama seperti pola c2: basketManager.cartManager = cartManager
    // Closure dengan trackID untuk binding bbox
    var addToCart:       ((Product, UUID?) -> Void)?
    var removeFromCart:  ((Product) -> Void)?
    /// Return true kalau produk ada di cart — untuk validasi TAKE (opsi 2)
    var isProductInCart: ((Product) -> Bool)?

    // Toast callback
    var onBasketEvent: ((BasketEvent) -> Void)?

    // Cooldown
    private var lastEventTime: Date = .distantPast
    private let minEventInterval: TimeInterval = 1.5
    private var currentDetections: [DetectionResult] = []

    init() { bindDepthTracker() }

    private func bindDepthTracker() {
        depthTracker.onAction = { [weak self] action in
            Task { @MainActor in self?.handleDepthAction(action) }
        }
        depthTracker.onDebug = { [weak self] phase, boxArea, overlap, areaRatio, isHolding in
            Task { @MainActor in
                guard let self else { return }
                self.debugPhase        = phase
                self.debugBoxArea      = boxArea
                self.debugOverlapRatio = overlap
                self.debugAreaRatio    = areaRatio
                self.debugIsHolding    = isHolding
            }
        }
    }

    // MARK: - Process frame

    func processFrame(detections: [DetectionResult], viewSize: CGSize) {
        currentDetections = detections
        depthTracker.process(landmarks: landmarks, detections: detections, viewSize: viewSize)
    }

    // MARK: - Handle gesture

    private func handleDepthAction(_ action: HandAction) {
        guard action != .idle else { return }
        let now = Date()
        guard now.timeIntervalSince(lastEventTime) >= minEventInterval else { return }
        lastEventTime = now

        switch action {

        case .approachingBasket:   // PUT — selalu bisa
            if let (product, trackID) = findBestProductAndTrackInHand() {
                addToCart?(product, trackID)
                let event = BasketEvent(action: .put, productName: product.name, confidence: 0.80)
                itemCount += 1
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onBasketEvent?(event)
            }

        case .leavingBasket:       // TAKE — hanya kalau produk ada di cart
            if let (product, _) = findBestProductAndTrackInHand() {
                let inCart = isProductInCart?(product) ?? false
                guard inCart else {
                    print("[BasketManager] ⏭ TAKE diabaikan — \(product.name) tidak ada di cart")
                    return
                }
                removeFromCart?(product)
                let event = BasketEvent(action: .take, productName: product.name, confidence: 0.50)
                itemCount = max(0, itemCount - 1)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onBasketEvent?(event)
            }

        case .idle: break
        }
    }

    // MARK: - Helpers

    private func findBestProductAndTrackInHand() -> (Product, UUID?)? {
        guard let lm = landmarks, let handRect = computeHandBBox(from: lm) else { return nil }
        let expandedHand = handRect.insetBy(dx: -0.08, dy: -0.08)
        var best: (product: Product, trackID: UUID?, ratio: CGFloat)?
        for det in currentDetections {
            guard let product = det.product else { continue }
            let ratio = overlapRatio(expandedHand, det.boundingBox)
            if ratio >= 0.10, (best == nil || ratio > best!.ratio) {
                best = (product, det.id, ratio)
            }
        }
        guard let b = best else { return nil }
        return (b.product, b.trackID)
    }

    private func computeHandBBox(from lm: HandLandmarks) -> CGRect? {
        let pts = Array(lm.points.values)
        guard pts.count >= 3 else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in pts { minX=min(minX,p.x); maxX=max(maxX,p.x); minY=min(minY,p.y); maxY=max(maxY,p.y) }
        return CGRect(x: minX, y: 1.0 - maxY, width: maxX - minX, height: maxY - minY)
    }

    private func overlapRatio(_ hand: CGRect, _ product: CGRect) -> CGFloat {
        let inter = hand.intersection(product)
        guard !inter.isNull else { return 0 }
        let productArea = product.width * product.height
        return productArea > 0 ? (inter.width * inter.height) / productArea : 0
    }

    func clearHistory() { itemCount = 0; depthTracker.reset() }
}
