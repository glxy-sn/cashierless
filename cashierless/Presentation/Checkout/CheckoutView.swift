import SwiftUI

// MARK: - CheckoutView

struct CheckoutView: View {

    @StateObject private var viewModel: CheckoutViewModel
    @Environment(\.dismiss) private var dismiss

    init(cartService: CartServiceImpl) {
        _viewModel = StateObject(wrappedValue: CheckoutViewModel(cartService: cartService))
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if viewModel.showSuccess, let result = viewModel.checkoutResult {
                SuccessView(result: result) {
                    viewModel.dismissSuccess()
                    dismiss()
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal:   .opacity
                ))
            } else {
                checkoutContent
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4), value: viewModel.showSuccess)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Pembayaran")
        .navigationBarBackButtonHidden(false)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.onDismiss = { dismiss() }
        }
    }

    // MARK: - Checkout Content

    private var checkoutContent: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {

                    // Order summary
                    OrderSummarySection(items: viewModel.items, total: viewModel.formattedTotal)
                        .padding(.top, 16)

                    Divider().background(Color.appDivider).padding(.vertical, 16)

                    // Payment method picker
                    PaymentMethodSection(selected: $viewModel.selectedMethod)

                    Divider().background(Color.appDivider).padding(.vertical, 16)

                    // Cash input (hanya tampil jika method = cash)
                    if viewModel.selectedMethod == .cash {
                        CashInputSection(
                            inputText:   $viewModel.cashInputText,
                            totalPrice:  viewModel.totalPrice,
                            change:      viewModel.change,
                            onDenomTap:  { viewModel.selectDenomination($0) },
                            onClear:     { viewModel.clearCashInput() }
                        )
                        Divider().background(Color.appDivider).padding(.vertical, 16)
                    }

                    // QRIS placeholder
                    if viewModel.selectedMethod == .qris {
                        QRISSection(total: viewModel.formattedTotal)
                        Divider().background(Color.appDivider).padding(.vertical, 16)
                    }

                    // Confirm button
                    ConfirmPaymentButton(
                        isValid:    viewModel.isPaymentValid,
                        method:     viewModel.selectedMethod,
                        onConfirm:  { viewModel.confirmPayment() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 16)
                }
            }
        }
    }
}

// MARK: - Order Summary Section

private struct OrderSummarySection: View {
    let items:  [CartItem]
    let total:  String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ringkasan Pesanan")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.appTextMuted)
                .padding(.horizontal, 16)

            ForEach(items) { item in
                HStack(spacing: 10) {
                    Text(item.product.emoji).font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.product.name)
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        Text("×\(item.quantity)")
                            .font(.system(size: 11)).foregroundStyle(Color.appTextMuted)
                    }
                    Spacer()
                    Text(item.formattedSubtotal)
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }

            Divider().background(Color.appDivider).padding(.horizontal, 16)

            HStack {
                Text("Total").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text(total).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.appGreen).monospacedDigit()
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Payment Method Section

private struct PaymentMethodSection: View {
    @Binding var selected: PaymentMethod

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metode Pembayaran")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.appTextMuted)
                .padding(.horizontal, 16)

            HStack(spacing: 10) {
                ForEach(PaymentMethod.allCases) { method in
                    PaymentMethodCard(
                        method:     method,
                        isSelected: selected == method,
                        onTap:      { selected = method }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct PaymentMethodCard: View {
    let method:     PaymentMethod
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: method.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.appGreen : Color(white: 0.4))
                Text(method.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.appGreen : Color(white: 0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isSelected
                    ? Color.appGreenBg
                    : Color.white.opacity(0.05)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.appGreenDark : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cash Input Section

private struct CashInputSection: View {
    @Binding var inputText: String
    let totalPrice: Int
    let change:     Int
    let onDenomTap: (CashDenomination) -> Void
    let onClear:    () -> Void

    private let denominations = CashDenomination.presets

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jumlah Pembayaran")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.appTextMuted)
                .padding(.horizontal, 16)

            // Input field
            HStack {
                Text("Rp").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.appTextMuted)
                TextField("0", text: $inputText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer()
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20)).foregroundStyle(Color(white: 0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)

            // Denomination shortcuts
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(denominations) { denom in
                    Button(action: { onDenomTap(denom) }) {
                        Text(denom.formatted)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.appGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.appGreenBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            // Kembalian
            HStack {
                Text("Kembalian").font(.system(size: 14)).foregroundStyle(Color.appTextMuted)
                Spacer()
                Text(change.formattedIDR)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(change >= 0 ? Color.appGreen : Color.red)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - QRIS Section

private struct QRISSection: View {
    let total: String

    var body: some View {
        VStack(spacing: 14) {
            Text("Scan QR Code untuk membayar")
                .font(.system(size: 14)).foregroundStyle(Color.appTextMuted)

            // QR placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(width: 180, height: 180)
                Image(systemName: "qrcode")
                    .font(.system(size: 120))
                    .foregroundStyle(Color.black.opacity(0.8))
            }

            Text(total)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.appGreen)
                .monospacedDigit()

            Text("Total yang harus dibayar")
                .font(.system(size: 12)).foregroundStyle(Color.appTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Confirm Payment Button

private struct ConfirmPaymentButton: View {
    let isValid:   Bool
    let method:    PaymentMethod
    let onConfirm: () -> Void

    var label: String {
        switch method {
        case .cash:  return "Konfirmasi Pembayaran"
        case .qris:  return "Pembayaran Selesai"
        case .debit: return "Konfirmasi Pembayaran"
        }
    }

    var body: some View {
        Button(action: onConfirm) {
            HStack(spacing: 8) {
                Image(systemName: method.icon).font(.system(size: 16))
                Text(label).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isValid ? Color.appGreenDark : Color.white.opacity(0.06))
            .foregroundStyle(isValid ? .white : Color.appTextMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!isValid)
        .animation(.easeInOut(duration: 0.2), value: isValid)
    }
}

// MARK: - Success View

struct SuccessView: View {
    let result:    CheckoutResult
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon + animasi
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.appGreenBg)
                        .frame(width: 96, height: 96)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Color.appGreen)
                }

                Text("Pembayaran Berhasil!")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)

                Text(result.receiptNumber)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.appTextMuted)
            }

            Spacer()

            // Receipt card
            VStack(spacing: 0) {
                receiptRow(label: "Metode", value: result.paymentMethod.title)
                Divider().background(Color.appDivider)
                receiptRow(label: "Total", value: result.formattedTotal)

                if result.paymentMethod == .cash {
                    Divider().background(Color.appDivider)
                    receiptRow(label: "Dibayar", value: result.formattedPaid)
                    Divider().background(Color.appDivider)
                    receiptRow(label: "Kembalian", value: result.formattedChange, highlight: true)
                }
            }
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)

            Spacer()

            // Transaksi baru button
            Button(action: onDismiss) {
                Label("Transaksi Baru", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.appGreenDark)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private func receiptRow(label: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Color.appTextMuted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(highlight ? Color.appGreen : .white)
                .monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}
