import Testing
@testable import unused

struct ProgressEstimateTests {

    @Test(arguments: [
        (2, 10, Duration.seconds(4), Duration.seconds(16)),
        (4, 10, .seconds(4), .seconds(6)),
        (3, 11, .milliseconds(1_500), .seconds(4)),
        (2, 5, .milliseconds(500), .milliseconds(750)),
        (1, 2, Duration(secondsComponent: 0, attosecondsComponent: 1),
         Duration(secondsComponent: 0, attosecondsComponent: 1))
    ])
    func testUsesAveragePhaseThroughput(completed: Int, total: Int, elapsed: Duration, expected: Duration) {
        #expect(ProgressEstimate.remainingTime(completed: completed, total: total, elapsed: elapsed) == expected)
    }

    @Test(arguments: [
        (0, 10, Duration.seconds(4)),
        (0, 10, .zero),
        (2, 10, .zero),
        (0, Int.max, .seconds(Int64.max))
    ])
    func testUnknownWithoutPositiveSamples(completed: Int, total: Int, elapsed: Duration) {
        #expect(ProgressEstimate.remainingTime(completed: completed, total: total, elapsed: elapsed) == nil)
    }

    @Test(arguments: [
        (10, 10, Duration.seconds(4)),
        (10, 10, .zero),
        (11, 10, .seconds(4)),
        (Int.max, 1, .zero),
        (Int.max, Int.max, .seconds(Int64.max))
    ])
    func testCompletionClampsToZero(completed: Int, total: Int, elapsed: Duration) {
        #expect(ProgressEstimate.remainingTime(completed: completed, total: total, elapsed: elapsed) == .zero)
    }

    @Test(arguments: [Int.min, -1, 0, 1, Int.max])
    func testZeroTotalMeansNoWork(completed: Int) {
        #expect(ProgressEstimate.remainingTime(completed: completed, total: 0, elapsed: .zero) == .zero)
        #expect(ProgressEstimate.remainingTime(completed: completed, total: 0, elapsed: .seconds(-1)) == .zero)
    }

    @Test(arguments: [
        (-1, 10, Duration.seconds(4)),
        (Int.min, Int.max, .seconds(4)),
        (1, -1, .seconds(4)),
        (0, Int.min, .zero),
        (Int.max, -1, .seconds(4)),
        (2, 10, .seconds(-1)),
        (2, 10, .milliseconds(-1)),
        (2, 10, Duration(secondsComponent: 0, attosecondsComponent: -1)),
        (2, 10, .seconds(Int64.min)),
        (10, 10, .seconds(-1))
    ])
    func testRejectsNegativeInputs(completed: Int, total: Int, elapsed: Duration) {
        #expect(ProgressEstimate.remainingTime(completed: completed, total: total, elapsed: elapsed) == nil)
    }

    @Test func testLargeCountsDoNotMultiplyIntegers() throws {
        let estimate = try #require(ProgressEstimate.remainingTime(completed: 2, total: Int.max, elapsed: .seconds(1)))

        #expect(estimate > .zero)
        #expect(estimate.components.seconds > Int64.max / 4)
    }

    @Test func testLargeElapsedCanProduceSupportedEstimate() {
        let estimate = ProgressEstimate.remainingTime(
            completed: Int.max - 1, total: Int.max, elapsed: .seconds(Int64.max)
        )

        #expect(estimate == .seconds(1))
    }

    @Test(arguments: [
        (1, 2, Duration.seconds(Int64.max)),
        (1, Int.max, .seconds(Int64.max)),
        (1, Int.max, .seconds(2)),
        (1, 2, .seconds(Double(Int64.max))),
        (1, 2, .seconds(Double(Int64.max).nextUp)),
                (1, 2, .seconds(Int64.max) + .seconds(1)),
                (1, 2, .seconds(Int64.max) * 2)
    ])
    func testUnsupportedEstimatesReturnNil(completed: Int, total: Int, elapsed: Duration) {
        #expect(ProgressEstimate.remainingTime(completed: completed, total: total, elapsed: elapsed) == nil)
    }

    @Test func testEstimateJustBelowOverflowBoundaryIsSupported() throws {
        let seconds = Double(Int64.max).nextDown
        let estimate = try #require(ProgressEstimate.remainingTime(completed: 1, total: 2, elapsed: .seconds(seconds)))

        #expect(estimate == .seconds(seconds))
    }

    @Test func testTinyEstimateRemainsNonnegative() throws {
        let elapsed = Duration(secondsComponent: 0, attosecondsComponent: 1)
        let estimate = try #require(ProgressEstimate.remainingTime(completed: Int.max - 1, total: Int.max, elapsed: elapsed))

        #expect(estimate >= .zero)
    }
}
