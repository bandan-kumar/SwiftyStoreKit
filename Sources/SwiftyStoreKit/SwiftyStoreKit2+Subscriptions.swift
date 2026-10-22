//
// SwiftyStoreKit2+Subscriptions.swift
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

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *)
extension SwiftyStoreKit2 {

    /// The verified state of an auto-renewable subscription.
    public struct SubscriptionState {
        /// The subscription group identifier.
        public let groupId: String
        /// The renewal state reported by the App Store.
        public let state: Product.SubscriptionInfo.RenewalState
        /// The verified transaction for the current subscription period.
        public let transaction: Transaction
        /// The verified renewal information (auto-renew status, expiration reason, grace period, billing retry, ...).
        public let renewalInfo: Product.SubscriptionInfo.RenewalInfo

        /// The product identifier of the subscription this state belongs to.
        public var productId: String {
            return transaction.productID
        }

        /// Whether the user should currently have access: the subscription is active
        /// or the renewal failed but the subscription is in its billing grace period.
        public var isActive: Bool {
            return state == .subscribed || state == .inGracePeriod
        }

        /// Whether the subscription renews automatically.
        public var willAutoRenew: Bool {
            return renewalInfo.willAutoRenew
        }

        /// The date the current period ends.
        public var expirationDate: Date? {
            return transaction.expirationDate
        }
    }

    // MARK: - Subscription state

    /// The states of all subscriptions in a subscription group, as reported by the App Store.
    ///
    /// Statuses whose transaction or renewal information fail verification are omitted.
    /// - Parameter groupId: The subscription group identifier from App Store Connect.
    public static func subscriptionStates(forGroup groupId: String) async throws -> [SubscriptionState] {
        let statuses = try await Product.SubscriptionInfo.status(for: groupId)
        return subscriptionStates(from: statuses, groupId: groupId)
    }

    /// The states of a subscription product's group.
    ///
    /// Statuses whose transaction or renewal information fail verification are omitted.
    /// - Returns: An empty array if the product is not an auto-renewable subscription.
    public static func subscriptionStates(for product: Product) async throws -> [SubscriptionState] {
        guard let subscription = product.subscription else {
            return []
        }
        let statuses = try await subscription.status
        return subscriptionStates(from: statuses, groupId: subscription.subscriptionGroupID)
    }

    /// The single most relevant subscription state of a group, or `nil` if the user never subscribed.
    ///
    /// If the user has several entries in a group, the active one wins, then grace period, billing retry,
    /// expired and revoked. Entries with the same rank are ordered by expiration date.
    /// - Parameter groupId: The subscription group identifier from App Store Connect.
    public static func subscriptionState(forGroup groupId: String) async throws -> SubscriptionState? {
        return bestState(in: try await subscriptionStates(forGroup: groupId))
    }

    /// The single most relevant subscription state of a product's group. See `subscriptionState(forGroup:)`.
    public static func subscriptionState(for product: Product) async throws -> SubscriptionState? {
        return bestState(in: try await subscriptionStates(for: product))
    }

    // MARK: - Introductory offers

    /// Whether the user is eligible for the introductory offer of a subscription product.
    ///
    /// Eligibility is per subscription group: a user who used an introductory offer for any product in the
    /// group is not eligible for the others.
    /// - returns: `false` if the product is not an auto-renewable subscription or has no introductory offer.
    public static func isEligibleForIntroductoryOffer(_ product: Product) async -> Bool {
        guard let subscription = product.subscription, subscription.introductoryOffer != nil else {
            return false
        }
        return await subscription.isEligibleForIntroOffer
    }

    /// Whether the user is eligible for introductory offers in a subscription group.
    public static func isEligibleForIntroductoryOffer(forGroup groupId: String) async -> Bool {
        return await Product.SubscriptionInfo.isEligibleForIntroOffer(for: groupId)
    }

    // MARK: - Helpers

    static func subscriptionStates(from statuses: [Product.SubscriptionInfo.Status], groupId: String) -> [SubscriptionState] {
        return statuses.compactMap { status in
            guard case .verified(let transaction) = status.transaction,
                  case .verified(let renewalInfo) = status.renewalInfo else {
                return nil
            }
            return SubscriptionState(groupId: groupId, state: status.state, transaction: transaction, renewalInfo: renewalInfo)
        }
    }

    static func bestState(in states: [SubscriptionState]) -> SubscriptionState? {
        return states.max { lhs, rhs in
            let lhsRank = rank(of: lhs.state)
            let rhsRank = rank(of: rhs.state)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return (lhs.expirationDate ?? .distantPast) < (rhs.expirationDate ?? .distantPast)
        }
    }

    private static func rank(of state: Product.SubscriptionInfo.RenewalState) -> Int {
        switch state {
        case .subscribed: return 5
        case .inGracePeriod: return 4
        case .inBillingRetryPeriod: return 3
        case .expired: return 2
        case .revoked: return 1
        default: return 0
        }
    }
}

#endif
