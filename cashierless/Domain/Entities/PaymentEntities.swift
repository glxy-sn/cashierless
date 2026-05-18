//
//  PaymentEntities.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import Foundation

// MARK: - PaymentMethod

enum PaymentMethod: CaseIterable, Identifiable {
    case cash
    case qris
    case debit

    var id: Self { self }

    var title: String {
        switch self {
        case .cash:  return "Tunai"
        case .qris:  return "QRIS"
        case .debit: return "Kartu Debit"
        }
    }

    var icon: String {
        switch self {
        case .cash:  return "banknote"
        case .qris:  return "qrcode"
        case .debit: return "creditcard"
        }
    }
}

// MARK: - CheckoutResult

struct CheckoutResult: Identifiable {
    let id:            UUID = UUID()
    let items:         [CartItem]
    let totalPrice:    Int
    let paymentMethod: PaymentMethod
    let amountPaid:    Int          // untuk cash
    let change:        Int          // kembalian (cash only)
    let timestamp:     Date = Date()

    var formattedTotal:   String { totalPrice.formattedIDR }
    var formattedChange:  String { change.formattedIDR }
    var formattedPaid:    String { amountPaid.formattedIDR }

    var receiptNumber: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        return "TRX-\(f.string(from: timestamp))"
    }
}

// MARK: - CashDenomination (pilihan cepat uang tunai)

struct CashDenomination: Identifiable {
    let id:    Int
    let value: Int
    var formatted: String { value.formattedIDR }
}

extension CashDenomination {
    static let presets: [CashDenomination] = [
        .init(id: 0, value: 5_000),
        .init(id: 1, value: 10_000),
        .init(id: 2, value: 20_000),
        .init(id: 3, value: 50_000),
        .init(id: 4, value: 100_000),
        .init(id: 5, value: 50_000),
    ]
}


