import SwiftUI
import StoreKit

@MainActor
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var products: [Product] = []
    @State private var selectedProduct: Product? = nil
    @State private var isPurchasing = false
    @State private var errorMessage: String? = nil
    @State private var entitlement: Entitlement = .free

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Hero
                    heroSection

                    // Feature list
                    featuresSection

                    // SKUs
                    productsSection

                    // CTA
                    ctaSection

                    // Footer
                    footerSection
                }
                .padding()
            }
            .navigationTitle("LEO Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Maybe later") { dismiss() }
                }
            }
            .task { await loadProducts() }
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.Color.accent)
            Text("LEO Pro")
                .font(.system(size: 34, weight: .bold))
            Text("The productivity layer that actually understands you.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private let proFeatures: [(String, String)] = [
        ("sparkles", "Unlimited AI planning"),
        ("alarm.fill", "Real alarms & escalating sounds"),
        ("repeat.circle.fill", "Advanced recurring (workdays, holidays)"),
        ("chart.bar.fill", "Habits & forgiving streaks"),
        ("text.badge.checkmark", "Weekly AI review"),
        ("rectangle.stack.fill", "Widgets + lock-screen widgets"),
        ("applewatch", "Apple Watch companion (v1.1)")
    ]

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(proFeatures, id: \.0) { icon, label in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .foregroundStyle(Theme.Color.accent)
                        .frame(width: 28)
                    Text(label)
                        .font(Theme.Typography.body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private var productsSection: some View {
        VStack(spacing: 12) {
            ForEach(products, id: \.id) { product in
                ProductCard(product: product, isSelected: selectedProduct?.id == product.id) {
                    selectedProduct = product
                }
            }
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 12) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Color.danger)
            }

            Button {
                Task { await purchase() }
            } label: {
                HStack {
                    if isPurchasing { ProgressView().tint(.white) }
                    Text(ctaLabel)
                        .font(Theme.Typography.body.bold())
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.Color.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .disabled(selectedProduct == nil || isPurchasing)

            Button("Restore purchases") {
                Task { await restore() }
            }
            .foregroundStyle(Theme.Color.textSecondary)
            .font(.caption)
        }
    }

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("Payment charged to Apple ID account at purchase confirmation. Subscription renews automatically unless cancelled.")
                .font(.caption2)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private func loadProducts() async {
        products = (try? await Product.products(for: LEOProductID.all))?.sorted { $0.price < $1.price } ?? []
        selectedProduct = products.first(where: { $0.id == LEOProductID.yearly }) ?? products.first
        entitlement = await StoreClient.shared.currentEntitlement
    }

    private func purchase() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        errorMessage = nil
        do {
            _ = try await StoreClient.shared.purchase(product)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isPurchasing = false
    }

    private func restore() async {
        do {
            try await StoreClient.shared.restore()
            entitlement = await StoreClient.shared.currentEntitlement
            if entitlement.isPro { dismiss() }
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private var ctaLabel: String {
        guard let product = selectedProduct else { return "Select a plan" }
        if let intro = product.subscription?.introductoryOffer {
            if intro.paymentMode == .freeTrial {
                return "Start 7-day free trial"
            }
        }
        return "Subscribe — \(product.displayPrice)"
    }
}

// MARK: - ProductCard

private struct ProductCard: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(Theme.Typography.body.bold())
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(Theme.Typography.body.bold())
                    .foregroundStyle(isSelected ? .white : Theme.Color.textPrimary)
            }
            .padding()
            .background(isSelected ? Theme.Color.accent : Theme.Color.surface)
            .foregroundStyle(isSelected ? .white : Theme.Color.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? Theme.Color.accent : Theme.Color.divider, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
