//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation

/// In-memory implementation of RateLimitPersistence for testing.
///
/// This implementation stores request timestamps in memory without any persistence.
/// It's designed for testing scenarios where immediate, async operations are needed.
/// Thread safety is guaranteed by actor isolation.
actor InMemoryRateLimitPersistence: RateLimitPersistence {
    private var timestamps: [TimeInterval] = []

    func loadRequests() -> [TimeInterval] {
        timestamps
    }

    func saveRequests(_ timestamps: [TimeInterval]) {
        self.timestamps = timestamps
    }

    func clearRequests() {
        timestamps.removeAll()
    }
}
