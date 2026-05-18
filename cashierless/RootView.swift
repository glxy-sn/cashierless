//
//  RootView.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import SwiftUI
import Combine

// MARK: - RootView

struct RootView: View {

    @StateObject private var router    = Router()
    @StateObject private var container = DIContainer.shared

    var body: some View {
        NavigationStack(path: $router.path) {
            MainView(
                cameraManager:   container.cameraManager,
                barcodeEngine:   container.barcodeEngine,
                inferenceEngine: container.inferenceEngine,
                basketManager:   container.basketManager,
                cartService:     container.cartService
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .detection:
                    DetectionView(
                        cameraManager:   container.cameraManager,
                        inferenceEngine: container.inferenceEngine,
                        basketManager:   container.basketManager,
                        cartService:     container.cartService
                    )
                    .navigationBarBackButtonHidden()
                case .scanBarcode:
                    ScanBarcodeView(
                        barcodeEngine: container.barcodeEngine,
                        cartService:   container.cartService
                    )
                    .navigationBarBackButtonHidden()
                case .checkout:
                    CheckoutView(cartService: container.cartService)
                }
            }
        }
        .environmentObject(router)
        .preferredColorScheme(.dark)
    }
}

// MARK: - MainView

struct MainView: View {

    @State private var selectedTab: AppTabBarView.AppTab = .detection

    private let cameraManager:   CameraManager
    private let barcodeEngine:   BarcodeEngine
    private let inferenceEngine: InferenceEngine
    private let basketManager:   BasketManager
    private let cartService:     CartServiceImpl

    init(cameraManager: CameraManager, barcodeEngine: BarcodeEngine,
         inferenceEngine: InferenceEngine, basketManager: BasketManager,
         cartService: CartServiceImpl) {
        self.cameraManager   = cameraManager
        self.barcodeEngine   = barcodeEngine
        self.inferenceEngine = inferenceEngine
        self.basketManager   = basketManager
        self.cartService     = cartService
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                DetectionView(
                    cameraManager:   cameraManager,
                    inferenceEngine: inferenceEngine,
                    basketManager:   basketManager,
                    cartService:     cartService
                )
                .opacity(selectedTab == .detection ? 1 : 0)
                .allowsHitTesting(selectedTab == .detection)

                ScanBarcodeView(
                    barcodeEngine: barcodeEngine,
                    cartService:   cartService
                )
                .opacity(selectedTab == .scanBarcode ? 1 : 0)
                .allowsHitTesting(selectedTab == .scanBarcode)
            }
            .animation(.easeInOut(duration: 0.15), value: selectedTab)

            AppTabBarView(selectedTab: $selectedTab)
        }
        .background(Color.appBackground)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarHidden(true)
        .onChange(of: selectedTab) { _, newTab in
            switch newTab {
            case .detection:
                barcodeEngine.stop()
                cameraManager.start()
            case .scanBarcode:
                cameraManager.stop()
                barcodeEngine.start()
            }
        }
        .onAppear  { cameraManager.start() }
        .onDisappear { cameraManager.stop(); barcodeEngine.stop() }
    }
}
