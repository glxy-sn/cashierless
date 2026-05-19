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
            // Langsung DetectionView — tidak ada tab lagi
            DetectionView(
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
                        barcodeEngine:   container.barcodeEngine,
                        inferenceEngine: container.inferenceEngine,
                        basketManager:   container.basketManager,
                        cartService:     container.cartService
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
