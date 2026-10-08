import ArgumentParser
import Foundation
import Synchronization
import Testing
@testable import unused

struct AnalyzeDiagnosticsTests {
    @Test func parsesThresholdAndKeepsExistingAnalysisOptions() throws {
        let command = try #require(try Unused.parseAsRoot([
            "analyze", "/project", "--file-count-warning-threshold", "2500", "--include-tests", "--no-color"
        ]) as? Analyze)
        #expect(command.fileCountWarningThreshold == 2_500)
        #expect(command.directory == "/project")
        #expect(command.includeTests)
        #expect(command.noColor)
        let defaults = try Analyze.parse([])
        #expect(defaults.fileCountWarningThreshold == 1_000)
    }

    @Test(arguments: ["0", "-1"])
    func rejectsNonpositiveThresholds(value: String) {
        #expect(throws: (any Error).self) {
            _ = try Analyze.parse(["--file-count-warning-threshold", value])
        }
    }

    @Test(arguments: [OutputFormat.console, .xcode])
    func warningsPrecedeAnalysisAndMemoryIsReportedAfterward(format: OutputFormat) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "func one() {}".write(to: directory.appendingPathComponent("One.swift"), atomically: true, encoding: .utf8)
        try "func two() {}".write(to: directory.appendingPathComponent("Two.swift"), atomically: true, encoding: .utf8)
        let reportFile = directory.appendingPathComponent(ReportService.reportFileName)
        let events = Mutex<[String]>([])
        let warnings = Mutex<[String]>([])
        let reports = Mutex<[String]>([])
        let diagnostics = AnalysisDiagnostics(
            warningPolicy: AnalysisWarningPolicy(fileCountThreshold: 2, homeDirectory: directory),
            memoryReporter: MemoryUsageReporter(readPeakResidentBytes: {
                let reportExists = FileManager.default.fileExists(atPath: reportFile.path)
                events.withLock { $0.append("memory: report exists = \(reportExists)") }
                return 10_485_760
            }),
            writeWarning: { message in
                warnings.withLock { $0.append(message) }
                let reportExists = FileManager.default.fileExists(atPath: reportFile.path)
                events.withLock { $0.append("warning: report exists = \(reportExists)") }
            },
            writeMemoryReport: { message, outputFormat in
                reports.withLock { $0.append("\(outputFormat.rawValue): \(message)") }
            }
        )
        let command = try Analyze.parse([
            directory.path, "--file-count-warning-threshold", "2", "--format", format.rawValue, "--no-color"
        ])
        try await command.run(diagnostics: diagnostics)
        #expect(warnings.withLock { $0.count } == 2)
        #expect(warnings.withLock { $0.first?.contains("home directory") } == true)
        #expect(warnings.withLock { $0.last?.contains("at least 2 Swift files") } == true)
        #expect(events.withLock { $0 } == [
            "warning: report exists = false", "warning: report exists = false", "memory: report exists = true"
        ])
        #expect(reports.withLock { $0 } == ["\(format.rawValue): Peak memory usage: 10.0 MiB (process peak RSS)"])
        let report = try ReportService.read(from: directory.path)
        #expect(Set(report.unused.map(\.name)) == ["one", "two"])
    }

    @Test func smallEmptyProjectsStillReportMemoryWithoutWarning() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let warnings = Mutex<[String]>([])
        let reports = Mutex<[String]>([])
        let diagnostics = AnalysisDiagnostics(
            memoryReporter: MemoryUsageReporter(readPeakResidentBytes: { nil }),
            writeWarning: { message in warnings.withLock { $0.append(message) } },
            writeMemoryReport: { message, _ in reports.withLock { $0.append(message) } }
        )
        let command = try Analyze.parse([directory.path, "--format", "xcode"])
        try await command.run(diagnostics: diagnostics)
        #expect(warnings.withLock { $0.isEmpty })
        #expect(reports.withLock { $0 } == ["Peak memory usage: unavailable"])
    }

    @Test func invalidDirectoryDoesNotProduceScanWarningsOrMemoryResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = Mutex<[String]>([])
        let diagnostics = AnalysisDiagnostics(
            writeWarning: { message in output.withLock { $0.append(message) } },
            writeMemoryReport: { message, _ in output.withLock { $0.append(message) } }
        )
        let command = try Analyze.parse([directory.path, "--format", "xcode"])
        await #expect(throws: ValidationError.self) {
            try await command.run(diagnostics: diagnostics)
        }
        #expect(output.withLock { $0.isEmpty })
    }
}
