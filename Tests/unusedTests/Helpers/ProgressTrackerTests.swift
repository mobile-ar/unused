//
//  Created by Fernando Romiti on 14/02/2026.
//

import Testing
import Foundation
@testable import unused

struct ProgressTrackerTests {

    @Test func testIncrementUpdatesCount() async {
        let tracker = ProgressTracker(total: 5, prefix: "Testing...")
        await tracker.increment()
        await tracker.increment()
        await tracker.finish()
    }

    @Test func testFinishCompletesWithoutError() async {
        let tracker = ProgressTracker(total: 3, prefix: "Processing...")
        await tracker.increment()
        await tracker.increment()
        await tracker.increment()
        await tracker.finish()
    }

    @Test func testSingleItemTracking() async {
        let tracker = ProgressTracker(total: 1, prefix: "Single item...")
        await tracker.increment()
        await tracker.finish()
    }

    @Test func testConcurrentIncrements() async {
        let tracker = ProgressTracker(total: 100, prefix: "Concurrent...")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await tracker.increment()
                }
            }
        }

        await tracker.finish()
    }

    @Test func testZeroTotalDoesNotCrash() async {
        let tracker = ProgressTracker(total: 0, prefix: "Empty...")
        await tracker.finish()
    }

    @Test func testLargeNumberOfIncrements() async {
        let count = 1000
        let tracker = ProgressTracker(total: count, prefix: "Large batch...")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<count {
                group.addTask {
                    await tracker.increment()
                }
            }
        }

        await tracker.finish()
    }
}
