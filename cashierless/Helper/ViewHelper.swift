//
//  ViewHelper.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import SwiftUI

// MARK: - Color Constants

extension Color {
    static let appGreen     = Color(red: 0.365, green: 0.792, blue: 0.647)
    static let appGreenDark = Color(red: 0.059, green: 0.431, blue: 0.337)
    static let appGreenDeep = Color(red: 0.031, green: 0.314, blue: 0.251)
    static let appGreenBg   = Color(red: 0.051, green: 0.157, blue: 0.125)
    static let appSurface   = Color(red: 0.067, green: 0.067, blue: 0.071)
    static let appBackground = Color(red: 0.039, green: 0.039, blue: 0.071)
    static let appDivider   = Color(red: 0.118, green: 0.118, blue: 0.118)
    static let appTextMuted = Color(red: 0.333, green: 0.333, blue: 0.333)
}

// MARK: - Int formatter

extension Int {
    var formattedIDR: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp "
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: self)) ?? "Rp \(self)"
    }
}
