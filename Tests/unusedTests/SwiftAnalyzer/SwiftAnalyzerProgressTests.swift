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
        remainingTimes.enumerated().map { index, remaining in
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
