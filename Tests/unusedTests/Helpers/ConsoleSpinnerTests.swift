//
//  Created by Fernando Romiti on 25/01/2026.
//

import Testing
@testable import unused

struct ConsoleSpinnerTests {

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
