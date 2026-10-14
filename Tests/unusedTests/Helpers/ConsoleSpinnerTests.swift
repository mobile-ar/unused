//
//  Created by Fernando Romiti on 25/01/2026.
//

import Testing
import Synchronization
@testable import unused

struct ConsoleSpinnerTests {

    @Test func initialFrameIsWrittenBeforeStartReturns() async {
        let output = Mutex<[String]>([])
        let spinner = ConsoleSpinner(
            interval: .seconds(3_600), interactiveEnabled: { true },
            write: { text in output.withLock { $0.append(text) } }
        )
        await spinner.start(message: "Preparing usage analysis...")
        #expect(output.withLock { $0 } == ["\r\u{1B}[K\("⠋".teal) Preparing usage analysis..."])
        await spinner.stop(success: true)
        #expect(output.withLock { $0.last?.contains("Preparing usage analysis...") } == true)
        #expect(output.withLock { $0.last?.hasSuffix("\n") } == true)
        #expect(output.withLock { $0.contains { $0.contains("Done in") } } == false)
    }

    @Test func elapsedTimingStartsAtStartAndResetsForEveryCycle() async {
        let origin = ContinuousClock().now
        let instant = Mutex<ContinuousClock.Instant>(origin)
        let output = Mutex<[String]>([])
        let spinner = ConsoleSpinner(
            showsElapsed: true, interval: .seconds(3_600), now: { instant.withLock { $0 } },
            interactiveEnabled: { true }, write: { text in output.withLock { $0.append(text) } }
        )
        instant.withLock { $0 = origin.advanced(by: .seconds(10)) }
        await spinner.start(message: "First preparation")
        instant.withLock { $0 = origin.advanced(by: .seconds(10) + .milliseconds(125)) }
        await spinner.stop(success: true)
        #expect(output.withLock { $0.last?.hasSuffix("First preparation Done in 125ms\n") } == true)

        instant.withLock { $0 = origin.advanced(by: .seconds(100)) }
        await spinner.start(message: "Second preparation")
        instant.withLock { $0 = origin.advanced(by: .seconds(114)) }
        await spinner.stop(success: false)
        #expect(output.withLock { $0.last?.hasSuffix("Second preparation Done in 14s\n") } == true)
        #expect(output.withLock { $0.last?.contains("✗") } == true)
    }

    @Test func duplicateStartsAndStopsDoNotOverwriteTheTimingOrRenderExtraLines() async {
        let origin = ContinuousClock().now
        let instant = Mutex<ContinuousClock.Instant>(origin)
        let output = Mutex<[String]>([])
        let spinner = ConsoleSpinner(
            showsElapsed: true, interval: .seconds(3_600), now: { instant.withLock { $0 } },
            interactiveEnabled: { true }, write: { text in output.withLock { $0.append(text) } }
        )
        await spinner.start(message: "Preparation")
        instant.withLock { $0 = origin.advanced(by: .seconds(1)) }
        await spinner.start(message: "Ignored")
        instant.withLock { $0 = origin.advanced(by: .seconds(2)) }
        await spinner.stop(success: true)
        await spinner.stop(success: true)
        #expect(output.withLock { $0.count } == 2)
        #expect(output.withLock { $0.last?.hasSuffix("Preparation Done in 2s\n") } == true)
    }

    @Test func disabledInteractiveOutputRemainsSilentForTimedSpinners() async {
        let output = Mutex<[String]>([])
        let spinner = ConsoleSpinner(
            showsElapsed: true, interactiveEnabled: { false },
            write: { text in output.withLock { $0.append(text) } }
        )
        await spinner.start(message: "Preparation")
        #expect(await spinner.isRunning)
        await spinner.stop(success: true)
        #expect(await spinner.isRunning == false)
        #expect(output.withLock { $0.isEmpty })
    }

    @Test func testStartSetsIsRunningToTrue() async throws {
        let spinner = ConsoleSpinner()

        await spinner.start(message: "Testing...")

        let isRunning = await spinner.isRunning
        #expect(isRunning == true)

        await spinner.stop(success: true)
    }

    @Test func testStopSetsIsRunningToFalse() async throws {
        let spinner = ConsoleSpinner()

        await spinner.start(message: "Testing...")
        await spinner.stop(success: true)

        let isRunning = await spinner.isRunning
        #expect(isRunning == false)
    }

    @Test func testStopWithoutStartDoesNotCrash() async throws {
        let spinner = ConsoleSpinner()

        await spinner.stop(success: true)

        let isRunning = await spinner.isRunning
        #expect(isRunning == false)
    }

    @Test func testMultipleStartStopCycles() async throws {
        let spinner = ConsoleSpinner()

        await spinner.start(message: "First cycle")
        var isRunning = await spinner.isRunning
        #expect(isRunning == true)

        await spinner.stop(success: true)
        isRunning = await spinner.isRunning
        #expect(isRunning == false)

        await spinner.start(message: "Second cycle")
        isRunning = await spinner.isRunning
        #expect(isRunning == true)

        await spinner.stop(success: false)
        isRunning = await spinner.isRunning
        #expect(isRunning == false)
    }

    @Test func testStartWhileAlreadyRunningDoesNothing() async throws {
        let spinner = ConsoleSpinner()

        await spinner.start(message: "First message")
        await spinner.start(message: "Second message")

        let isRunning = await spinner.isRunning
        #expect(isRunning == true)

        await spinner.stop(success: true)
    }

    @Test func testStopWhileNotRunningDoesNothing() async throws {
        let spinner = ConsoleSpinner()

        await spinner.stop(success: true)
        await spinner.stop(success: false)

        let isRunning = await spinner.isRunning
        #expect(isRunning == false)
    }
}
