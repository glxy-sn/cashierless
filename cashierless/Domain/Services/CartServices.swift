//
//  CartServices.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import Foundation
import Combine

// MARK: - CartService Protocol

protocol CartService: AnyObject {
    var items: [CartItem] { get }
    var totalPrice: Int { get }
    var totalItems: Int { get }
    var formattedTotal: String { get }

    func addProduct(_ product: Product, source: CartItemSource)
    func increaseQuantity(for item: CartItem)
    func decreaseQuantity(for item: CartItem)
    func removeItem(_ item: CartItem)
    func clearCart()
}

// MARK: - CartServiceImpl

final class CartServiceImpl: CartService, ObservableObject {

    @Published private(set) var items: [CartItem] = []

    /// Track IDs yang sudah ter-bind ke barcode scan — ditampilkan hijau di bbox
    @Published private(set) var boundTrackIDs: Set<UUID> = []

    var totalPrice: Int  { items.reduce(0) { $0 + $1.subtotal } }
    var totalItems: Int  { items.reduce(0) { $0 + $1.quantity } }

    var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp "
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: totalPrice)) ?? "Rp \(totalPrice)"
    }

    func addProduct(_ product: Product, source: CartItemSource) {
        if let idx = items.firstIndex(where: { $0.product.id == product.id }) {
            items[idx].quantity += 1
        } else {
            items.append(CartItem(id: UUID(), product: product, quantity: 1, source: source))
        }
    }

    /// Bind track UUID ke cart item — bbox akan berubah warna hijau
    func bindTrack(_ trackID: UUID, to product: Product) {
        boundTrackIDs.insert(trackID)
    }

    func isTrackBound(_ trackID: UUID) -> Bool {
        boundTrackIDs.contains(trackID)
    }

    func increaseQuantity(for item: CartItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].quantity += 1
    }

    func decreaseQuantity(for item: CartItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        if items[idx].quantity > 1 { items[idx].quantity -= 1 }
        else { items.remove(at: idx) }
    }

    func removeItem(_ item: CartItem) { items.removeAll { $0.id == item.id } }

    func clearCart() {
        items.removeAll()
        boundTrackIDs.removeAll()
    }
}
