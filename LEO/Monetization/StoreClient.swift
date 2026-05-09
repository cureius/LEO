import StoreKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "store")

// MARK: - Entitlement

public enum Entitlement: Sendable, Equatable {
    case free
    case pro(expiresAt: Date?, inTrial: Bool)
    case unknown

    public var isPro: Bool {
        if case .pro = self { return true }
        return false
    }
    public var isInTrial: Bool {
        if case .pro(_, let trial) = self { return trial }
        return false
    }
}

// MARK: - Product IDs

public enum LEOProductID {
    public static let monthly = "leo.pro.monthly"
    public static let yearly  = "leo.pro.yearly"
    public static let all     = [monthly, yearly]
}

// MARK: - StoreClient

actor StoreClient {
    static let shared = StoreClient()

    private(set) var products: [Product] = []
    private var transactionListener: Task<Void, Error>?

    var currentEntitlement: Entitlement = .unknown

    init() {
        transactionListener = startTransactionListener()
        Task { await refreshEntitlement() }
    }

    // MARK: - Fetch products

    func loadProducts() async throws {
        self.products = try await Product.products(for: LEOProductID.all)
            .sorted { $0.price < $1.price }
        logger.info("Loaded \(self.products.count) products")
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            await refreshEntitlement()
            logger.info("Purchased \(product.id)")
            return transaction
        case .userCancelled:
            logger.info("Purchase cancelled")
            return nil
        case .pending:
            logger.info("Purchase pending")
            return nil
        @unknown default:
            return nil
        }
    }

    // MARK: - Restore

    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlement()
        logger.info("Purchases restored")
    }

    // MARK: - Entitlement refresh

    func refreshEntitlement() async {
        var latestExpiry: Date? = nil
        var inTrial = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if LEOProductID.all.contains(transaction.productID) {
                latestExpiry = transaction.expirationDate
                // Check if this is an introductory/trial offer
                if let offerType = transaction.offerType {
                    let offerString = "\(offerType)"
                    if offerString.lowercased().contains("introductory") {
                        inTrial = true
                    }
                }
            }
        }

        if let expiry = latestExpiry, expiry > .now {
            self.currentEntitlement = .pro(expiresAt: expiry, inTrial: inTrial)
        } else {
            self.currentEntitlement = .free
        }
        logger.info("Entitlement refreshed: \(String(describing: self.currentEntitlement))")
    }

    // MARK: - Transaction listener

    nonisolated private func startTransactionListener() -> Task<Void, Error> {
        let client = self
        return Task.detached(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await client.refreshEntitlement()
                }
            }
        }
    }
}
