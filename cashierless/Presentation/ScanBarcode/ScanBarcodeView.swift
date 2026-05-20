//
//  ScanBarcodeView.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import SwiftUI
import Combine
import UIKit

// MARK: - ScanBarcodeViewModel

@MainActor
final class ScanBarcodeViewModel: ObservableObject {

    @Published var isFlashOn:       Bool = false
    @Published var lastScanResult:  BarcodeResult? = nil
    @Published var lastProductName: String = ""
    @Published var showBanner:      Bool = false

    let barcodeEngine: BarcodeEngine
    private let cartService: CartServiceImpl

    init(barcodeEngine: BarcodeEngine, cartService: CartServiceImpl) {
        self.barcodeEngine = barcodeEngine
        self.cartService   = cartService
        bindEngine()
    }

    private func bindEngine() {
        barcodeEngine.onScan = { [weak self] result in
            Task { @MainActor [weak self] in self?.handleBarcodeScan(result) }
        }
    }

    func onAppear()    { /* Session dimanage oleh MainView */ }
    func onDisappear() { isFlashOn = false }

    func toggleFlash() { isFlashOn.toggle(); barcodeEngine.setTorch(isFlashOn) }

    func handleBarcodeScan(_ result: BarcodeResult) {
        let product = ProductDatabase.product(named: result.value)
        lastScanResult  = result
        lastProductName = product?.name ?? result.value
        cartService.addProduct(
            product ?? Product(id: -1, name: result.value, price: 0, emoji: "📦"),
            source: .barcode
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showBannerBriefly()
    }

    private func showBannerBriefly() {
        withAnimation(.spring(response: 0.3)) { showBanner = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { showBanner = false }
        }
    }
}

// MARK: - ScanBarcodeView

struct ScanBarcodeView: View {

    @StateObject private var viewModel: ScanBarcodeViewModel
    @StateObject private var viewModelBasket = BasketManager()
    private let cartService: CartServiceImpl

    init(barcodeEngine: BarcodeEngine, cartService: CartServiceImpl) {
        self.cartService = cartService
        _viewModel = StateObject(wrappedValue: ScanBarcodeViewModel(
            barcodeEngine: barcodeEngine,
            cartService:   cartService
        ))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                barcodeCameraSection(geo: geo).frame(height: geo.size.height * 0.58)
                CartPanelView(cartService: cartService, basketManager: viewModelBasket)
            }
        }
        .background(Color.appBackground)
        .onAppear   { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    @ViewBuilder
    private func barcodeCameraSection(geo: GeometryProxy) -> some View {
        ZStack {
            if viewModel.barcodeEngine.error == .permissionDenied {
                Color.black; CameraPermissionDeniedView()
            } else {
                BarcodeCameraPreviewView(barcodeEngine: viewModel.barcodeEngine)
                    .ignoresSafeArea(edges: .top)
                ViewfinderOverlayView()
            }
            VStack {
                CameraTopBarView(
                    title:          "GroceryScanner",
                    statusText:     "Scan barcode",
                    formattedTotal: cartService.formattedTotal,
                    isCartEmpty:    cartService.items.isEmpty,
                    isFlashOn:      viewModel.isFlashOn,
                    isHandDetected: false,
                    onFlashTapped:  { viewModel.toggleFlash() }
                )
                Spacer()
                if viewModel.showBanner, let result = viewModel.lastScanResult {
                    ScanResultBannerView(result: result, productName: viewModel.lastProductName)
                        .padding(.horizontal, geo.size.width * 0.04).padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35), value: viewModel.showBanner)
        }
    }
}

