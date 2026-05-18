//
//  Entities.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import Foundation
import CoreGraphics

// MARK: - Product

struct Product: Identifiable, Hashable {
    let id: Int
    let name: String
    let price: Int
    let emoji: String

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp "
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: price)) ?? "Rp \(price)"
    }
}

// MARK: - CartItem

struct CartItem: Identifiable, Equatable {
    let id: UUID
    let product: Product
    var quantity: Int
    let source: CartItemSource

    var subtotal: Int { product.price * quantity }

    var formattedSubtotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp "
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: subtotal)) ?? "Rp \(subtotal)"
    }

    static func == (lhs: CartItem, rhs: CartItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - CartItemSource

enum CartItemSource {
    case detection
    case barcode

    var label: String {
        switch self {
        case .detection: return "deteksi otomatis"
        case .barcode:   return "scan barcode"
        }
    }
}

// MARK: - DetectionResult

struct DetectionResult: Identifiable {
    let id: UUID
    let classIndex: Int
    let confidence: Float
    let boundingBox: CGRect

    init(classIndex: Int, confidence: Float, boundingBox: CGRect) {
        self.id          = UUID()
        self.classIndex  = classIndex
        self.confidence  = confidence
        self.boundingBox = boundingBox
    }

    init(id: UUID, classIndex: Int, confidence: Float, boundingBox: CGRect) {
        self.id          = id
        self.classIndex  = classIndex
        self.confidence  = confidence
        self.boundingBox = boundingBox
    }

    var product: Product? { ProductDatabase.product(for: classIndex) }

    var confidencePercent: String { String(format: "%.0f%%", confidence * 100) }
}

// MARK: - BarcodeResult

struct BarcodeResult {
    let value:      String
    let symbology:  String
    let scannedAt:  Date = Date()
}

// MARK: - BasketEvent

struct BasketEvent: Identifiable {
    let id:          UUID = UUID()
    let action:      BasketAction
    let productName: String
    let confidence:  Float
    let timestamp:   Date = Date()

    enum BasketAction { case put, take }
}
