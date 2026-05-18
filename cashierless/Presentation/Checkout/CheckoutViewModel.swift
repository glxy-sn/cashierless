import SwiftUI
import Combine

// MARK: - CheckoutViewModel

@MainActor
final class CheckoutViewModel: ObservableObject {

    // MARK: - State
    @Published var selectedMethod: PaymentMethod = .cash
    @Published var cashInputText:  String        = ""
    @Published var showSuccess:    Bool          = false
    @Published var checkoutResult: CheckoutResult? = nil

    // MARK: - Computed
    var totalPrice: Int { cartService.totalPrice }
    var items:      [CartItem] { cartService.items }

    var cashInput: Int {
        Int(cashInputText.filter { $0.isNumber }) ?? 0
    }

    var change: Int {
        max(0, cashInput - totalPrice)
    }

    var isPaymentValid: Bool {
        switch selectedMethod {
        case .cash:         return cashInput >= totalPrice
        case .qris, .debit: return true
        }
    }

    var formattedTotal:  String { totalPrice.formattedIDR }
    var formattedChange: String { change.formattedIDR }

    // MARK: - Dependencies
    private let cartService: CartServiceImpl
    var onDismiss: (() -> Void)?

    init(cartService: CartServiceImpl) {
        self.cartService = cartService
    }

    // MARK: - Intents

    func selectDenomination(_ denomination: CashDenomination) {
        let current = cashInput
        cashInputText = String(current + denomination.value)
    }

    func clearCashInput() {
        cashInputText = ""
    }

    func confirmPayment() {
        guard isPaymentValid else { return }

        let result = CheckoutResult(
            items:         cartService.items,
            totalPrice:    cartService.totalPrice,
            paymentMethod: selectedMethod,
            amountPaid:    selectedMethod == .cash ? cashInput : totalPrice,
            change:        selectedMethod == .cash ? change : 0
        )

        checkoutResult = result

        withAnimation(.spring(response: 0.4)) {
            showSuccess = true
        }

        // Clear cart setelah animasi selesai
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            cartService.clearCart()
        }
    }

    func dismissSuccess() {
        showSuccess = false
        checkoutResult = nil
        onDismiss?()
    }
}
