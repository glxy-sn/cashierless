////
////  DetectionView.swift
////  cashierless
////
////  Created by Shafa Tiara on 18/05/26.
////
//
//import SwiftUI
//import Combine
//import UIKit
//
//// MARK: - DetectionViewModel
//
//@MainActor
//final class DetectionViewModel: ObservableObject {
//
//    @Published var detections:      [DetectionResult] = []
//    @Published var isModelLoaded:   Bool    = false
//    @Published var isFlashOn:       Bool    = false
//    @Published var activeToast:     BasketEvent? = nil
//    @Published var statusText:      String  = "Memuat model..."
//    @Published var isBarcodeScannerActive: Bool   = false
//    @Published var unknownBarcodeValue:    String? = nil
//
//    /// Produk yang menunggu untuk di-bind ke track setelah kamera aktif kembali
//    private var pendingBindProduct: Product? = nil
//
//    #if DEBUG
//    @Published var debugPhase:        String  = "idle"
//    @Published var debugBoxArea:      CGFloat = 0
//    @Published var debugOverlapRatio: CGFloat = 0
//    @Published var debugAreaRatio:    CGFloat = 0
//    @Published var debugIsHolding:    Bool    = false
//    @Published var debugHasLandmarks: Bool    = false
//    #endif
//
//    let cameraManager:   CameraManager
//    let barcodeEngine:   BarcodeEngine
//    let inferenceEngine: InferenceEngine
//    let basketManager:   BasketManager
//    private let cartService: CartServiceImpl
//
//    init(cameraManager: CameraManager, barcodeEngine: BarcodeEngine,
//         inferenceEngine: InferenceEngine, basketManager: BasketManager,
//         cartService: CartServiceImpl) {
//        self.cameraManager   = cameraManager
//        self.barcodeEngine   = barcodeEngine
//        self.inferenceEngine = inferenceEngine
//        self.basketManager   = basketManager
//        self.cartService     = cartService
//        bindAll()
//    }
//
//    // MARK: - Binding
//
//    private var cancellables = Set<AnyCancellable>()
//
//    private func bindAll() {
//        basketManager.addToCart = { [cartService] product, trackID in
//            cartService.addProduct(product, source: .detection)
//            if let id = trackID {
//                cartService.bindTrack(id, to: product)
//            }
//        }
//        basketManager.removeFromCart = { [cartService] product in
//            if let item = cartService.items.first(where: { $0.product.id == product.id }) {
//                cartService.decreaseQuantity(for: item)
//            } else if let last = cartService.items.last {
//                cartService.decreaseQuantity(for: last)
//            }
//        }
//        basketManager.isProductInCart = { [cartService] product in
//            cartService.items.contains { $0.product.id == product.id }
//        }
//
//        let processor = basketManager.handPoseProcessor
//        cameraManager.onFrame = { [weak self] pixelBuffer in
//            self?.inferenceEngine.run(on: pixelBuffer)
//            processor.processFrame(pixelBuffer: pixelBuffer)
//        }
//
//        inferenceEngine.onDetections = { [weak self] detections in
//            guard let self else { return }
//            self.detections = detections
//            self.updateStatus()
//
//            // Resolve pending bind dari barcode scan sebelumnya
//            if let product = self.pendingBindProduct, !detections.isEmpty {
//                let candidates = detections.filter { $0.classIndex == product.id }
//                let centerFrame = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
//                if let bestTrack = candidates.max(by: { a, b in
//                    self.iouRect(a.boundingBox, centerFrame) < self.iouRect(b.boundingBox, centerFrame)
//                }) {
//                    self.cartService.bindTrack(bestTrack.id, to: product)
//                    self.pendingBindProduct = nil   // clear setelah berhasil di-bind
//                }
//            }
//        }
//
//        inferenceEngine.onModelLoaded = { [weak self] in
//            self?.isModelLoaded = true
//            self?.updateStatus()
//        }
//        if inferenceEngine.isModelLoaded { isModelLoaded = true; updateStatus() }
//
//        basketManager.onBasketEvent = { [weak self] event in
//            guard let self else { return }
//            withAnimation(.spring(response: 0.35)) { self.activeToast = event }
//            Task {
//                try? await Task.sleep(nanoseconds: 2_500_000_000)
//                withAnimation { self.activeToast = nil }
//            }
//        }
//
//        // Barcode scan → lookup barcode, kalau tidak dikenali tampilkan alert
//        barcodeEngine.onScan = { [weak self] result in
//            Task { @MainActor in
//                guard let self else { return }
//
//                guard let product = ProductDatabase.product(forBarcode: result.value) else {
//                    withAnimation(.easeInOut(duration: 0.25)) { self.isBarcodeScannerActive = false }
//                    self.barcodeEngine.stop()
//                    self.cameraManager.start()
//                    self.unknownBarcodeValue = result.value
//                    return
//                }
//
//                self.cartService.addProduct(product, source: .barcode)
//                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
//
//                // Simpan pending bind — akan di-bind saat kamera aktif kembali
//                // dan deteksi produk muncul di frame
//                self.pendingBindProduct = product
//
//                let event = BasketEvent(action: .put, productName: product.name, confidence: 1.0)
//                withAnimation(.spring(response: 0.35)) { self.activeToast = event }
//                Task {
//                    try? await Task.sleep(nanoseconds: 2_000_000_000)
//                    withAnimation { self.activeToast = nil }
//                }
//
//                try? await Task.sleep(nanoseconds: 800_000_000)
//                withAnimation(.easeInOut(duration: 0.25)) { self.isBarcodeScannerActive = false }
//                self.barcodeEngine.stop()
//                self.cameraManager.start()
//            }
//        }
//
//        #if DEBUG
//        basketManager.$debugPhase        .receive(on: RunLoop.main).assign(to: &$debugPhase)
//        basketManager.$debugBoxArea      .receive(on: RunLoop.main).assign(to: &$debugBoxArea)
//        basketManager.$debugOverlapRatio .receive(on: RunLoop.main).assign(to: &$debugOverlapRatio)
//        basketManager.$debugAreaRatio    .receive(on: RunLoop.main).assign(to: &$debugAreaRatio)
//        basketManager.$debugIsHolding    .receive(on: RunLoop.main).assign(to: &$debugIsHolding)
//        basketManager.$landmarks
//            .map { $0 != nil }
//            .receive(on: RunLoop.main)
//            .assign(to: &$debugHasLandmarks)
//        #endif
//    }
//
//    // MARK: - Intents
//
//    func onAppear() {
//        cameraManager.start()
//        updateStatus()
//    }
//
//    func onDisappear() {
//        isFlashOn = false
//        cameraManager.setTorch(false)
//        cameraManager.stop()
//        barcodeEngine.stop()
//    }
//
//    func toggleFlash() { isFlashOn.toggle(); cameraManager.setTorch(isFlashOn) }
//
//    func openBarcodeScanner() {
//        withAnimation(.easeInOut(duration: 0.25)) { isBarcodeScannerActive = true }
//        cameraManager.stop()
//        barcodeEngine.start()
//    }
//
//    func closeBarcodeScanner() {
//        withAnimation(.easeInOut(duration: 0.25)) { isBarcodeScannerActive = false }
//        barcodeEngine.stop()
//        cameraManager.start()
//    }
//
//    func updateStatus() {
//        let objText = detections.isEmpty ? "" : " · \(detections.count) objek"
//        statusText  = isModelLoaded ? "Siap\(objText)" : "Memuat model..."
//    }
//
//    private func iouRect(_ a: CGRect, _ b: CGRect) -> CGFloat {
//        let inter = a.intersection(b)
//        guard !inter.isNull else { return 0 }
//        let iA = inter.width * inter.height
//        let uA = a.width * a.height + b.width * b.height - iA
//        return uA > 0 ? iA / uA : 0
//    }
//}
//
//// MARK: - DetectionView
//
//struct DetectionView: View {
//
//    @StateObject private var viewModel: DetectionViewModel
//    private let cartService: CartServiceImpl
//
//    init(cameraManager: CameraManager, barcodeEngine: BarcodeEngine,
//         inferenceEngine: InferenceEngine, basketManager: BasketManager,
//         cartService: CartServiceImpl) {
//        self.cartService = cartService
//        _viewModel = StateObject(wrappedValue: DetectionViewModel(
//            cameraManager:   cameraManager,
//            barcodeEngine:   barcodeEngine,
//            inferenceEngine: inferenceEngine,
//            basketManager:   basketManager,
//            cartService:     cartService
//        ))
//    }
//
//    var body: some View {
//        GeometryReader { geo in
//            VStack(spacing: 0) {
//                cameraSection(geo: geo).frame(height: geo.size.height * 0.58)
//                CartPanelView(cartService: cartService)
//            }
//        }
//        .background(Color.appBackground)
//        .onAppear   { viewModel.onAppear() }
//        .onDisappear { viewModel.onDisappear() }
//        .onReceive(viewModel.$detections) { newDetections in
//            let camSize = CGSize(width: UIScreen.main.bounds.width,
//                                 height: UIScreen.main.bounds.height * 0.58)
//            viewModel.basketManager.processFrame(detections: newDetections, viewSize: camSize)
//        }
//        .alert(
//            "Barcode Tidak Dikenali",
//            isPresented: Binding(
//                get: { viewModel.unknownBarcodeValue != nil },
//                set: { if !$0 { viewModel.unknownBarcodeValue = nil } }
//            ),
//            presenting: viewModel.unknownBarcodeValue
//        ) { _ in
//            Button("OK") { viewModel.unknownBarcodeValue = nil }
//        } message: { barcode in
//            Text("Barcode \(barcode) belum terdaftar di database produk. Tambahkan produk secara manual.")
//        }
//    }
//
//    // MARK: - Camera section
//
//    @ViewBuilder
//    private func cameraSection(geo: GeometryProxy) -> some View {
//        let camSize = CGSize(width: geo.size.width, height: geo.size.height * 0.58)
//
//        ZStack {
//            // ── Mode deteksi ──────────────────────────────────────────────
//            if !viewModel.isBarcodeScannerActive {
//                if viewModel.cameraManager.error == .permissionDenied {
//                    Color.black; CameraPermissionDeniedView()
//                } else {
//                    CameraPreviewView(cameraManager: viewModel.cameraManager)
//                        .ignoresSafeArea(edges: .top)
//                    ForEach(viewModel.detections) { det in
//                        BoundingBoxView(
//                            detection: det,
//                            viewSize:  camSize,
//                            isBound:   cartService.isTrackBound(det.id)
//                        ) {}
//                    }
//                    if let lm = viewModel.basketManager.landmarks {
//                        HandOverlayView(landmarks: lm, size: camSize)
//                    }
//                }
//            }
//
//            // ── Mode barcode scanner ───────────────────────────────────────
//            if viewModel.isBarcodeScannerActive {
//                BarcodeCameraPreviewView(barcodeEngine: viewModel.barcodeEngine)
//                    .ignoresSafeArea(edges: .top)
//                ViewfinderOverlayView()
//
//                // Tombol tutup scanner
//                VStack {
//                    HStack {
//                        Spacer()
//                        Button(action: { viewModel.closeBarcodeScanner() }) {
//                            Image(systemName: "xmark")
//                                .font(.system(size: 16, weight: .semibold))
//                                .foregroundStyle(.white)
//                                .frame(width: 36, height: 36)
//                                .background(.black.opacity(0.55))
//                                .clipShape(Circle())
//                        }
//                        .buttonStyle(.plain)
//                        .padding(.top, 16)
//                        .padding(.trailing, 16)
//                    }
//                    Spacer()
//                }
//                .zIndex(10)
//            }
//
//            // ── HUD overlay (selalu tampil) ────────────────────────────────
//            VStack {
//                if !viewModel.isBarcodeScannerActive {
//                    CameraTopBarView(
//                        title:          "GroceryScanner",
//                        statusText:     viewModel.statusText,
//                        formattedTotal: cartService.formattedTotal,
//                        isCartEmpty:    cartService.items.isEmpty,
//                        onFlashTapped:  { viewModel.toggleFlash() }
//                    )
//                }
//                Spacer()
//
//                // Toast notifikasi
//                if let toast = viewModel.activeToast {
//                    BasketToastView(event: toast)
//                        .padding(.horizontal, geo.size.width * 0.04)
//                        .padding(.bottom, viewModel.isBarcodeScannerActive ? 50 : 12)
//                        .transition(.move(edge: .bottom).combined(with: .opacity))
//                }
//
//                // Floating barcode button — hanya di mode deteksi
//                if !viewModel.isBarcodeScannerActive {
//                    HStack {
//                        Spacer()
//                        Button(action: { viewModel.openBarcodeScanner() }) {
//                            HStack(spacing: 8) {
//                                Image(systemName: "barcode.viewfinder")
//                                    .font(.system(size: 16, weight: .medium))
//                                Text("Scan Barcode")
//                                    .font(.system(size: 13, weight: .medium))
//                            }
//                            .foregroundStyle(.white)
//                            .padding(.horizontal, 16)
//                            .padding(.vertical, 10)
//                            .background(.black.opacity(0.65))
//                            .overlay(
//                                Capsule().stroke(Color.appGreen.opacity(0.6), lineWidth: 1)
//                            )
//                            .clipShape(Capsule())
//                        }
//                        .buttonStyle(.plain)
//                        .padding(.trailing, 14)
//                        .padding(.bottom, 12)
//                    }
//                }
//            }
//
//            // ── Debug panel ───────────────────────────────────────────────
//            #if DEBUG
//            if !viewModel.isBarcodeScannerActive {
//                VStack {
//                    Spacer()
//                    HStack(alignment: .bottom) {
//                        DebugPanelView(
//                            isHandDetected: viewModel.debugHasLandmarks,
//                            phase:          viewModel.debugPhase,
//                            boxArea:        viewModel.debugBoxArea,
//                            overlapRatio:   viewModel.debugOverlapRatio,
//                            areaRatio:      viewModel.debugAreaRatio
//                        )
//                        .padding(.leading, 10).padding(.bottom, 48)
//                        Spacer()
//                    }
//                }
//            }
//            #endif
//        }
//        .animation(.easeInOut(duration: 0.25), value: viewModel.isBarcodeScannerActive)
//        .animation(.spring(response: 0.35), value: viewModel.activeToast?.id)
//    }
//}
//
//// MARK: - CartPanelView (shared)
//
//struct CartPanelView: View {
//    @ObservedObject var cartService: CartServiceImpl
//    @EnvironmentObject var router: Router
//    @State private var showClearConfirm = false
//
//    var body: some View {
//        VStack(spacing: 0) {
//            HStack {
//                VStack(alignment: .leading, spacing: 2) {
//                    Text("Keranjang Belanja")
//                        .font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
//                    Text("\(cartService.totalItems) item")
//                        .font(.system(size: 13)).foregroundStyle(Color.appTextMuted)
//                }
//                Spacer()
//                if !cartService.items.isEmpty {
//                    Button {
//                        showClearConfirm = true
//                    } label: {
//                        Image(systemName: "trash")
//                            .font(.system(size: 16))
//                            .foregroundStyle(.red.opacity(0.8))
//                            .frame(width: 36, height: 36)
//                            .background(Color.red.opacity(0.1))
//                            .clipShape(RoundedRectangle(cornerRadius: 8))
//                    }
//                    .buttonStyle(.plain)
//                    .confirmationDialog(
//                        "Hapus semua item dari keranjang?",
//                        isPresented: $showClearConfirm,
//                        titleVisibility: .visible
//                    ) {
//                        Button("Hapus Semua", role: .destructive) { cartService.clearCart() }
//                        Button("Batal", role: .cancel) {}
//                    }
//                }
//            }
//            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
//
//            Divider().background(Color.appDivider)
//
//            if cartService.items.isEmpty {
//                CartEmptyStateView()
//            } else {
//                ScrollView {
//                    LazyVStack(spacing: 0) {
//                        ForEach(cartService.items) { item in
//                            CartItemRowView(
//                                item: item,
//                                onIncrease: { cartService.increaseQuantity(for: item) },
//                                onDecrease: { cartService.decreaseQuantity(for: item) },
//                                onDelete:   { cartService.removeItem(item) }
//                            )
//                            Divider().background(Color.appDivider).padding(.leading, 16)
//                        }
//                    }
//                }
//            }
//            Spacer(minLength: 0)
//            CartSummaryFooterView(
//                totalItems:     cartService.totalItems,
//                formattedTotal: cartService.formattedTotal,
//                isCartEmpty:    cartService.items.isEmpty,
//                onPayTapped:    { router.navigate(to: .checkout) }
//            )
//        }
//        .background(Color.appSurface)
//    }
//}

import SwiftUI
import Combine
import UIKit

// MARK: - DetectionViewModel

@MainActor
final class DetectionViewModel: ObservableObject {

    @Published var detections:      [DetectionResult] = []
    @Published var isModelLoaded:   Bool    = false
    @Published var isFlashOn:       Bool    = false
    @Published var activeToast:     BasketEvent? = nil
    @Published var statusText:      String  = "Memuat model..."
    @Published var isBarcodeScannerActive: Bool   = false
    @Published var unknownBarcodeValue:    String? = nil

    /// Produk yang menunggu untuk di-bind ke track setelah kamera aktif kembali
    private var pendingBindProduct: Product? = nil

    #if DEBUG
    @Published var debugPhase:        String  = "idle"
    @Published var debugBoxArea:      CGFloat = 0
    @Published var debugOverlapRatio: CGFloat = 0
    @Published var debugAreaRatio:    CGFloat = 0
    @Published var debugIsHolding:    Bool    = false
    @Published var debugHasLandmarks: Bool    = false
    #endif

    let cameraManager:   CameraManager
    let barcodeEngine:   BarcodeEngine
    let inferenceEngine: InferenceEngine
    let basketManager:   BasketManager
    private let cartService: CartServiceImpl

    init(cameraManager: CameraManager, barcodeEngine: BarcodeEngine,
         inferenceEngine: InferenceEngine, basketManager: BasketManager,
         cartService: CartServiceImpl) {
        self.cameraManager   = cameraManager
        self.barcodeEngine   = barcodeEngine
        self.inferenceEngine = inferenceEngine
        self.basketManager   = basketManager
        self.cartService     = cartService
        bindAll()
    }

    // MARK: - Binding

    private var cancellables = Set<AnyCancellable>()

    private func bindAll() {
        basketManager.addToCart = { [cartService] product, trackID in
            cartService.addProduct(product, source: .detection)
            if let id = trackID {
                cartService.bindTrack(id, to: product)
            }
        }
        basketManager.removeFromCart = { [cartService] product in
            if let item = cartService.items.first(where: { $0.product.id == product.id }) {
                cartService.decreaseQuantity(for: item)
            } else if let last = cartService.items.last {
                cartService.decreaseQuantity(for: last)
            }
        }
        basketManager.isProductInCart = { [cartService] product in
            cartService.items.contains { $0.product.id == product.id }
        }

        let processor = basketManager.handPoseProcessor
        cameraManager.onFrame = { [weak self] pixelBuffer in
            self?.inferenceEngine.run(on: pixelBuffer)
            processor.processFrame(pixelBuffer: pixelBuffer)
        }

        inferenceEngine.onDetections = { [weak self] detections in
            guard let self else { return }
            self.detections = detections
            self.updateStatus()

            // Resolve pending bind dari barcode scan sebelumnya
            if let product = self.pendingBindProduct, !detections.isEmpty {
                let candidates = detections.filter { $0.classIndex == product.id }
                let centerFrame = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                if let bestTrack = candidates.max(by: { a, b in
                    self.iouRect(a.boundingBox, centerFrame) < self.iouRect(b.boundingBox, centerFrame)
                }) {
                    self.cartService.bindTrack(bestTrack.id, to: product)
                    self.pendingBindProduct = nil   // clear setelah berhasil di-bind
                }
            }
        }

        inferenceEngine.onModelLoaded = { [weak self] in
            self?.isModelLoaded = true
            self?.updateStatus()
        }
        if inferenceEngine.isModelLoaded { isModelLoaded = true; updateStatus() }

        basketManager.onBasketEvent = { [weak self] event in
            guard let self else { return }
            withAnimation(.spring(response: 0.35)) { self.activeToast = event }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { self.activeToast = nil }
            }
        }

        // Barcode scan → lookup barcode, kalau tidak dikenali tampilkan alert
        barcodeEngine.onScan = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                guard let product = ProductDatabase.product(forBarcode: result.value) else {
                    withAnimation(.easeInOut(duration: 0.25)) { self.isBarcodeScannerActive = false }
                    self.barcodeEngine.stop()
                    self.cameraManager.start()
                    self.unknownBarcodeValue = result.value
                    return
                }

                self.cartService.addProduct(product, source: .barcode)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                // Simpan pending bind — akan di-bind saat kamera aktif kembali
                // dan deteksi produk muncul di frame
                self.pendingBindProduct = product

                let event = BasketEvent(action: .put, productName: product.name, confidence: 1.0)
                withAnimation(.spring(response: 0.35)) { self.activeToast = event }
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { self.activeToast = nil }
                }

                try? await Task.sleep(nanoseconds: 800_000_000)
                withAnimation(.easeInOut(duration: 0.25)) { self.isBarcodeScannerActive = false }
                self.barcodeEngine.stop()
                self.cameraManager.start()
            }
        }

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

    func onAppear() {
        cameraManager.start()
        updateStatus()
    }

    func onDisappear() {
        isFlashOn = false
        cameraManager.setTorch(false)
        cameraManager.stop()
        barcodeEngine.stop()
    }

    func toggleFlash() { isFlashOn.toggle(); cameraManager.setTorch(isFlashOn) }

    func openBarcodeScanner() {
        withAnimation(.easeInOut(duration: 0.25)) { isBarcodeScannerActive = true }
        cameraManager.stop()
        barcodeEngine.start()
    }

    func closeBarcodeScanner() {
        withAnimation(.easeInOut(duration: 0.25)) { isBarcodeScannerActive = false }
        barcodeEngine.stop()
        cameraManager.start()
    }

    func updateStatus() {
        let objText = detections.isEmpty ? "" : " · \(detections.count) objek"
        statusText  = isModelLoaded ? "Siap\(objText)" : "Memuat model..."
    }

    private func iouRect(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull else { return 0 }
        let iA = inter.width * inter.height
        let uA = a.width * a.height + b.width * b.height - iA
        return uA > 0 ? iA / uA : 0
    }
}

// MARK: - DetectionView

struct DetectionView: View {

    @StateObject private var viewModel: DetectionViewModel
    private let cartService: CartServiceImpl

    init(cameraManager: CameraManager, barcodeEngine: BarcodeEngine,
         inferenceEngine: InferenceEngine, basketManager: BasketManager,
         cartService: CartServiceImpl) {
        self.cartService = cartService
        _viewModel = StateObject(wrappedValue: DetectionViewModel(
            cameraManager:   cameraManager,
            barcodeEngine:   barcodeEngine,
            inferenceEngine: inferenceEngine,
            basketManager:   basketManager,
            cartService:     cartService
        ))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                cameraSection(geo: geo).frame(height: geo.size.height * 0.58)
                CartPanelView(cartService: cartService, basketManager: viewModel.basketManager)
            }
        }
        .background(Color.appBackground)
        .onAppear   { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .onReceive(viewModel.$detections) { newDetections in
            let camSize = CGSize(width: UIScreen.main.bounds.width,
                                 height: UIScreen.main.bounds.height * 0.58)
            viewModel.basketManager.processFrame(detections: newDetections, viewSize: camSize)
        }
        .alert(
            "Barcode Tidak Dikenali",
            isPresented: Binding(
                get: { viewModel.unknownBarcodeValue != nil },
                set: { if !$0 { viewModel.unknownBarcodeValue = nil } }
            ),
            presenting: viewModel.unknownBarcodeValue
        ) { _ in
            Button("OK") { viewModel.unknownBarcodeValue = nil }
        } message: { barcode in
            Text("Barcode \(barcode) belum terdaftar di database produk. Tambahkan produk secara manual.")
        }
    }

    // MARK: - Camera section

    @ViewBuilder
    private func cameraSection(geo: GeometryProxy) -> some View {
        let camSize = CGSize(width: geo.size.width, height: geo.size.height * 0.58)

        ZStack {
            // ── Mode deteksi ──────────────────────────────────────────────
            if !viewModel.isBarcodeScannerActive {
                if viewModel.cameraManager.error == .permissionDenied {
                    Color.black; CameraPermissionDeniedView()
                } else {
                    CameraPreviewView(cameraManager: viewModel.cameraManager)
                        .ignoresSafeArea(edges: .top)
                    ForEach(viewModel.detections) { det in
                        BoundingBoxView(
                            detection: det,
                            viewSize:  camSize,
                            isBound:   cartService.isTrackBound(det.id)
                        ) {}
                    }
                    if let lm = viewModel.basketManager.landmarks {
                        HandOverlayView(landmarks: lm, size: camSize)
                    }
                }
            }

            // ── Mode barcode scanner ───────────────────────────────────────
            if viewModel.isBarcodeScannerActive {
                BarcodeCameraPreviewView(barcodeEngine: viewModel.barcodeEngine)
                    .ignoresSafeArea(edges: .top)
                ViewfinderOverlayView()

                // Tombol tutup scanner
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { viewModel.closeBarcodeScanner() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.55))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .zIndex(10)
            }

            // ── HUD overlay (selalu tampil) ────────────────────────────────
            VStack {
                if !viewModel.isBarcodeScannerActive {
                    CameraTopBarView(
                        title:          "GroceryScanner",
                        statusText:     viewModel.statusText,
                        formattedTotal: cartService.formattedTotal,
                        isCartEmpty:    cartService.items.isEmpty,
                        isFlashOn:      viewModel.isFlashOn,
                        isHandDetected: viewModel.basketManager.landmarks != nil,
                        onFlashTapped:  { viewModel.toggleFlash() }
                    )
                }
                Spacer()

                // Toast notifikasi
                if let toast = viewModel.activeToast {
                    BasketToastView(event: toast)
                        .padding(.horizontal, geo.size.width * 0.04)
                        .padding(.bottom, viewModel.isBarcodeScannerActive ? 50 : 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Floating barcode button — hanya di mode deteksi
                if !viewModel.isBarcodeScannerActive {
                    HStack {
                        Spacer()
                        Button(action: { viewModel.openBarcodeScanner() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Scan Barcode")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.65))
                            .overlay(
                                Capsule().stroke(Color.appGreen.opacity(0.6), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                        .padding(.bottom, 12)
                    }
                }
            }

        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isBarcodeScannerActive)
        .animation(.spring(response: 0.35), value: viewModel.activeToast?.id)
    }
}

// MARK: - CartPanelView (shared)

struct CartPanelView: View {
    @ObservedObject var cartService: CartServiceImpl
    let basketManager: BasketManager
    @EnvironmentObject var router: Router
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keranjang Belanja")
                        .font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    Text("\(cartService.totalItems) item")
                        .font(.system(size: 13)).foregroundStyle(Color.appTextMuted)
                }
                Spacer()
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
                            basketManager.clearHistory()
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
