//
//  ProductDatabase.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import Foundation

// MARK: - ProductDatabase

enum ProductDatabase {

    static let products: [Int: Product] = [
        0:  Product(id: 0,  name: "Aqua",                price: 4_000,  emoji: "💧"),
        1:  Product(id: 1,  name: "Chitato",             price: 12_000, emoji: "🥔"),
        2:  Product(id: 2,  name: "Fanta",               price: 7_000,  emoji: "🧃"),
        3:  Product(id: 3,  name: "Indomie",             price: 3_500,  emoji: "🍜"),
        4:  Product(id: 4,  name: "Lifebuoy",            price: 5_500,  emoji: "🧼"),
        5:  Product(id: 5,  name: "Oreo",                price: 11_500, emoji: "🍫"),
        6:  Product(id: 6,  name: "Pepsodent",           price: 15_000, emoji: "🦷"),
        7:  Product(id: 7,  name: "Pocari Sweat",        price: 8_500,  emoji: "💧"),
        8:  Product(id: 8,  name: "Roma Biskuit Kelapa", price: 6_000,  emoji: "🍘"),
        9:  Product(id: 9,  name: "Shampoo",             price: 15_000, emoji: "🧴"),
        10: Product(id: 10, name: "Sprite",              price: 7_000,  emoji: "🥤"),
        11: Product(id: 11, name: "Tissue",              price: 8_000,  emoji: "🧻"),
    ]

    static func product(for classIndex: Int) -> Product? { products[classIndex] }

    static func product(named name: String) -> Product? {
        products.values.first { $0.name.lowercased() == name.lowercased() }
    }
}
