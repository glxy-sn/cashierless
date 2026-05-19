//
//  Components.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//

import SwiftUI
import UIKit

// MARK: - CartItemRowView

struct CartItemRowView: View {
    let item: CartItem
    let onIncrease: () -> Void
    let onDecrease: () -> Void
    let onDelete:   () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.appGreen).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.name)
                    .font(.system(size: 13)).foregroundStyle(.white).lineLimit(1)
                Text(item.source.label)
                    .font(.system(size: 10)).foregroundStyle(Color.appTextMuted)
            }
            Spacer()
            QuantityStepperView(quantity: item.quantity, onIncrease: onIncrease, onDecrease: onDecrease)
            Text(item.formattedSubtotal)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(minWidth: 64, alignment: .trailing).monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Hapus", systemImage: "trash")
            }
        }
    }
}

// MARK: - QuantityStepperView

struct QuantityStepperView: View {
    let quantity: Int
    let onIncrease: () -> Void
    let onDecrease: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onDecrease) {
                Image(systemName: "minus").font(.system(size: 11, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.08)).foregroundStyle(Color(white: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)

            Text("\(quantity)").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(width: 26).monospacedDigit()

            Button(action: onIncrease) {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Color.appGreenDeep).foregroundStyle(Color.appGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - CartSummaryFooterView

struct CartSummaryFooterView: View {
    let totalItems: Int
    let formattedTotal: String
    let isCartEmpty: Bool
    let onPayTapped: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Color.appDivider)
            VStack(spacing: 10) {
                HStack {
                    Text("Subtotal (\(totalItems) item)").font(.system(size: 13)).foregroundStyle(Color.appTextMuted)
                    Spacer()
                    Text(formattedTotal).font(.system(size: 13)).foregroundStyle(Color.appTextMuted).monospacedDigit()
                }
                HStack {
                    Text("Total").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    Spacer()
                    Text(formattedTotal).font(.system(size: 19, weight: .medium))
                        .foregroundStyle(isCartEmpty ? Color.appTextMuted : Color.appGreen).monospacedDigit()
                }
                Button(action: onPayTapped) {
                    Label("Bayar Sekarang", systemImage: "creditcard")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(isCartEmpty ? Color.white.opacity(0.06) : Color.appGreenDark)
                        .foregroundStyle(isCartEmpty ? Color.appTextMuted : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(isCartEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
    }
}

// MARK: - CartEmptyStateView

struct CartEmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "cart").font(.system(size: 44)).foregroundStyle(Color(white: 0.18))
            Text("Keranjang kosong").font(.system(size: 15, weight: .medium)).foregroundStyle(Color(white: 0.27))
            Text("Scan produk dan tap kotak deteksi").font(.system(size: 12)).foregroundStyle(Color(white: 0.2)).multilineTextAlignment(.center)
            Spacer()
        }.padding(.horizontal, 24)
    }
}

// MARK: - BoundingBoxView

struct BoundingBoxView: View {
    let detection: DetectionResult
    let viewSize:  CGSize
    let isBound:   Bool      // true = ter-bind ke barcode scan → warna hijau
    let onTap:     () -> Void

    private var rect: CGRect {
        CGRect(
            x:      detection.boundingBox.minX * viewSize.width,
            y:      detection.boundingBox.minY * viewSize.height,
            width:  detection.boundingBox.width  * viewSize.width,
            height: detection.boundingBox.height * viewSize.height
        )
    }

    private var boxColor: Color {
        if isBound { return Color.appGreen }
        return detection.confidence > 0.75
            ? Color.appGreen
            : Color(red: 0.937, green: 0.624, blue: 0.153)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(boxColor, lineWidth: isBound ? 3 : 2)
                .background(boxColor.opacity(isBound ? 0.12 : 0.06))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)

            if let product = detection.product {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if isBound {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 8))
                                .foregroundStyle(boxColor)
                        }
                        Text(product.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(boxColor)
                    }
                    HStack(spacing: 5) {
                        Text(product.formattedPrice)
                            .font(.system(size: 9)).foregroundStyle(.white)
                        Text(detection.confidencePercent)
                            .font(.system(size: 9)).foregroundStyle(Color(white: 0.5))
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .position(x: rect.minX + 50, y: rect.minY - 20)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
    }
}

// MARK: - CameraTopBarView

struct CameraTopBarView: View {
    let title:          String
    let statusText:     String
    let formattedTotal: String
    let isCartEmpty:    Bool
    let isFlashOn:      Bool
    let isHandDetected: Bool
    let onFlashTapped:  () -> Void

    var body: some View {
        HStack(alignment: .top) {

            // Kiri: title + status
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "cart")
                        .font(.system(size: 12)).foregroundStyle(Color.appGreen)
                    Text(title)
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                }
                Text(statusText)
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.55)).clipShape(Capsule())
            }

            Spacer()

            // Kanan: flash button saja
            Button(action: onFlashTapped) {
                Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isFlashOn ? Color(red: 1.0, green: 0.85, blue: 0.0) : .white)
                    .frame(width: 36, height: 36)
                    .background(isFlashOn ? Color(red: 0.4, green: 0.35, blue: 0.0) : .white.opacity(0.15))
                    .clipShape(Circle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.top, 12)
    }
}

// MARK: - AppTabBarView

struct AppTabBarView: View {
    @Binding var selectedTab: AppTab

    enum AppTab: CaseIterable {
        case detection, scanBarcode

        var title: String {
            switch self {
            case .detection:   return "Deteksi Otomatis"
            case .scanBarcode: return "Scan Barcode"
            }
        }
        var icon: String {
            switch self {
            case .detection:   return "sparkles"
            case .scanBarcode: return "barcode.viewfinder"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 24))
                        Text(tab.title).font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity).frame(minHeight: 52)
                    .foregroundStyle(selectedTab == tab ? Color.appGreen : Color(white: 0.18))
                    .background(
                        selectedTab == tab
                            ? RoundedRectangle(cornerRadius: 12).fill(Color.appGreenBg)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appGreenDark, lineWidth: 0.5))
                            : nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 20)
        .background(Color.appBackground)
        .overlay(alignment: .top) { Divider().background(Color.appDivider) }
    }
}

// MARK: - BasketToastView

struct BasketToastView: View {
    let event: BasketEvent

    private var isPut: Bool { event.action == .put }
    private var accentColor: Color { isPut ? Color.appGreen : Color(red: 1.0, green: 0.58, blue: 0.0) }
    private var borderColor: Color { isPut ? Color.appGreenDark : Color(red: 0.6, green: 0.3, blue: 0.0) }
    private var icon: String { isPut ? "arrow.down.circle.fill" : "arrow.up.circle.fill" }
    private var label: String { isPut ? "Dimasukkan" : "Dikeluarkan" }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(event.productName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("gerakan tangan terdeteksi")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.black.opacity(0.88))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(borderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

// MARK: - ScanResultBannerView

struct ScanResultBannerView: View {
    let result: BarcodeResult
    let productName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").font(.system(size: 17)).foregroundStyle(Color.appGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(productName) · ditambahkan")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                Text("\(result.symbology) · \(result.value)")
                    .font(.system(size: 9)).foregroundStyle(Color.appGreenDark)
            }
            Spacer()
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(Color.appGreenDeep.opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.appGreenDark, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

// MARK: - ViewfinderOverlayView

struct ViewfinderOverlayView: View {
    var body: some View {
        GeometryReader { geo in
            let bW = geo.size.width  * 0.72
            let bH = geo.size.height * 0.48
            let bX = (geo.size.width  - bW) / 2
            let bY = (geo.size.height - bH) / 2

            ZStack {
                Color.black.opacity(0.45).mask(
                    Rectangle().overlay(
                        RoundedRectangle(cornerRadius: 10).frame(width: bW, height: bH).blendMode(.destinationOut)
                    ).compositingGroup()
                )
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(white: 0.15), lineWidth: 1.5).frame(width: bW, height: bH)
                CornerAccentsView(
                    rect: CGRect(x: bX, y: bY, width: bW, height: bH),
                    color: Color.appGreen, length: 20, thickness: 3
                )
                Text("Arahkan barcode ke area ini")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    .position(x: geo.size.width / 2, y: bY + bH + 28)
            }
        }
    }
}

// MARK: - CornerAccentsView

struct CornerAccentsView: View {
    let rect: CGRect; let color: Color; let length: CGFloat; let thickness: CGFloat

    var body: some View {
        ZStack {
            cornerPath(from: CGPoint(x: rect.minX, y: rect.minY + length), to: CGPoint(x: rect.minX, y: rect.minY), then: CGPoint(x: rect.minX + length, y: rect.minY))
            cornerPath(from: CGPoint(x: rect.maxX - length, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.minY), then: CGPoint(x: rect.maxX, y: rect.minY + length))
            cornerPath(from: CGPoint(x: rect.minX, y: rect.maxY - length), to: CGPoint(x: rect.minX, y: rect.maxY), then: CGPoint(x: rect.minX + length, y: rect.maxY))
            cornerPath(from: CGPoint(x: rect.maxX - length, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.maxY), then: CGPoint(x: rect.maxX, y: rect.maxY - length))
        }
    }

    private func cornerPath(from a: CGPoint, to b: CGPoint, then c: CGPoint) -> some View {
        Path { p in p.move(to: a); p.addLine(to: b); p.addLine(to: c) }
            .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
    }
}

// MARK: - DebugPanelView (DEBUG only)

#if DEBUG
struct DebugPanelView: View {
    let isHandDetected: Bool
    let phase:          String
    let boxArea:        CGFloat
    let overlapRatio:   CGFloat
    let areaRatio:      CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: "hand.raised").font(.system(size: 10)).foregroundStyle(Color(white: 0.5))
                Text("Tangan").font(.system(size: 9)).foregroundStyle(Color(white: 0.7))
                Text("1").font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color(white: 0.1)).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Group {
                Text(isHandDetected ? "Hand ✓" : "Tidak terdeteksi").foregroundStyle(isHandDetected ? Color.appGreen : .red)
                Text("Phase: \(phase)")
                Text(String(format: "Box: %.4f", boxArea))
                Text(String(format: "Overlap: %.0f%%", overlapRatio * 100))
                Text(String(format: "Ratio: %.1f%%", areaRatio * 100))
            }
            .font(.system(size: 8, design: .monospaced)).foregroundStyle(Color(red: 0, green: 1, blue: 0))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.black.opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
#endif
