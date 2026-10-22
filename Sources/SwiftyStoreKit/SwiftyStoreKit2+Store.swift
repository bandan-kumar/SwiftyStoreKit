//
// SwiftyStoreKit2+Store.swift
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
#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - App Store interactions (platform specific)

#if os(iOS) || targetEnvironment(macCatalyst)

@available(iOS 15.0, macCatalyst 15.0, *)
extension SwiftyStoreKit2 {

    /// Present the App Store's refund request sheet for a transaction.
    /// - Parameter transactionId: The identifier of the transaction (`Transaction.id`).
    /// - Parameter scene: The window scene to present the sheet in.
    /// - returns: Whether the user submitted the request or cancelled.
    @MainActor
    public static func beginRefundRequest(for transactionId: UInt64, in scene: UIWindowScene) async throws -> Transaction.RefundRequestStatus {
        return try await Transaction.beginRefundRequest(for: transactionId, in: scene)
    }

    /// Show the App Store's subscription management screen.
    /// - Parameter scene: The window scene to present the screen in.
    @MainActor
    public static func showManageSubscriptions(in scene: UIWindowScene) async throws {
        try await AppStore.showManageSubscriptions(in: scene)
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
extension SwiftyStoreKit2 {

    /// Present the system sheet that lets the user redeem an offer code.
    ///
    /// Redeemed offers arrive through `transactionUpdates()`.
    /// - Parameter scene: The window scene to present the sheet in.
    @MainActor
    public static func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
    }
}

#elseif os(macOS)

@available(macOS 12.0, *)
extension SwiftyStoreKit2 {

    /// Present the App Store's refund request sheet for a transaction.
    /// - Parameter transactionId: The identifier of the transaction (`Transaction.id`).
    /// - Parameter viewController: The view controller to present the sheet from.
    /// - returns: Whether the user submitted the request or cancelled.
    @MainActor
    public static func beginRefundRequest(for transactionId: UInt64, in viewController: NSViewController) async throws -> Transaction.RefundRequestStatus {
        return try await Transaction.beginRefundRequest(for: transactionId, in: viewController)
    }
}

#endif

// MARK: - App transaction

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, macCatalyst 16.0, *)
extension SwiftyStoreKit2 {

    /// The signed record of the user's original download or purchase of the app.
    ///
    /// It contains the original app version and purchase date, which is useful to grandfather
    /// existing paying customers when an app moves to a different business model.
    /// - Throws: `StoreError.failedAppTransactionVerification` if the record can not be verified.
    public static func appTransaction() async throws -> AppTransaction {
        switch try await AppTransaction.shared {
        case .verified(let appTransaction):
            return appTransaction
        case .unverified(_, let error):
            throw StoreError.failedAppTransactionVerification(error)
        }
    }
}

#endif
