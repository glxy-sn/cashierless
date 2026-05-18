//
//  DetectionView.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import SwiftUI
import Combine
import UIKit

// MARK: - DetectionViewModel

@MainActor
final class DetectionViewModel: ObservableObject {

    @Published var detections:    [DetectionResult] = []
    @Published var isModelLoaded: Bool = false
    @Published var isFlashOn:     Bool = false
    @Published var activeToast:   BasketEvent? = nil
    @Published var statusText:    String = "Memuat model..."

    #if DEBUG
    @Published var debugPhase:        String  = "idle"
    @Published var debugBoxArea:      CGFloat = 0
    @Published var debugOverlapRatio: CGFloat = 0
    @Published var debugAreaRatio:    CGFloat = 0
    @Published var debugIsHolding:    Bool    = false
    @Published var debugHasLandmarks: Bool    = false
    #endif

    let cameraManager:   CameraManager
    let inferenceEngine: InferenceEngine
    let basketManager:   BasketManager
    private let cartService: CartServiceImpl

    init(cameraManager: CameraManager, inferenceEngine: InferenceEngine,
         basketManager: BasketManager, cartService: CartServiceImpl) {
        self.cameraManager   = cameraManager
        self.inferenceEngine = inferenceEngine
        self.basketManager   = basketManager
        self.cartService     = cartService
        bindAll()
    }

    // MARK: - Binding

    private var cancellables = Set<AnyCancellable>()

    private func bindAll() {
        // Wire basketManager → cartService via closure (strong reference, tidak bisa nil)
        basketManager.addToCart = { [cartService] product in
            cartService.addProduct(product, source: .detection)
        }
        basketManager.removeFromCart = { [cartService] product in
            if let item = cartService.items.first(where: { $0.product.id == product.id }) {
                cartService.decreaseQuantity(for: item)
            } else if let last = cartService.items.last {
                // fallback: ambil item terakhir
                cartService.decreaseQuantity(for: last)
            }
        }

        // Frame → inference + hand pose
        let processor = basketManager.handPoseProcessor
        cameraManager.onFrame = { [weak self] pixelBuffer in
            self?.inferenceEngine.run(on: pixelBuffer)
            processor.processFrame(pixelBuffer: pixelBuffer)
        }

        // Inference results → update detections ONLY
        // processFrame ke BasketManager dilakukan via onReceive di View (seperti c2)
        inferenceEngine.onDetections = { [weak self] detections in
            guard let self else { return }
            self.detections = detections
            self.updateStatus()
        }

        // Model loaded
        inferenceEngine.onModelLoaded = { [weak self] in
            self?.isModelLoaded = true
            self?.updateStatus()
        }
        if inferenceEngine.isModelLoaded { isModelLoaded = true; updateStatus() }

        // Basket event → toast
        basketManager.onBasketEvent = { [weak self] event in
            guard let self else { return }
            withAnimation(.spring(response: 0.35)) { self.activeToast = event }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { self.activeToast = nil }
            }
        }

        // Debug
        #if DEBUG
        basketManager.$debugPhase        .receive(on: RunLoop.main).assign(to: &$debugPhase)
        basketManager.$debugBoxArea      .receive(on: RunLoop.main).assign(to: &$debugBoxArea)
        basketManager.$debugOverlapRatio .receive(on: RunLoop.main).assign(to: &$debugOverlapRatio)
        basketManager.$debugAreaRatio    .receive(on: RunLoop.main).assign(to: &$debugAreaRatio)
        basketManager.$debugIsHolding    .receive(on: RunLoop.main).assign(to: &$debugIsHolding)
        basketManager.$landmarks
            .map { $0 != nil }
            .receive(on: RunLoop.main)
            .assign(to: &$debugHasLandmarks)
        #endif
    }

    // MARK: - Intents

    func onAppear()    { updateStatus() }
    func onDisappear() { isFlashOn = false; cameraManager.setTorch(false) }

    func toggleFlash() { isFlashOn.toggle(); cameraManager.setTorch(isFlashOn) }

    func updateStatus() {
        let objText = detections.isEmpty ? "" : " · \(detections.count) objek"
        statusText  = isModelLoaded ? "Siap\(objText)" : "Memuat model..."
    }
}

// MARK: - DetectionView

struct DetectionView: View {

    @StateObject private var viewModel: DetectionViewModel
    private let cartService: CartServiceImpl

    init(cameraManager: CameraManager, inferenceEngine: InferenceEngine,
         basketManager: BasketManager, cartService: CartServiceImpl) {
        self.cartService = cartService
        _viewModel = StateObject(wrappedValue: DetectionViewModel(
            cameraManager:   cameraManager,
            inferenceEngine: inferenceEngine,
            basketManager:   basketManager,
            cartService:     cartService
        ))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                cameraSection(geo: geo).frame(height: geo.size.height * 0.58)
                CartPanelView(cartService: cartService)
            }
        }
        .background(Color.appBackground)
        .onAppear   { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        // processFrame dipanggil di MainActor via onReceive — persis seperti c2
        .onReceive(viewModel.$detections) { newDetections in
            let camSize = CGSize(width: UIScreen.main.bounds.width,
                                 height: UIScreen.main.bounds.height)
            viewModel.basketManager.processFrame(detections: newDetections, viewSize: camSize)
        }
    }

    @ViewBuilder
    private func cameraSection(geo: GeometryProxy) -> some View {
        let camSize = CGSize(width: geo.size.width, height: geo.size.height * 0.58)

        ZStack {
            if viewModel.cameraManager.error == .permissionDenied {
                Color.black; CameraPermissionDeniedView()
            } else {
                CameraPreviewView(cameraManager: viewModel.cameraManager)
                    .ignoresSafeArea(edges: .top)

                // Bounding boxes
                ForEach(viewModel.detections) { det in
                    BoundingBoxView(detection: det, viewSize: camSize) {}
                }

                // Hand skeleton
                if let lm = viewModel.basketManager.landmarks {
                    HandOverlayView(landmarks: lm, size: camSize)
                }
            }

            // HUD
            VStack {
                CameraTopBarView(
                    title:          "GroceryScanner",
                    statusText:     viewModel.statusText,
                    formattedTotal: cartService.formattedTotal,
                    isCartEmpty:    cartService.items.isEmpty,
                    onFlashTapped:  { viewModel.toggleFlash() }
                )
                Spacer()
                if let toast = viewModel.activeToast {
                    BasketToastView(event: toast)
                        .padding(.horizontal, geo.size.width * 0.04)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Debug panel
            #if DEBUG
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    DebugPanelView(
                        isHandDetected: viewModel.debugHasLandmarks,
                        phase:          viewModel.debugPhase,
                        boxArea:        viewModel.debugBoxArea,
                        overlapRatio:   viewModel.debugOverlapRatio,
                        areaRatio:      viewModel.debugAreaRatio
                    )
                    .padding(.leading, 10).padding(.bottom, 10)
                    Spacer()
                }
            }
            #endif
        }
        .animation(.spring(response: 0.35), value: viewModel.activeToast?.id)
    }
}

// MARK: - CartPanelView (shared)

struct CartPanelView: View {
    @ObservedObject var cartService: CartServiceImpl
    @EnvironmentObject var router: Router
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keranjang Belanja")
                        .font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    Text("\(cartService.totalItems) item")
                        .font(.system(size: 13)).foregroundStyle(Color.appTextMuted)
                }
                Spacer()
                // Hapus semua — hanya muncul kalau ada item
                if !cartService.items.isEmpty {
                    Button {
                        showClearConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundStyle(.red.opacity(0.8))
                            .frame(width: 36, height: 36)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "Hapus semua item dari keranjang?",
                        isPresented: $showClearConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Hapus Semua", role: .destructive) {
                            cartService.clearCart()
                        }
                        Button("Batal", role: .cancel) {}
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Divider().background(Color.appDivider)

            if cartService.items.isEmpty {
                CartEmptyStateView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(cartService.items) { item in
                            CartItemRowView(
                                item: item,
                                onIncrease: { cartService.increaseQuantity(for: item) },
                                onDecrease: { cartService.decreaseQuantity(for: item) },
                                onDelete:   { cartService.removeItem(item) }
                            )
                            Divider().background(Color.appDivider).padding(.leading, 16)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            CartSummaryFooterView(
                totalItems:     cartService.totalItems,
                formattedTotal: cartService.formattedTotal,
                isCartEmpty:    cartService.items.isEmpty,
                onPayTapped:    { router.navigate(to: .checkout) }
            )
        }
        .background(Color.appSurface)
    }
}
