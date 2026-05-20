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
// PUT  → tangan overlap dengan track yang BELUM di-cart → assign ke cart
// TAKE → tangan overlap dengan track yang SUDAH di-cart → track hilang → remove dari cart

@MainActor
final class BasketManager: ObservableObject {

    @Published var landmarks:         HandLandmarks? = nil
    @Published var debugPhase:        String  = "idle"
    @Published var debugBoxArea:      CGFloat = 0
    @Published var debugOverlapRatio: CGFloat = 0
    @Published var debugAreaRatio:    CGFloat = 0
    @Published var debugIsHolding:    Bool    = false
    @Published var itemCount:         Int     = 0

    // MARK: - Re-ID State
    // Set of track IDs yang sudah di-assign ke cart (sudah masuk keranjang)
    private var cartTrackIDs: Set<UUID> = []

    // Track yang sedang "dipegang tangan" untuk TAKE monitoring
    // key: trackID yang overlap tangan, value: frame count overlap
    private var handOverlapCandidates: [UUID: Int] = [:]
    private let minOverlapFramesBeforeWatch = 5   // berapa frame overlap sebelum kita "watch" untuk TAKE

    // Track yang sedang kita pantau untuk TAKE (sudah confirmed overlap)
    // Ketika track ini hilang → TAKE fired
    private var watchingForTake: UUID? = nil
    private var watchingProduct: Product? = nil
    private var takeGraceFrames: Int = 0
    private let maxTakeGraceFrames = 8   // toleransi frame hilang sebelum dianggap keluar

    let depthTracker = ProductDepthTracker()

    lazy var handPoseProcessor = HandPoseProcessor { [weak self] landmarks in
        Task { @MainActor in self?.landmarks = landmarks }
    }

    var addToCart:       ((Product, UUID?) -> Void)?
    var removeFromCart:  ((Product) -> Void)?
    var isProductInCart: ((Product) -> Bool)?
    var onBasketEvent:   ((BasketEvent) -> Void)?

    // Cooldown untuk PUT
    private var lastPutTime:    Date = .distantPast
    private let minPutInterval: TimeInterval = 1.5
    // Cooldown per track ID untuk PUT
    private var recentlyAddedTrackIDs: Set<UUID> = []

    private var currentDetections: [DetectionResult] = []

    init() { bindDepthTracker() }

    private func bindDepthTracker() {
        // DepthTracker hanya untuk debug visual, action sudah kita handle sendiri
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
        // Tidak pakai depthTracker.onAction — kita handle PUT/TAKE sendiri
    }

    // MARK: - Process frame

    func processFrame(detections: [DetectionResult], viewSize: CGSize) {
        currentDetections = detections
        // Tetap jalankan depthTracker untuk debug overlay
        depthTracker.process(landmarks: landmarks, detections: detections, viewSize: viewSize)

        // Logika utama PUT & TAKE berbasis Re-ID
        processHandInteraction(detections: detections)
    }

    // MARK: - Hand Interaction Logic

    private func processHandInteraction(detections: [DetectionResult]) {
        guard let lm = landmarks, let handRect = computeHandBBox(from: lm) else {
            // Tidak ada tangan — reset overlap candidates
            handOverlapCandidates.removeAll()
            // Cek apakah track yang sedang di-watch hilang
            handleTakeWatchWithNoHand(detections: detections)
            return
        }

        let expandedHand = handRect.insetBy(dx: -0.08, dy: -0.08)

        // Kumpulkan semua track yang overlap dengan tangan
        var overlappingDetections: [(det: DetectionResult, ratio: CGFloat)] = []
        for det in detections {
            guard det.product != nil else { continue }
            let ratio = overlapRatio(expandedHand, det.boundingBox)
            if ratio >= 0.10 {
                overlappingDetections.append((det, ratio))
            }
        }

        let overlappingIDs = Set(overlappingDetections.map { $0.det.id })

        // Hapus kandidat yang sudah tidak overlap lagi
        handOverlapCandidates = handOverlapCandidates.filter { overlappingIDs.contains($0.key) }

        // Increment frame counter untuk yang masih overlap
        for item in overlappingDetections {
            handOverlapCandidates[item.det.id, default: 0] += 1
        }

        // Ambil detection terbaik (overlap ratio tertinggi)
        let bestOverlap = overlappingDetections.max(by: { $0.ratio < $1.ratio })

        if let best = bestOverlap {
            let trackID = best.det.id

            if cartTrackIDs.contains(trackID) {
                // Track ini SUDAH di-cart → kandidat TAKE
                handleTakeCandidate(trackID: trackID, product: best.det.product!, detections: detections)
            } else {
                // Track ini BELUM di-cart → kandidat PUT
                handlePutCandidate(det: best.det, overlapFrames: handOverlapCandidates[trackID] ?? 1)
            }
        } else {
            // Tidak ada overlap — cek apakah yang sedang di-watch hilang
            handleTakeWatchWithNoHand(detections: detections)
        }
    }

    // MARK: - PUT Logic
    // Tangan overlap dengan track yang belum di-cart → PUT

    private func handlePutCandidate(det: DetectionResult, overlapFrames: Int) {
        guard let product = det.product else { return }
        let trackID = det.id

        // Jangan PUT kalau track ini sudah pernah di-add
        guard !recentlyAddedTrackIDs.contains(trackID) else {
            debugPhase = "put_skip(already_added)"
            return
        }

        // Cooldown global PUT
        let now = Date()
        guard now.timeIntervalSince(lastPutTime) >= minPutInterval else {
            debugPhase = "put_cooldown"
            return
        }

        // Perlu beberapa frame overlap yang stabil sebelum PUT
        guard overlapFrames >= minOverlapFramesBeforeWatch else {
            debugPhase = "put_pending(\(overlapFrames) fr)"
            return
        }

        // ✅ PUT confirmed
        lastPutTime = now
        cartTrackIDs.insert(trackID)
        recentlyAddedTrackIDs.insert(trackID)
        handOverlapCandidates[trackID] = 0

        addToCart?(product, trackID)
        let event = BasketEvent(action: .put, productName: product.name, confidence: 0.80)
        itemCount += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onBasketEvent?(event)
        debugPhase = "PUT_fired(\(product.name))"
        print("[BasketManager] ✅ PUT: \(product.name) | trackID: \(trackID)")
    }

    // MARK: - TAKE Logic
    // Tangan overlap dengan track yang sudah di-cart → mulai watch
    // Ketika track itu hilang dari detections → TAKE

    private func handleTakeCandidate(trackID: UUID, product: Product, detections: [DetectionResult]) {
        // Set track ini sebagai yang sedang di-watch untuk TAKE
        if watchingForTake != trackID {
            watchingForTake  = trackID
            watchingProduct  = product
            takeGraceFrames  = 0
            print("[BasketManager] 👁 Watching for TAKE: \(product.name) | trackID: \(trackID)")
        }
        debugPhase = "take_watching(\(product.name))"
    }

    private func handleTakeWatchWithNoHand(detections: [DetectionResult]) {
        guard let watchID = watchingForTake, let product = watchingProduct else { return }

        // Cek apakah track yang di-watch masih ada di detections
        let stillVisible = detections.contains { $0.id == watchID }

        if stillVisible {
            // Track masih ada — belum keluar, reset grace
            takeGraceFrames = 0
            debugPhase = "take_watch_present(\(product.name))"
        } else {
            // Track tidak terdeteksi — mulai hitung grace frames
            takeGraceFrames += 1
            debugPhase = "take_grace(\(takeGraceFrames)/\(maxTakeGraceFrames))"

            if takeGraceFrames >= maxTakeGraceFrames {
                // ✅ TAKE confirmed — track benar-benar hilang setelah tangan overlap
                fireTake(product: product, trackID: watchID)
            }
        }
    }

    private func fireTake(product: Product, trackID: UUID) {
        let inCart = isProductInCart?(product) ?? false
        guard inCart else {
            print("[BasketManager] ⏭ TAKE diabaikan — \(product.name) tidak ada di cart")
            resetTakeWatch()
            return
        }

        cartTrackIDs.remove(trackID)
        recentlyAddedTrackIDs.remove(trackID) // Boleh di-add lagi kalau masuk ulang
        removeFromCart?(product)
        let event = BasketEvent(action: .take, productName: product.name, confidence: 0.75)
        itemCount = max(0, itemCount - 1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onBasketEvent?(event)
        debugPhase = "TAKE_fired(\(product.name))"
        print("[BasketManager] ✅ TAKE: \(product.name) | trackID: \(trackID)")
        resetTakeWatch()
    }

    private func resetTakeWatch() {
        watchingForTake = nil
        watchingProduct = nil
        takeGraceFrames = 0
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

    func clearHistory() {
        itemCount = 0
        cartTrackIDs.removeAll()
        recentlyAddedTrackIDs.removeAll()
        handOverlapCandidates.removeAll()
        resetTakeWatch()
        depthTracker.reset()
    }
}
