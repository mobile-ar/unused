import Synchronization
import Testing
@testable import unused

struct PrintHelperTests {
    @Test func rendersETAAndReplacesTheExistingTerminalLine() {
        let output = Mutex<[String]>([])
        printProgressBar(
            prefix: "Parsing files...", current: 2, total: 4, estimatedRemaining: .seconds(65),
            interactiveEnabled: true, colorEnabled: false,
            write: { text in output.withLock { $0.append(text) } }
        )
        let text = output.withLock { $0.first }
        #expect(text?.hasPrefix("\r\u{1B}[K") == true)
        #expect(text?.contains("50.0% (2/4) ETA: ~1m 5s") == true)
        #expect(text?.hasSuffix("\n") == false)
        #expect(output.withLock { $0.count } == 1)
    }

    @Test func noninteractiveOutputDoesNotEmitProgressOrControlSequences() {
        let output = Mutex<[String]>([])
        printProgressBar(
            prefix: "Hidden", current: 1, total: 2, estimatedRemaining: .seconds(10),
            interactiveEnabled: false, colorEnabled: true,
            write: { text in output.withLock { $0.append(text) } }
        )
        printProgressBar(
            prefix: "Hidden empty", current: Int.max, total: 0,
            interactiveEnabled: false, write: { text in output.withLock { $0.append(text) } }
        )
        #expect(output.withLock { $0.isEmpty })
    }

    @Test func missingTimingSampleShowsCalculatingInsteadOfPlaceholder() {
        let output = Mutex<[String]>([])
        printProgressBar(
            prefix: "External protocols...", current: 1, total: 5,
            interactiveEnabled: true, colorEnabled: false,
            write: { text in output.withLock { $0.append(text) } }
        )
        #expect(output.withLock { $0.first?.contains("ETA: calculating...") } == true)
    }

    @Test func forwardsElapsedTimeForCompletedPhases() {
        let output = Mutex<[String]>([])
        printProgressBar(
            prefix: "Parsing files...", current: 2, total: 2, estimatedRemaining: .zero, elapsed: .milliseconds(42),
            interactiveEnabled: true, colorEnabled: false,
            write: { text in output.withLock { $0.append(text) } }
        )
        #expect(output.withLock { $0.first?.hasSuffix(" Done in 42ms") } == true)
        #expect(output.withLock { $0.first?.contains("ETA:") } == false)
    }

    @Test func terminalClearingIsIndependentOfColorStyling() {
        let plain = Mutex<[String]>([])
        let styled = Mutex<[String]>([])
        printProgressBar(
            prefix: "Phase", current: 1, total: 1, estimatedRemaining: .zero,
            interactiveEnabled: true, colorEnabled: false,
            write: { text in plain.withLock { $0.append(text) } }
        )
        printProgressBar(
            prefix: "Phase", current: 1, total: 1, estimatedRemaining: .zero,
            interactiveEnabled: true, colorEnabled: true,
            write: { text in styled.withLock { $0.append(text) } }
        )
        #expect(plain.withLock { $0.first?.contains("\u{1B}[38;2;") } == false)
        #expect(styled.withLock { $0.first?.contains("\u{1B}[38;2;") } == true)
        #expect(plain.withLock { $0.first?.hasPrefix("\r\u{1B}[K") } == true)
        #expect(styled.withLock { $0.first?.hasPrefix("\r\u{1B}[K") } == true)
        #expect(plain.withLock { $0.first?.contains("100.0% (1/1) ETA: 0ms") } == true)
    }

    @Test func interactiveEmptyCountsDoNotDivideByZero() {
        let output = Mutex<[String]>([])
        printProgressBar(
            prefix: "Empty", current: 0, total: 0, estimatedRemaining: .zero,
            interactiveEnabled: true, colorEnabled: false,
            write: { text in output.withLock { $0.append(text) } }
        )
        #expect(output.withLock { $0.first?.contains("0.0% (0/0) ETA: 0ms") } == true)
    }
}
