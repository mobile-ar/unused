import Testing
import Foundation
import Synchronization
@testable import unused

struct SwiftAnalyzerProgressTests {
    @Test func tracksEveryCompletedFileInEachProjectPhase() async throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ["unusedFirst", "unusedSecond", "unusedThird"].map { name in
            try writeSource("func \(name)() {}", to: "\(name).swift", in: directory)
        }

        let result = await analyze(files, in: directory)
        let expectedUpdates = projectPhasePrefixes.flatMap { prefix in
            updates(prefix: prefix, remainingTimes: [.seconds(12), .seconds(3), .zero])
        }

        #expect(result.updates == expectedUpdates)
        #expect(result.finishedPrefixes == projectPhasePrefixes)
        try expectReport(result.report, in: directory, unusedNames: ["unusedFirst", "unusedSecond", "unusedThird"])
    }

    @Test func preparationFinishesBeforeTheInitialUsageFrameAndHasIndependentTiming() async throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try writeSource("struct Subject { var value: Int; func work() { print(value) } }", to: "Subject.swift", in: directory)
        let origin = ContinuousClock().now
        let instant = Mutex<ContinuousClock.Instant>(origin)
        let events = Mutex<[String]>([])
        let spinner = ConsoleSpinner(
            showsElapsed: true, interval: .seconds(3_600), now: { instant.withLock { $0 } },
            interactiveEnabled: { true }, write: { text in
                events.withLock { $0.append(text) }
                if text.contains("Preparing usage analysis..."), !text.contains("Done in") {
                    instant.withLock { $0 = origin.advanced(by: .seconds(12)) }
                }
            }
        )
        let analyzer = SwiftAnalyzer(
            directory: directory.path,
            swiftInterfaceClient: SwiftInterfaceClient(moduleInterfaceProvider: { _ in nil }),
            usagePreparationSpinnerFactory: { spinner },
            progressTrackerFactory: { total, prefix in
                events.withLock { $0.append("Created \(prefix)") }
                let start = instant.withLock { $0 }
                return ProgressTracker(
                    total: total, prefix: prefix,
                    elapsed: { start.duration(to: instant.withLock { $0 }) }, renderInterval: .zero,
                    render: { update in
                        events.withLock { $0.append(ProgressBarFormatter().render(update)) }
                        if update.prefix == "Collecting usage...", update.current == 0 {
                            instant.withLock { $0 = $0.advanced(by: .seconds(2)) }
                        }
                    },
                    finishLine: { events.withLock { $0.append("Finished \(prefix)") } }
                )
            }
        )
        let report = await analyzer.analyzeFiles([file])
        let output = events.withLock { $0 }
        let parameterFinish = try #require(output.firstIndex(of: "Finished Checking parameters..."))
        let preparationStart = try #require(output.firstIndex { $0.contains("Preparing usage analysis...") && !$0.contains("Done in") })
        let preparationFinish = try #require(output.firstIndex { $0.hasSuffix("Preparing usage analysis... Done in 12s\n") })
        let usageCreation = try #require(output.firstIndex(of: "Created Collecting usage..."))
        let initialUsage = try #require(output.firstIndex { $0.contains("Collecting usage...") && $0.hasSuffix("0.0% (0/1) ETA: calculating...") })
        let completedUsage = try #require(output.firstIndex { $0.contains("Collecting usage...") && $0.hasSuffix("100.0% (1/1) Done in 2s") })
        #expect(parameterFinish < preparationStart)
        #expect(preparationStart < preparationFinish)
        #expect(preparationFinish < usageCreation)
        #expect(usageCreation < initialUsage)
        #expect(initialUsage < completedUsage)
        #expect(output.filter { $0.contains("Preparing usage analysis...") }.count == 2)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".unused.json").path))
        #expect(report.allItems.contains { $0.name == "work" })
    }

    @Test func emptyInputsNeverCreateAPreparationSpinner() async throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let created = Mutex<Int>(0)
        let analyzer = SwiftAnalyzer(
            directory: directory.path,
            swiftInterfaceClient: SwiftInterfaceClient(moduleInterfaceProvider: { _ in nil }),
            usagePreparationSpinnerFactory: {
                created.withLock { $0 += 1 }
                return ConsoleSpinner(interactiveEnabled: { false })
            }
        )
        let report = await analyzer.analyzeFiles([])
        #expect(created.withLock { $0 } == 0)
        #expect(report.unused.isEmpty)
    }

    @Test func emptyInputDoesNotRenderFramesOrFinishProgressLines() async throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = await analyze([], in: directory)

        #expect(result.updates.isEmpty)
        #expect(result.finishedPrefixes.isEmpty)
        #expect(result.report.unused.isEmpty)
        try expectReport(result.report, in: directory, unusedNames: [])
    }

    @Test(arguments: [false, true])
    func failedReadsCountAsCompletedParsingAttempts(missing: Bool) async throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let validFile = try writeSource("func unusedValid() {}", to: "Valid.swift", in: directory)
        let failedFile = directory.appendingPathComponent("Failed.swift")
        if !missing {
            // Invalid UTF-8 makes reading fail without relying on file permissions.
            try Data([0xFF]).write(to: failedFile)
        }

        let result = await analyze([validFile, failedFile], in: directory)
        let expectedUpdates = updates(prefix: "Parsing files...", remainingTimes: [.seconds(6), .zero])
            + projectPhasePrefixes.dropFirst().flatMap { prefix in
                updates(prefix: prefix, remainingTimes: [.zero])
            }

        #expect(result.updates == expectedUpdates)
        #expect(result.finishedPrefixes == projectPhasePrefixes)
        try expectReport(result.report, in: directory, unusedNames: ["unusedValid"])
    }

    @Test func dependencyProtocolsHaveTheirOwnCompletedFileProgress() async throws {
        let directory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let projectFile = try writeSource("func unusedProject() {}", to: "Project.swift", in: directory)
        _ = try writeSource(
            "protocol DependencyRequirement {}",
            to: ".build/checkouts/Pkg/Sources/Protocol.swift",
            in: directory
        )

        let result = await analyze([projectFile], in: directory)
        var prefixes = projectPhasePrefixes
        prefixes.insert("Scanning dependency protocols...", at: 2)
        let expectedUpdates = prefixes.flatMap { prefix in
            updates(prefix: prefix, remainingTimes: [.zero])
        }

        #expect(result.updates == expectedUpdates)
        #expect(result.finishedPrefixes == prefixes)
        try expectReport(result.report, in: directory, unusedNames: ["unusedProject"])
    }

    private var projectPhasePrefixes: [String] {
        [
            "Parsing files...",
            "Analyzing protocols...",
            "Collecting declarations...",
            "Checking parameters...",
            "Collecting usage..."
        ]
    }

    private func makeProjectDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeSource(_ source: String, to path: String, in directory: URL) throws -> URL {
        let file = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private func analyze(
        _ files: [URL],
        in directory: URL
    ) async -> (report: Report, updates: [ProgressUpdate], finishedPrefixes: [String]) {
        let frames = Mutex<[ProgressUpdate]>([])
        let finishedPrefixes = Mutex<[String]>([])
        let analyzer = SwiftAnalyzer(
            directory: directory.path,
            progressTrackerFactory: { total, prefix in
                ProgressTracker(
                    total: total,
                    prefix: prefix,
                    elapsed: { .seconds(6) },
                    renderInterval: .zero,
                    render: { update in frames.withLock { $0.append(update) } },
                    finishLine: { finishedPrefixes.withLock { $0.append(prefix) } }
                )
            }
        )
        let report = await analyzer.analyzeFiles(files)
        return (report, frames.withLock { $0 }, finishedPrefixes.withLock { $0 })
    }

    private func updates(prefix: String, remainingTimes: [Duration]) -> [ProgressUpdate] {
        let initialUpdates: [ProgressUpdate] = prefix == "Collecting usage..." && !remainingTimes.isEmpty ? [
            ProgressUpdate(prefix: prefix, current: 0, total: remainingTimes.count, estimatedRemaining: nil, elapsed: .seconds(6))
        ] : []
        return initialUpdates + remainingTimes.enumerated().map { index, remaining in
            ProgressUpdate(
                prefix: prefix,
                current: index + 1,
                total: remainingTimes.count,
                estimatedRemaining: remaining,
                elapsed: .seconds(6)
            )
        }
    }

    private func expectReport(_ report: Report, in directory: URL, unusedNames: [String]) throws {
        #expect(report.unused.map(\.name).sorted() == unusedNames.sorted())
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".unused.json").path))
        let savedReport = try ReportService.read(from: directory.path)
        #expect(savedReport.unused == report.unused)
        #expect(savedReport.excluded == report.excluded)
        #expect(savedReport.options == report.options)
        #expect(savedReport.summary == report.summary)
    }
}
