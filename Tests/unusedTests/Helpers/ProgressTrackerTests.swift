import Synchronization
import Testing
@testable import unused

struct ProgressTrackerTests {
    @Test func startImmediatelyRendersZeroWithoutInventingCompletedWork() async {
        let updates = Mutex<[ProgressUpdate]>([])
        let tracker = ProgressTracker(
            total: 129, prefix: "Collecting usage...", elapsed: { .seconds(2) },
            render: { update in updates.withLock { $0.append(update) } }, finishLine: {}
        )
        await tracker.start()
        await tracker.start()
        #expect(updates.withLock { $0 } == [
            ProgressUpdate(prefix: "Collecting usage...", current: 0, total: 129, estimatedRemaining: nil, elapsed: .seconds(2))
        ])
        #expect(updates.withLock { ProgressBarFormatter().render($0[0]).hasSuffix("0.0% (0/129) ETA: calculating...") })
        await tracker.finish()
    }

    @Test func firstCompletionRendersEvenImmediatelyAfterStarting() async {
        let elapsed = Mutex<Duration>(.zero)
        let updates = Mutex<[ProgressUpdate]>([])
        let tracker = ProgressTracker(
            total: 3, prefix: "Usage", elapsed: { elapsed.withLock { $0 } },
            render: { update in updates.withLock { $0.append(update) } }, finishLine: {}
        )
        await tracker.start()
        elapsed.withLock { $0 = .milliseconds(10) }
        await tracker.increment()
        await tracker.start()
        #expect(updates.withLock { $0.map(\.current) } == [0, 1])
        #expect(updates.withLock { $0.last?.estimatedRemaining } == .milliseconds(20))
        await tracker.finish()
    }

    @Test func finishingAnInitiallyRenderedPhaseClosesItsLineWithoutClaimingCompletion() async {
        let updates = Mutex<[ProgressUpdate]>([])
        let lines = Mutex<Int>(0)
        let tracker = ProgressTracker(
            total: 3, prefix: "Usage", render: { update in updates.withLock { $0.append(update) } },
            finishLine: { lines.withLock { $0 += 1 } }
        )
        await tracker.start()
        await tracker.finish()
        await tracker.finish()
        await tracker.start()
        await tracker.increment()
        #expect(updates.withLock { $0.map(\.current) } == [0])
        #expect(updates.withLock { $0.first?.estimatedRemaining } == nil)
        #expect(lines.withLock { $0 } == 1)
    }

    @Test func calculatesRemainingTimeFromCompletedItemsAndElapsedTime() async {
        let elapsed = Mutex<Duration>(.seconds(4))
        let updates = Mutex<[ProgressUpdate]>([])
        let tracker = ProgressTracker(
            total: 10, prefix: "Parsing files...", elapsed: { elapsed.withLock { $0 } }, renderInterval: .zero,
            render: { update in updates.withLock { $0.append(update) } }, finishLine: {}
        )
        await tracker.increment()
        elapsed.withLock { $0 = .seconds(6) }
        await tracker.increment()
        #expect(updates.withLock { $0 } == [
            ProgressUpdate(prefix: "Parsing files...", current: 1, total: 10, estimatedRemaining: .seconds(36), elapsed: .seconds(4)),
            ProgressUpdate(prefix: "Parsing files...", current: 2, total: 10, estimatedRemaining: .seconds(24), elapsed: .seconds(6))
        ])
    }

    @Test func zeroElapsedTimeStaysUnknownUntilCompletion() async {
        let updates = Mutex<[ProgressUpdate]>([])
        let tracker = ProgressTracker(
            total: 2, prefix: "Fast phase", elapsed: { .zero }, renderInterval: .zero,
            render: { update in updates.withLock { $0.append(update) } }, finishLine: {}
        )
        await tracker.increment()
        await tracker.increment()
        #expect(updates.withLock { $0.first?.estimatedRemaining } == nil)
        #expect(updates.withLock { $0.last?.estimatedRemaining } == .zero)
    }

    @Test func throttlesRedrawsButAlwaysShowsCompletion() async {
        let elapsed = Mutex<Duration>(.zero)
        let updates = Mutex<[ProgressUpdate]>([])
        let lines = Mutex<Int>(0)
        let tracker = ProgressTracker(
            total: 5, prefix: "Throttled", elapsed: { elapsed.withLock { $0 } },
            render: { update in updates.withLock { $0.append(update) } },
            finishLine: { lines.withLock { $0 += 1 } }
        )
        await tracker.increment()
        elapsed.withLock { $0 = .milliseconds(10) }
        await tracker.increment()
        elapsed.withLock { $0 = .milliseconds(99) }
        await tracker.increment()
        elapsed.withLock { $0 = .milliseconds(100) }
        await tracker.increment()
        elapsed.withLock { $0 = .milliseconds(101) }
        await tracker.increment()
        await tracker.finish()
        #expect(updates.withLock { $0.map(\.current) } == [1, 4, 5])
        #expect(updates.withLock { $0.last?.estimatedRemaining } == .zero)
        #expect(lines.withLock { $0 } == 1)
    }

    @Test func finishFlushesTheLatestPartialCountWithoutClaimingCompletion() async {
        let elapsed = Mutex<Duration>(.zero)
        let updates = Mutex<[ProgressUpdate]>([])
        let lines = Mutex<Int>(0)
        let tracker = ProgressTracker(
            total: 5, prefix: "Partial", elapsed: { elapsed.withLock { $0 } },
            render: { update in updates.withLock { $0.append(update) } },
            finishLine: { lines.withLock { $0 += 1 } }
        )
        await tracker.increment()
        elapsed.withLock { $0 = .milliseconds(10) }
        await tracker.increment()
        elapsed.withLock { $0 = .seconds(2) }
        await tracker.finish()
        await tracker.finish()
        await tracker.increment()
        #expect(updates.withLock { $0.map(\.current) } == [1, 2])
        #expect(updates.withLock { $0.last?.estimatedRemaining } == .seconds(3))
        #expect(lines.withLock { $0 } == 1)
    }

    @Test(arguments: [0, -1])
    func emptyTotalsDoNotRenderOrWriteBlankLines(total: Int) async {
        let updates = Mutex<[ProgressUpdate]>([])
        let lines = Mutex<Int>(0)
        let tracker = ProgressTracker(
            total: total, prefix: "Empty", render: { update in updates.withLock { $0.append(update) } },
            finishLine: { lines.withLock { $0 += 1 } }
        )
        await tracker.start()
        await tracker.increment()
        await tracker.finish()
        await tracker.start()
        await tracker.finish()
        #expect(updates.withLock { $0.isEmpty })
        #expect(lines.withLock { $0 } == 0)
    }

    @Test func finishingBeforeProcessingAnythingDoesNotInventProgress() async {
        let updates = Mutex<[ProgressUpdate]>([])
        let lines = Mutex<Int>(0)
        let tracker = ProgressTracker(
            total: 3, prefix: "Not started", render: { update in updates.withLock { $0.append(update) } },
            finishLine: { lines.withLock { $0 += 1 } }
        )
        await tracker.finish()
        await tracker.increment()
        #expect(updates.withLock { $0.isEmpty })
        #expect(lines.withLock { $0 } == 0)
    }

    @Test func extraIncrementsAndRepeatedFinishAreIgnored() async {
        let updates = Mutex<[ProgressUpdate]>([])
        let lines = Mutex<Int>(0)
        let tracker = ProgressTracker(
            total: 1, prefix: "One", elapsed: { .milliseconds(1) }, renderInterval: .zero,
            render: { update in updates.withLock { $0.append(update) } },
            finishLine: { lines.withLock { $0 += 1 } }
        )
        await tracker.increment()
        await tracker.increment()
        await tracker.finish()
        await tracker.finish()
        await tracker.increment(total: 2)
        #expect(updates.withLock { $0 } == [
            ProgressUpdate(prefix: "One", current: 1, total: 1, estimatedRemaining: .zero, elapsed: .milliseconds(1))
        ])
        #expect(lines.withLock { $0 } == 1)
    }

    @Test func concurrentCompletionsHaveOrderedCountsAndCorrectFinalETA() async {
        let updates = Mutex<[ProgressUpdate]>([])
        let tracker = ProgressTracker(
            total: 1_000, prefix: "Concurrent", elapsed: { .seconds(1) }, renderInterval: .zero,
            render: { update in updates.withLock { $0.append(update) } }, finishLine: {}
        )
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1_000 { group.addTask { await tracker.increment() } }
        }
        await tracker.finish()
        #expect(updates.withLock { $0.map(\.current) } == Array(1...1_000))
        #expect(updates.withLock { $0.last?.estimatedRemaining } == .zero)
    }

    @Test func aFastLargeBatchHasBoundedRedraws() async {
        let updates = Mutex<[ProgressUpdate]>([])
        let tracker = ProgressTracker(
            total: 1_000, prefix: "Fast batch", elapsed: { .milliseconds(1) },
            render: { update in updates.withLock { $0.append(update) } }, finishLine: {}
        )
        for _ in 0..<1_000 { await tracker.increment() }
        await tracker.finish()
        #expect(updates.withLock { $0.map(\.current) } == [1, 1_000])
    }

    @Test func eachPhaseStartsWithIndependentMeasurements() async {
        let updates = Mutex<[ProgressUpdate]>([])
        let first = ProgressTracker(
            total: 2, prefix: "First", elapsed: { .seconds(10) }, renderInterval: .zero,
            render: { update in updates.withLock { $0.append(update) } }, finishLine: {}
        )
        let second = ProgressTracker(
            total: 2, prefix: "Second", elapsed: { .seconds(1) }, renderInterval: .zero,
            render: { update in updates.withLock { $0.append(update) } }, finishLine: {}
        )
        await first.increment()
        await second.increment()
        #expect(updates.withLock { $0.map(\.estimatedRemaining) } == [.seconds(10), .seconds(1)])
    }

    @Test func dynamicTotalsIncludeNewlyDiscoveredWorkBeforeRendering() async {
        let elapsed = Mutex<Duration>(.milliseconds(10))
        let updates = Mutex<[ProgressUpdate]>([])
        let tracker = ProgressTracker(
            total: 1, prefix: "Dynamic", elapsed: { elapsed.withLock { $0 } }, renderInterval: .zero,
            render: { update in updates.withLock { $0.append(update) } }, finishLine: {}
        )
        await tracker.increment(total: 3)
        elapsed.withLock { $0 = .milliseconds(20) }
        await tracker.increment(total: 3)
        elapsed.withLock { $0 = .milliseconds(30) }
        await tracker.increment(total: 3)
        await tracker.finish()

        #expect(updates.withLock { $0.map(\.current) } == [1, 2, 3])
        #expect(updates.withLock { $0.map(\.total) } == [3, 3, 3])
        #expect(updates.withLock { $0.map(\.estimatedRemaining) } == [.milliseconds(20), .milliseconds(10), .zero])
        #expect(updates.withLock { $0.map(\.elapsed) } == [.milliseconds(10), .milliseconds(20), .milliseconds(30)])
    }

    @Test func fastPhaseDisplaysMillisecondsAndItsCompletionDuration() async {
        let output = Mutex<[String]>([])
        let tracker = ProgressTracker(
            total: 2, prefix: "Fast phase", elapsed: { .milliseconds(125) }, renderInterval: .zero,
            render: { update in output.withLock { $0.append(ProgressBarFormatter().render(update)) } }, finishLine: {}
        )
        await tracker.increment()
        await tracker.increment()
        await tracker.finish()

        #expect(output.withLock { $0.first?.hasSuffix(" ETA: ~125ms") } == true)
        #expect(output.withLock { $0.last?.hasSuffix(" Done in 125ms") } == true)
    }

    @Test func partialFinishStillShowsRemainingTimeRatherThanCompletionDuration() async {
        let output = Mutex<[String]>([])
        let tracker = ProgressTracker(
            total: 2, prefix: "Partial", elapsed: { .milliseconds(125) },
            render: { update in output.withLock { $0.append(ProgressBarFormatter().render(update)) } }, finishLine: {}
        )
        await tracker.increment()
        await tracker.finish()

        #expect(output.withLock { $0.last?.hasSuffix(" ETA: ~125ms") } == true)
        #expect(output.withLock { $0.contains { $0.contains("Done in") } } == false)
    }

    @Test func invalidClockSamplesDoNotProduceNegativeEstimates() async {
        let updates = Mutex<[ProgressUpdate]>([])
        let tracker = ProgressTracker(
            total: 2, prefix: "Invalid clock", elapsed: { .seconds(-1) }, renderInterval: .zero,
            render: { update in updates.withLock { $0.append(update) } }, finishLine: {}
        )
        await tracker.increment()
        #expect(updates.withLock { $0.first?.estimatedRemaining } == nil)
    }
}
