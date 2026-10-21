//
// SwiftyStoreKitAsyncTests.swift
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

import XCTest
import StoreKit
@testable import SwiftyStoreKit

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, macCatalyst 13.0, *)
class SwiftyStoreKitAsyncTests: XCTestCase {

    private var requestBuilder: TestInAppProductRequestBuilder!
    private var paymentQueueSpy: PaymentQueueSpy!
    private var paymentQueueController: PaymentQueueController!
    private var receiptURL: URL!
    private let receiptData = Data("receipt".utf8)

    override func setUpWithError() throws {
        requestBuilder = TestInAppProductRequestBuilder()
        paymentQueueSpy = PaymentQueueSpy()
        paymentQueueController = PaymentQueueController(paymentQueue: paymentQueueSpy)
        paymentQueueController.completeTransactions(CompleteTransactions(atomically: true) { _ in })

        receiptURL = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-\(UUID().uuidString)")
        try receiptData.write(to: receiptURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: receiptURL)
    }

    private func makeSUT(receiptURL: URL? = nil) -> SwiftyStoreKit {
        return SwiftyStoreKit(productsInfoController: ProductsInfoController(inAppProductRequestBuilder: requestBuilder),
                              paymentQueueController: paymentQueueController,
                              receiptVerificator: InAppReceiptVerificator(appStoreReceiptURL: receiptURL))
    }

    /// Polls until `condition` is true, so the test can act once the async call under test has registered its work.
    private func waitUntil(_ description: String, timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)")
    }

    // MARK: retrieveProductsInfo

    func testRetrieveProductsInfo_when_requestCompletes_then_returnsResults() async {
        let sut = makeSUT()

        let task = Task { await sut.retrieveProductsInfo(["com.iap.purchase1"]) }
        await waitUntil("product request") { !requestBuilder.requests.isEmpty }
        requestBuilder.fireCallbacks()
        let results = await task.value

        XCTAssertTrue(results.retrievedProducts.isEmpty)
        XCTAssertTrue(results.invalidProductIDs.isEmpty)
        XCTAssertNil(results.error)
    }

    // MARK: purchaseProduct

    func testPurchaseProductId_when_productCanNotBeRetrieved_then_returnsError() async {
        let sut = makeSUT()

        let task = Task {
            await sut.purchaseProduct("com.iap.unknown", quantity: 1, atomically: true, applicationUsername: "", simulatesAskToBuyInSandbox: false)
        }
        await waitUntil("product request") { !requestBuilder.requests.isEmpty }
        requestBuilder.fireCallbacks()
        let result = await task.value

        guard case .error(let error) = result else {
            return XCTFail("expected error, got \(result)")
        }
        XCTAssertEqual(error.code, .unknown)
        XCTAssertEqual(paymentQueueSpy.payments.count, 0)
    }

    func testPurchaseProduct_when_transactionPurchased_then_returnsSuccess() async {
        let sut = makeSUT()
        let product = TestProduct(productIdentifier: "com.iap.purchase1")

        let task = Task {
            await sut.purchase(product: product, quantity: 1, atomically: true, applicationUsername: "", simulatesAskToBuyInSandbox: false, paymentDiscount: nil)
        }
        await waitUntil("payment to be queued") { paymentQueueSpy.payments.count == 1 }
        let transaction = TestPaymentTransaction(payment: SKPayment(product: product), transactionState: .purchased)
        paymentQueueController.paymentQueue(SKPaymentQueue(), updatedTransactions: [transaction])
        let result = await task.value

        guard case .success(let purchase) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(purchase.productId, "com.iap.purchase1")
        XCTAssertEqual(paymentQueueSpy.finishTransactionCalledCount, 1)
    }

    func testPurchaseProduct_when_transactionDeferred_then_returnsDeferred() async {
        let sut = makeSUT()
        let product = TestProduct(productIdentifier: "com.iap.purchase1")

        let task = Task {
            await sut.purchase(product: product, quantity: 1, atomically: true, applicationUsername: "", simulatesAskToBuyInSandbox: false, paymentDiscount: nil)
        }
        await waitUntil("payment to be queued") { paymentQueueSpy.payments.count == 1 }
        let transaction = TestPaymentTransaction(payment: SKPayment(product: product), transactionState: .deferred)
        paymentQueueController.paymentQueue(SKPaymentQueue(), updatedTransactions: [transaction])
        let result = await task.value

        guard case .deferred(let purchase) = result else {
            return XCTFail("expected deferred, got \(result)")
        }
        XCTAssertEqual(purchase.productId, "com.iap.purchase1")
    }

    // MARK: restorePurchases

    func testRestorePurchases_when_restoreFinishes_then_returnsRestoredPurchases() async {
        let sut = makeSUT()
        let product = TestProduct(productIdentifier: "com.iap.purchase1")

        let task = Task { await sut.restorePurchases(atomically: true, applicationUsername: "") }
        await waitUntil("restore to start") { paymentQueueSpy.restoreCompletedTransactionCalledCount == 1 }
        let transaction = TestPaymentTransaction(payment: SKPayment(product: product), transactionState: .restored)
        paymentQueueController.paymentQueue(SKPaymentQueue(), updatedTransactions: [transaction])
        paymentQueueController.paymentQueueRestoreCompletedTransactionsFinished(SKPaymentQueue())
        let results = await task.value

        XCTAssertEqual(results.restoredPurchases.map { $0.productId }, ["com.iap.purchase1"])
        XCTAssertTrue(results.restoreFailedPurchases.isEmpty)
    }

    // MARK: receipts

    func testFetchReceipt_when_receiptExists_then_returnsData() async {
        let sut = makeSUT(receiptURL: receiptURL)

        let result = await sut.fetchReceipt(forceRefresh: false)

        guard case .success(let data) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(data, receiptData)
    }

    func testVerifyReceipt_when_receiptExists_then_callsValidatorAndReturnsSuccess() async {
        let sut = makeSUT(receiptURL: receiptURL)
        let validator = TestReceiptValidator()

        let result = await sut.verifyReceipt(using: validator, forceRefresh: false)

        XCTAssertTrue(validator.validateCalled)
        XCTAssertEqual(result, .success(receipt: [:]))
    }
}

#endif
