import Testing
@testable import unused

struct ProgressBarFormatterTests {

    @Test func testExactPlainRendering() {
        let update = ProgressUpdate(prefix: "PREFIX", current: 1, total: 4, estimatedRemaining: .seconds(30))
        let bar = String(repeating: "█", count: 12) + String(repeating: "░", count: 38)

        #expect(ProgressBarFormatter().render(update) == " PREFIX [\(bar)] 25.0% (1/4) ETA: ~30s")
    }

    @Test(arguments: [
        (0, 4, 0, "0.0", 0, 4),
        (1, 3, 16, "33.3", 1, 3),
        (2, 3, 33, "66.7", 2, 3),
        (4, 4, 50, "100.0", 4, 4),
        (-1, 4, 0, "0.0", 0, 4),
        (Int.min, 4, 0, "0.0", 0, 4),
        (5, 4, 50, "100.0", 4, 4),
        (Int.max, 4, 50, "100.0", 4, 4),
        (0, 0, 0, "0.0", 0, 0),
        (1, 0, 0, "0.0", 0, 0),
        (Int.min, 0, 0, "0.0", 0, 0),
        (1, -4, 0, "0.0", 0, 0),
        (Int.max, Int.min, 0, "0.0", 0, 0),
        (Int.max, Int.max, 50, "100.0", Int.max, Int.max),
        (Int.max / 2, Int.max, 25, "50.0", Int.max / 2, Int.max)
    ])
    func testClampsCountsAndFormatsPercentage(
        current: Int, total: Int, filled: Int, percentage: String, displayedCurrent: Int, displayedTotal: Int
    ) {
        let update = ProgressUpdate(prefix: "Scan", current: current, total: total, estimatedRemaining: nil)
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: 50 - filled)

        #expect(ProgressBarFormatter().render(update) == " Scan [\(bar)] \(percentage)% (\(displayedCurrent)/\(displayedTotal)) ETA: calculating...")
    }

    @Test(arguments: [
        (nil, "calculating..."),
        (Duration.zero, "0ms"),
        (.seconds(-1), "calculating..."),
        (.milliseconds(-1), "calculating..."),
        (Duration(secondsComponent: 0, attosecondsComponent: -1), "calculating..."),
        (.seconds(Int64.min), "calculating..."),
        (Duration(secondsComponent: 0, attosecondsComponent: 1), "<1ms"),
        (.microseconds(999), "<1ms"),
        (.milliseconds(1), "~1ms"),
        (.microseconds(1_001), "~2ms"),
        (.milliseconds(125), "~125ms"),
        (.milliseconds(999), "~999ms"),
        (.microseconds(999_001), "~1000ms"),
        (.seconds(1), "~1s"),
        (.milliseconds(1_001), "~2s"),
        (.seconds(30), "~30s"),
        (.seconds(59), "~59s"),
        (.milliseconds(59_001), "~1m 0s"),
        (.seconds(60), "~1m 0s"),
        (.seconds(80), "~1m 20s"),
        (.milliseconds(80_001), "~1m 21s"),
        (.seconds(3_599), "~59m 59s"),
        (.milliseconds(3_599_001), "~1h 0m"),
        (.seconds(3_600), "~1h 0m"),
        (.seconds(4_800), "~1h 20m"),
        (.seconds(4_859), "~1h 20m"),
        (.milliseconds(4_859_001), "~1h 21m"),
        (.milliseconds(7_199_001), "~2h 0m"),
        (.seconds(86_400), "~24h 0m"),
        (.seconds(Int64.max), "~2562047788015215h 30m"),
        (Duration(secondsComponent: Int64.max, attosecondsComponent: 1), "~2562047788015215h 30m"),
        (Duration(secondsComponent: Int64.max, attosecondsComponent: 999_999_999_999_999_999), "~2562047788015215h 30m"),
        (.seconds(Int64.max) + .seconds(1), "calculating..."),
        (.seconds(Int64.max) * 2, "calculating..."),
        (.seconds(Double(Int64.max).nextUp), "calculating...")
    ] as [(Duration?, String)])
    func testFormatsRemainingTime(duration: Duration?, expected: String) {
        let update = ProgressUpdate(prefix: "Scan", current: 1, total: 4, estimatedRemaining: duration)

        #expect(ProgressBarFormatter().render(update).hasSuffix(" ETA: \(expected)"))
    }

    @Test func testEstimateIsIndependentOfCounts() {
        let update = ProgressUpdate(prefix: "Empty", current: 0, total: 0, estimatedRemaining: .zero)
        let bar = String(repeating: "░", count: 50)

        #expect(ProgressBarFormatter().render(update) == " Empty [\(bar)] 0.0% (0/0) ETA: 0ms")
    }

    @Test(arguments: [
        (Duration.zero, "0ms"),
        (.microseconds(500), "<1ms"),
        (.milliseconds(42), "42ms"),
        (.milliseconds(999), "999ms"),
        (.seconds(1), "1s"),
        (.seconds(65), "1m 5s"),
        (.seconds(3_600), "1h 0m")
    ])
    func testCompletedPhaseShowsElapsedTimeInsteadOfZeroETA(elapsed: Duration, expected: String) {
        let update = ProgressUpdate(prefix: "Scan", current: 4, total: 4, estimatedRemaining: .zero, elapsed: elapsed)
        let text = ProgressBarFormatter().render(update)

        #expect(text.hasSuffix(" Done in \(expected)"))
        #expect(!text.contains("ETA:"))
    }

    @Test func testIncompletePhaseStillShowsETAWhenElapsedIsAvailable() {
        let update = ProgressUpdate(
            prefix: "Scan", current: 1, total: 4, estimatedRemaining: .milliseconds(375), elapsed: .milliseconds(125)
        )

        #expect(ProgressBarFormatter().render(update).hasSuffix(" ETA: ~375ms"))
    }

    @Test func testEmptyPhaseDoesNotClaimCompletionWhenElapsedIsAvailable() {
        let update = ProgressUpdate(prefix: "Empty", current: 0, total: 0, estimatedRemaining: nil, elapsed: .zero)

        #expect(ProgressBarFormatter().render(update).hasSuffix(" ETA: calculating..."))
    }

    @Test(arguments: [Duration.seconds(-1), .seconds(Int64.max) + .seconds(1)])
    func testInvalidElapsedTimeDoesNotProduceACompletionDuration(elapsed: Duration) {
        let update = ProgressUpdate(prefix: "Scan", current: 4, total: 4, estimatedRemaining: .zero, elapsed: elapsed)

        #expect(ProgressBarFormatter().render(update).hasSuffix(" ETA: 0ms"))
    }

    @Test func testColorsUseLocalTruecolorTheme() {
        let update = ProgressUpdate(prefix: "PREFIX", current: 1, total: 4, estimatedRemaining: .seconds(30))
        let filled = String(repeating: "█", count: 12)
        let empty = String(repeating: "░", count: 38)
        let expected = " \u{1B}[1;38;2;116;199;236mPREFIX\u{1B}[0m"
            + " [\u{1B}[38;2;203;166;247m\(filled)\u{1B}[0m\u{1B}[38;2;180;190;254m\(empty)\u{1B}[0m]"
            + " 25.0% (1/4) \u{1B}[38;2;180;190;254mETA: ~30s\u{1B}[0m"

        #expect(ProgressBarFormatter(colorEnabled: true).render(update) == expected)
    }

    @Test func testPerInstanceColorsDoNotMutateGlobalFlags() {
        let colorEnabled = OutputConfig.colorEnabled
        let interactiveEnabled = OutputConfig.interactiveEnabled
        let update = ProgressUpdate(prefix: "Scan", current: 2, total: 4, estimatedRemaining: nil)
        var formatter = ProgressBarFormatter()
        let plain = formatter.render(update)
        formatter.colorEnabled = true
        let colored = formatter.render(update)
        formatter.colorEnabled = false

        #expect(!plain.contains("\u{1B}"))
        #expect(colored.contains("\u{1B}[38;2;203;166;247m"))
        #expect(colored.contains("\u{1B}[38;2;180;190;254mETA: calculating...\u{1B}[0m"))
        #expect(formatter.render(update) == plain)
        #expect(ProgressBarFormatter(colorEnabled: true).render(update) == colored)
        #expect(OutputConfig.colorEnabled == colorEnabled)
        #expect(OutputConfig.interactiveEnabled == interactiveEnabled)
    }

    @Test(arguments: [false, true])
    func testDoesNotEmitTerminalControls(colorEnabled: Bool) {
        let update = ProgressUpdate(prefix: "Scan", current: 0, total: 0, estimatedRemaining: nil)
        let output = ProgressBarFormatter(colorEnabled: colorEnabled).render(update)

        #expect(!output.contains("\r"))
        #expect(!output.contains("\n"))
        #expect(!output.contains("\u{1B}[K"))
    }
}
