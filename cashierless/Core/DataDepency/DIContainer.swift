//
//  DIContainer.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import Foundation
import Combine

final class DIContainer: ObservableObject {

    static let shared = DIContainer()
    
    let cartService:      CartServiceImpl  = CartServiceImpl()
    lazy var cameraManager:   CameraManager   = CameraManager()
    lazy var barcodeEngine:   BarcodeEngine   = BarcodeEngine()
    lazy var inferenceEngine: InferenceEngine = InferenceEngine()
    lazy var basketManager:   BasketManager   = BasketManager()

    private init() {}
}

