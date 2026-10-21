//
// SwiftyStoreKit+Async.swift
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

// MARK: - Callback to async bridge

/// Makes sure a continuation is resumed at most once, so a callback that fires twice can never trap.
private final class ResumeGuard {

    private let lock = NSLock()
    private var resumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, macCatalyst 13.0, *)
private func awaitCallback<T>(_ start: (@escaping (T) -> Void) -> Void) async -> T {
    return await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
        let resumeGuard = ResumeGuard()
        start { value in
            if resumeGuard.claim() {
                continuation.resume(returning: value)
            }
        }
    }
}

// MARK: - Instance implementation (internal, so it can be tested with injected controllers)

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, macCatalyst 13.0, *)
extension SwiftyStoreKit {

    func retrieveProductsInfo(_ productIds: Set<String>) async -> RetrieveResults {
        return await awaitCallback { done in
            _ = self.retrieveProductsInfo(productIds, completion: done)
        }
    }

    func purchaseProduct(_ productId: String, quantity: Int, atomically: Bool, applicationUsername: String, simulatesAskToBuyInSandbox: Bool) async -> PurchaseResult {
        return await awaitCallback { done in
            _ = self.purchaseProduct(productId, quantity: quantity, atomically: atomically, applicationUsername: applicationUsername, simulatesAskToBuyInSandbox: simulatesAskToBuyInSandbox, completion: done)
        }
    }

    func purchase(product: SKProduct, quantity: Int, atomically: Bool, applicationUsername: String, simulatesAskToBuyInSandbox: Bool, paymentDiscount: PaymentDiscount?) async -> PurchaseResult {
        return await awaitCallback { done in
            self.purchase(product: product, quantity: quantity, atomically: atomically, applicationUsername: applicationUsername, simulatesAskToBuyInSandbox: simulatesAskToBuyInSandbox, paymentDiscount: paymentDiscount, completion: done)
        }
    }

    func restorePurchases(atomically: Bool, applicationUsername: String) async -> RestoreResults {
        return await awaitCallback { done in
            self.restorePurchases(atomically: atomically, applicationUsername: applicationUsername, completion: done)
        }
    }

    func verifyReceipt(using validator: ReceiptValidator, forceRefresh: Bool) async -> VerifyReceiptResult {
        return await awaitCallback { done in
            _ = self.receiptVerificator.verifyReceipt(using: validator, forceRefresh: forceRefresh, completion: done)
        }
    }

    func fetchReceipt(forceRefresh: Bool) async -> FetchReceiptResult {
        return await awaitCallback { done in
            _ = self.receiptVerificator.fetchReceipt(forceRefresh: forceRefresh, completion: done)
        }
    }
}

// MARK: - Public async API

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, macCatalyst 13.0, *)
extension SwiftyStoreKit {

    // MARK: Purchases

    /// Retrieve products information
    /// - Parameter productIds: The set of product identifiers to retrieve corresponding products for
    /// - returns: The retrieved products, the invalid product identifiers and an optional error
    /// - Note: The request can not be cancelled. Cancelling the surrounding `Task` does not cancel it.
    public class func retrieveProductsInfo(_ productIds: Set<String>) async -> RetrieveResults {
        return await sharedInstance.retrieveProductsInfo(productIds)
    }

    /// Purchase a product
    ///  - Parameter productId: productId as specified in App Store Connect
    ///  - Parameter quantity: quantity of the product to be purchased
    ///  - Parameter atomically: whether the product is purchased atomically (e.g. `finishTransaction` is called immediately)
    ///  - Parameter applicationUsername: an opaque identifier for the user’s account on your system
    ///  - Parameter simulatesAskToBuyInSandbox: whether to simulate the "Ask to Buy" flow in the sandbox
    ///  - returns: The result of the purchase. This also covers errors: failures are reported as `.error`, not thrown.
    public class func purchaseProduct(_ productId: String, quantity: Int = 1, atomically: Bool = true, applicationUsername: String = "", simulatesAskToBuyInSandbox: Bool = false) async -> PurchaseResult {
        return await sharedInstance.purchaseProduct(productId, quantity: quantity, atomically: atomically, applicationUsername: applicationUsername, simulatesAskToBuyInSandbox: simulatesAskToBuyInSandbox)
    }

    /// Purchase a product
    ///  - Parameter product: product to be purchased
    ///  - Parameter quantity: quantity of the product to be purchased
    ///  - Parameter atomically: whether the product is purchased atomically (e.g. `finishTransaction` is called immediately)
    ///  - Parameter applicationUsername: an opaque identifier for the user’s account on your system
    ///  - Parameter simulatesAskToBuyInSandbox: whether to simulate the "Ask to Buy" flow in the sandbox
    ///  - Parameter paymentDiscount: optional discount to be applied. Must be of `SKProductPayment` type
    ///  - returns: The result of the purchase. This also covers errors: failures are reported as `.error`, not thrown.
    public class func purchaseProduct(_ product: SKProduct, quantity: Int = 1, atomically: Bool = true, applicationUsername: String = "", simulatesAskToBuyInSandbox: Bool = false, paymentDiscount: PaymentDiscount? = nil) async -> PurchaseResult {
        return await sharedInstance.purchase(product: product, quantity: quantity, atomically: atomically, applicationUsername: applicationUsername, simulatesAskToBuyInSandbox: simulatesAskToBuyInSandbox, paymentDiscount: paymentDiscount)
    }

    /// Restore purchases
    ///  - Parameter atomically: whether the product is purchased atomically (e.g. `finishTransaction` is called immediately)
    ///  - Parameter applicationUsername: an opaque identifier for the user’s account on your system
    ///  - returns: The restored purchases and the purchases that failed to restore
    public class func restorePurchases(atomically: Bool = true, applicationUsername: String = "") async -> RestoreResults {
        return await sharedInstance.restorePurchases(atomically: atomically, applicationUsername: applicationUsername)
    }

    // MARK: Receipt verification

    /// Verify application receipt
    /// - Parameter validator: receipt validator to use
    /// - Parameter forceRefresh: If `true`, refreshes the receipt even if one already exists.
    /// - returns: The result of the verification. Failures are reported as `.error`, not thrown.
    /// - Note: The request can not be cancelled. Cancelling the surrounding `Task` does not cancel it.
    public class func verifyReceipt(using validator: ReceiptValidator, forceRefresh: Bool = false) async -> VerifyReceiptResult {
        return await sharedInstance.verifyReceipt(using: validator, forceRefresh: forceRefresh)
    }

    /// Fetch application receipt
    /// - Parameter forceRefresh: If true, refreshes the receipt even if one already exists.
    /// - returns: The receipt data, or an error. Failures are reported as `.error`, not thrown.
    /// - Note: The request can not be cancelled. Cancelling the surrounding `Task` does not cancel it.
    public class func fetchReceipt(forceRefresh: Bool) async -> FetchReceiptResult {
        return await sharedInstance.fetchReceipt(forceRefresh: forceRefresh)
    }
}

#endif
