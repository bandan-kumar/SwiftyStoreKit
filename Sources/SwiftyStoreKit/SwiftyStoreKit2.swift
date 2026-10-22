//
// SwiftyStoreKit2.swift
// SwiftyStoreKit
//
// Copyright (c) 2015 Andrea Bizzotto (bizz84@gmail.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#if compiler(>=5.5) && canImport(_Concurrency)

import Foundation
import StoreKit

/// Namespace for the StoreKit 2 based API.
///
/// `SwiftyStoreKit2` is a purely additive API that lives next to the original
/// `SwiftyStoreKit` (StoreKit 1) API. Nothing in `SwiftyStoreKit` changes when
/// you start using it, and the two can be adopted one call at a time.
///
/// It uses StoreKit 2's own types (`Product`, `Transaction`, ...) and reports
/// failures by throwing `SwiftyStoreKit2.StoreError`.
///
/// - Important: Do not run the StoreKit 1 transaction observer
///   (`SwiftyStoreKit.completeTransactions`) and `transactionUpdates()` at the
///   same time for the same purchases, or both will try to deliver and finish them.
///   Pick one of them at app launch.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
public enum SwiftyStoreKit2 {

    // MARK: - Types

    /// Errors thrown by `SwiftyStoreKit2`.
    public enum StoreError: Swift.Error {
        /// No product with this identifier exists (or it is not available in the current storefront).
        case productNotFound(productId: String)
        /// StoreKit could not verify the signed transaction. The transaction is **not** finished.
        case failedVerification(VerificationResult<Transaction>.VerificationError)
        /// StoreKit could not verify the signed renewal information.
        case failedRenewalVerification(VerificationResult<Product.SubscriptionInfo.RenewalInfo>.VerificationError)
        /// StoreKit could not verify the signed app transaction (the associated value is the verification error).
        case failedAppTransactionVerification(Swift.Error)
    }

    /// The result of a purchase.
    public enum PurchaseOutcome {
        /// The purchase succeeded and the transaction is verified.
        case success(Transaction)
        /// The purchase is pending approval (for example "Ask to Buy").
        /// The final result arrives through `transactionUpdates()`.
        case pending
        /// The user cancelled the purchase.
        case userCancelled
    }

    /// A transaction coming from `transactionUpdates()` or `unfinishedTransactions()`.
    public enum TransactionUpdate {
        case verified(Transaction)
        case unverified(Transaction, VerificationResult<Transaction>.VerificationError)

        /// The transaction, whether it was verified or not.
        public var transaction: Transaction {
            switch self {
            case .verified(let transaction), .unverified(let transaction, _):
                return transaction
            }
        }
    }

    /// The result of `products(for:)`.
    public struct ProductsResult {
        /// The products StoreKit returned.
        public let products: [Product]
        /// The requested identifiers StoreKit did not return a product for.
        public let invalidProductIds: Set<String>
    }

    // MARK: - Products

    /// Retrieve products.
    ///
    /// Unlike `Product.products(for:)`, this also reports the identifiers that could not be found.
    /// - Parameter productIds: The product identifiers to retrieve.
    public static func products(for productIds: Set<String>) async throws -> ProductsResult {
        let products = try await Product.products(for: productIds)
        let found = Set(products.map { $0.id })
        return ProductsResult(products: products, invalidProductIds: productIds.subtracting(found))
    }

    /// Retrieve a single product.
    /// - Throws: `StoreError.productNotFound` if there is no such product.
    public static func product(for productId: String) async throws -> Product {
        guard let product = try await Product.products(for: [productId]).first else {
            throw StoreError.productNotFound(productId: productId)
        }
        return product
    }

    // MARK: - Purchases

    /// Purchase a product.
    ///
    /// - Parameter product: The product to purchase.
    /// - Parameter quantity: The quantity (consumables only).
    /// - Parameter appAccountToken: An identifier that associates the purchase with a user account in your system.
    /// - Parameter options: Additional StoreKit purchase options, for example a promotional offer
    ///   (`Product.PurchaseOption.promotionalOffer(...)`).
    /// - Parameter finishAutomatically: Whether to finish the transaction as soon as it is verified.
    ///   Pass `false` if you deliver content from a server first, then call `finish(_:)` yourself.
    /// - Throws: `StoreError.failedVerification` if the transaction can not be verified (it is not finished),
    ///   or the error StoreKit reports if the purchase fails.
    @discardableResult
    public static func purchase(_ product: Product,
                                quantity: Int = 1,
                                appAccountToken: UUID? = nil,
                                options: Set<Product.PurchaseOption> = [],
                                finishAutomatically: Bool = true) async throws -> PurchaseOutcome {

        var purchaseOptions = options
        if quantity != 1 {
            purchaseOptions.insert(.quantity(quantity))
        }
        if let appAccountToken = appAccountToken {
            purchaseOptions.insert(.appAccountToken(appAccountToken))
        }

        let result = try await product.purchase(options: purchaseOptions)
        return try await outcome(from: result, finishAutomatically: finishAutomatically)
    }

    static func outcome(from result: Product.PurchaseResult, finishAutomatically: Bool) async throws -> PurchaseOutcome {
        switch result {
        case .success(let verification):
            let transaction = try verified(verification)
            if finishAutomatically {
                await transaction.finish()
            }
            return .success(transaction)
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .pending
        }
    }

    /// Purchase a product given its identifier. See `purchase(_:quantity:appAccountToken:options:finishAutomatically:)`.
    /// - Throws: `StoreError.productNotFound` if there is no such product.
    @discardableResult
    public static func purchase(productId: String,
                                quantity: Int = 1,
                                appAccountToken: UUID? = nil,
                                options: Set<Product.PurchaseOption> = [],
                                finishAutomatically: Bool = true) async throws -> PurchaseOutcome {

        let product = try await self.product(for: productId)
        return try await purchase(product, quantity: quantity, appAccountToken: appAccountToken, options: options, finishAutomatically: finishAutomatically)
    }

    /// Finish a transaction.
    ///
    /// Call this once the content has been delivered, for transactions you did not finish automatically.
    public static func finish(_ transaction: Transaction) async {
        await transaction.finish()
    }

    // MARK: - Entitlements

    /// The user's current entitlements: verified, non-expired, non-revoked transactions for
    /// non-consumables, auto-renewable subscriptions and non-renewing subscriptions.
    ///
    /// Transactions that fail verification are not included.
    public static func currentEntitlements() async -> [Transaction] {
        var transactions: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                transactions.append(transaction)
            }
        }
        return transactions
    }

    /// Whether the user is currently entitled to a product.
    public static func isEntitled(to productId: String) async -> Bool {
        return await currentEntitlements().contains { $0.productID == productId }
    }

    /// The latest verified transaction for a product, including expired and revoked ones. `nil` if never purchased.
    public static func latestTransaction(for productId: String) async -> Transaction? {
        guard let result = await Transaction.latest(for: productId), case .verified(let transaction) = result else {
            return nil
        }
        return transaction
    }

    // MARK: - Transaction updates

    /// A stream of transactions that happen outside of a `purchase` call: renewals, Ask to Buy approvals,
    /// purchases made on other devices, refunds and revocations, and purchases started in the App Store.
    ///
    /// Start iterating it **at app launch** and keep it alive for the lifetime of the app, otherwise
    /// you can miss transactions.
    ///
    /// ```swift
    /// Task {
    ///     for await update in SwiftyStoreKit2.transactionUpdates() {
    ///         if case .verified(let transaction) = update { /* unlock content */ }
    ///     }
    /// }
    /// ```
    /// - Parameter finishAutomatically: Whether to finish verified transactions as they arrive.
    public static func transactionUpdates(finishAutomatically: Bool = true) -> AsyncStream<TransactionUpdate> {
        return AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    let update = transactionUpdate(from: result)
                    if finishAutomatically, case .verified(let transaction) = update {
                        await transaction.finish()
                    }
                    continuation.yield(update)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Transactions that were not finished yet (purchases that were never delivered or finished).
    public static func unfinishedTransactions() async -> [TransactionUpdate] {
        var updates: [TransactionUpdate] = []
        for await result in Transaction.unfinished {
            updates.append(transactionUpdate(from: result))
        }
        return updates
    }

    // MARK: - Restore

    /// Restore purchases by syncing with the App Store.
    ///
    /// With StoreKit 2 purchases are restored automatically on every device. Only call this from a
    /// user action (for example a "Restore Purchases" button), because it can ask the user to sign in.
    /// - returns: The user's current entitlements after the sync.
    /// - Throws: The error StoreKit reports if the sync fails or the user cancels the sign in.
    public static func restorePurchases() async throws -> [Transaction] {
        try await AppStore.sync()
        return await currentEntitlements()
    }

    // MARK: - Verification helpers

    /// Unwrap a verification result.
    /// - Throws: `StoreError.failedVerification` if the result is unverified.
    public static func verified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw StoreError.failedVerification(error)
        }
    }

    static func transactionUpdate(from result: VerificationResult<Transaction>) -> TransactionUpdate {
        switch result {
        case .verified(let transaction):
            return .verified(transaction)
        case .unverified(let transaction, let error):
            return .unverified(transaction, error)
        }
    }
}

#endif
